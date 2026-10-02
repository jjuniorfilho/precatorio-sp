# Context: FOR-196 — cumprimento sintético gravando cnj=null

Card: https://linear.app/forjuris/issue/FOR-196/cumprimento-de-sentenca-em-branco-pra-347k-incidentes

Issue discovery-first: diagnóstico já cravado (arquivo:linha + causa raiz + SQL de backfill
validado) no próprio card, achado ao investigar o refinamento da FOR-195. Este contexto
documenta o que já estava diagnosticado, não uma investigação nova.

## Regras críticas do projeto (resumo de docs/technical-context/briefing/critical-rules.md, quando aplicável)

- Valores em centavos — não tocado aqui (campo é `cnj`, texto).
- Migrations em `sql/2026-MM-DD_forNNN_descrição.sql`, aplicadas manualmente no SQL Editor.
- Mudança de schema/dado em produção sempre validada antes num Postgres local descartável
  (`sql/sandbox/*.sh`) — nunca só "deveria funcionar".

## Motivação

`worker-crawler/src/crawl.ts` monta a árvore e-SAJ em 3 níveis: processo (raiz) → cumprimento
(execução de sentença) → incidente (precatório/RPV). Quando a execução corre **no próprio
processo**, sem uma página de cumprimento separada no e-SAJ (incidentes pendurados direto na
raiz, ou raiz sem nada — só cálculo homologado), o crawler cria um "cumprimento sintético"
(`processo_codigo: "{root}#cumprimento"`) para manter a hierarquia. Nas linhas 141 e 148-149,
esse cumprimento sintético gravava `cnj: null` em vez do CNJ da própria raiz (`capa.cnj`, já
extraído por `extractCapa(root.$)` na linha 89) — não havia motivo para ser null, o dado já
estava disponível.

Impacto medido (read-only, confirmado pelo achado da issue): 126.388 dos 298.691 `cumprimentos`
tinham `cnj is null`, afetando 347.482 `incidentes` (quase metade da base de ~761k) — campo
"Cumprimento de Sentença" aparecia em branco quando deveria mostrar o mesmo número do processo
principal.

## Meta

1. Corrigir o crawler (`cnj: null` → `cnj: capa.cnj` nas duas ramificações) para que novos
   crawls nasçam certos.
2. Backfill via UPDATE único em `cumprimentos` (join por `incidentes.processo_id` →
   `processos.cnj`) para os 126.388 já gravados errados — **sem recrawl**, confirmado seguro
   (0% desses cumprimentos pertence a um `processos` ainda LEGADO-, i.e. `processos.cnj` é
   sempre confiável).

## Estratégia (já definida no card — não é decisão nova)

- Fix de 2 linhas em `crawl.ts` (literal `null` → `capa.cnj`, variável já em escopo).
- 1 migration SQL idempotente em `sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql`.
- Teste novo cobrindo o cenário "cumprimento sintético herda capa.cnj" (não existia teste
  nenhum para `crawlSeed` — as dependências de rede, esaj.js/comunica.js/supabase.js, são
  mockadas via `mock.module`, node:test; roda via `npm run test:module-mocks`, script novo e
  opt-in — o `npm test` default continua em Node ≥20 sem flag experimental, os 2 testes novos
  só se auto-pulam (skip) quando o flag não está ativo).
- Script de validação local do backfill: `sql/sandbox/for196_validate_local.sh` (Postgres 15
  descartável, schema sintético mínimo de `processos`/`cumprimentos`/`incidentes`).

## Fora de escopo

- FOR-195 (ação principal real acima do cumprimento — caso menor, ~24k incidentes legado, esse
  sim exige recrawl). Separado por design no próprio card.
- Aplicar a migration em produção / deploy do worker na VPS — fica para o humano após o merge.

## Dependências / limitações

- A migration deve ser aplicada **depois** do deploy do fix do crawler (ordem não é crítica
  aqui, ao contrário do FOR-178 — o backfill não depende de o crawler já estar corrigido, e o
  crawler corrigido não depende da migration já ter rodado; são independentes).
- `--experimental-test-module-mocks` existe só a partir do Node 22.3 — por isso ficou num
  script `test:module-mocks` separado, não no `npm test` default (que o README do worker
  declara "Node ≥20").
