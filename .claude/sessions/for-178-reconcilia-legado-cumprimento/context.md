# Context: FOR-178 — reconciliação LEGADO no nível do cumprimento

Card: https://linear.app/forjuris/issue/FOR-178

## Regras críticas do projeto (resumo de docs/technical-context/briefing/critical-rules.md)

- RLS sempre; RPCs `security definer` com GRANT explícito só pra `service_role, authenticated`
  (e REVOKE de `PUBLIC`/`anon` — erro já cometido no FOR-174).
- Busca/matching tolerante a formato: CNJ sempre comparado pelo `cnj_normalizado` (só dígitos).
- Valores em centavos (não tocado aqui).

## Motivação

~24.292 `incidentes` importados pelo legado (FOR-143, import de PDF/CSV) têm
`cumprimento_id IS NULL` e `processo_codigo LIKE 'LEGADO-%'`. A linha `processos` a que apontam
(`processo_codigo = LEGADO-<cnjNorm>`) guarda o CNJ do **cumprimento de sentença**, não da ação
original (raiz). Quando o crawler e-SAJ crawleia esse CNJ, `normalizeToRoot()` sobe até a raiz e
`persistTree` reconcilia legado→real só por `cnj_normalizado` da RAIZ — nunca casa com a linha
legado (que está um nível abaixo). Resultado: hierarquia nova correta em paralelo, linha legado
órfã e `incidentes.numero_depre` duplicado (uma linha sem `cumprimento_id`, outra com).

Exemplo real: DEPRE `0088499-12.2023.8.26.0500`, cumprimento `0016525-29.2022.8.26.0053`,
raiz real `0023830-02.2001.8.26.0053`.

## Meta

Ao persistir uma árvore crawleada, para cada `cumprimento` cujo CNJ tenha uma linha `processos`
LEGADO- com o mesmo `cnj_normalizado`: reapontar os incidentes/partes dessa linha legado para o
processo raiz real + o cumprimento real, apagar a linha legado e deixar o loop de incidentes
existente (`reconcileLegadoIncidente`) renomear/mergear o incidente legado com o real — ao final,
1 única linha `incidentes` por numero_depre, com `cumprimento_id` preenchido.

## Estratégia (acordada com o usuário — não é nova decisão)

1. RPC nova `merge_legado_processo_para_cumprimento(p_legado_processo_id, p_real_processo_id,
   p_real_cumprimento_id)` em `sql/2026-09-29_for178_merge_legado_processo_para_cumprimento.sql`.
2. `persistTree`: após upsert de cada cumprimento, chamar `reconcileLegadoCumprimento` e, se
   houve merge, recarregar o Map `incidentesLegadoDoProcesso` antes do loop de incidentes.
3. Idempotente (2º crawl = no-op).

## Validação

- Teste unitário novo (`node:test` via `tsx --test`) com fake in-memory do client Supabase
  (`t.mock.method(supabase, "from"/"rpc")`), simulando as RPCs em JS.
- Sandbox Postgres local (`sql/sandbox/for178_validate_local.sh`) aplicando a RPC real e
  reproduzindo o caso DEPRE 0088499-12.2023.8.26.0500.

## Fora de escopo

- Enfileirar o backfill dos ~24k CNJs (produção/terceiro — aprovação separada).
- `leads_processos` e call-sites do FOR-177/177d.
- Deploy no worker da VPS / aplicar SQL em produção.

## Dependências / limitações

- `config.legadoReconcile` (env `LEGADO_RECONCILE`) continua sendo o gate de toda reconciliação.
- Depende de a RPC ser aplicada no SQL Editor ANTES do deploy do worker (senão o crawl falha ao
  achar uma linha legado de cumprimento — erro "function ... does not exist").
