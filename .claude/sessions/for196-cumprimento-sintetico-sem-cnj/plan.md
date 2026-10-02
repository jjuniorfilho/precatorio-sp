# FOR-196 — cumprimento sintético gravando cnj=null

Plano pequeno (issue mecânica, diagnóstico já cravado no card — ver context.md). 2 fases,
auto-aprovadas em modo autônomo (sem decisão de produto/arquitetura nova; única escolha de
tooling de teste documentada em architecture.md).

## FASE 1 — Fix do crawler + teste de regressão [Completada ✅]

### Trocar `cnj: null` por `cnj: capa.cnj` nas 2 ramificações de cumprimento sintético [Completada ✅]

`worker-crawler/src/crawl.ts` linha 141 (incidentes pendurados direto na raiz) e linhas 148-149
(raiz sem nada, placeholder). Variável `capa` já em escopo (extraída na linha 89 via
`extractCapa(root.$)`, antes de ambas as ramificações).

### Teste novo cobrindo as 2 ramificações [Completada ✅]

`worker-crawler/src/crawl-cumprimento-sintetico.test.ts` — não havia teste nenhum para
`crawlSeed` (orquestração com rede); mocka `esaj.js`/`comunica.js`/`supabase.js` via
`mock.module` (node:test nativo) e dirige por HTML sintético. Rodado ANTES do fix (RED,
confirma que pega a regressão: `actual null`, `expected <CNJ>`) e DEPOIS (GREEN, 2/2).

### Comentários:
- `mock.module` exige `--experimental-test-module-mocks`, só em Node ≥22.3. Para não elevar o
  piso de Node do `npm test` default (README do worker diz "Node ≥20"), criei um script opt-in
  `test:module-mocks` em `package.json` — os 2 testes novos se auto-pulam (skip) sob o `npm
  test` padrão (sem o flag) em vez de falhar. Documentado em architecture.md como a única
  escolha de engenharia feita sem aprovação prévia (tooling de teste, não produção).
- Suite completa (`npm test`) tem 1 teste pré-existente intermitente/flaky, não relacionado
  (`supabase-persist-tree-legado.test.ts`, FOR-178 idempotência, comparação de timestamp em
  milissegundos) — confirmado reproduzindo em ~1 a cada 3 rodadas MESMO sem tocar aquele
  arquivo. Não é regressão desta mudança.

## FASE 2 — Backfill SQL + validação local [Completada ✅]

### Migration de backfill [Completada ✅]

`sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql` — UPDATE único (padrão já
validado no card), preenche `cumprimentos.cnj` a partir de `processos.cnj` via `incidentes`,
só onde `cnj is null`.

### Script de validação local [Completada ✅]

`sql/sandbox/for196_validate_local.sh` — Postgres 15 descartável, schema sintético mínimo
(`processos`/`cumprimentos`/`incidentes`), 3 cenários (sintético com 2 incidentes, cumprimento
"de verdade" já preenchido — não pode ser sobrescrito, sintético sem incidente associado — fica
null mesmo) e 2 rodadas (prova idempotência: nada muda na 2ª, sem duplicar linha). Rodado e
confirmado: todos os `✔`, nenhum `✘`.

### Comentários:
- Migration e fix de código são independentes entre si — ordem de deploy não importa (ao
  contrário do FOR-178, onde a RPC precisava vir antes do worker).
- Aplicar a migration em produção fica para o humano, fora do escopo deste PR (igual ao
  padrão dos demais `sql/2026-*_forNNN_*.sql` do repo — preparados, não aplicados pelo agente).
