# Context: FOR-159 — Persistir "acordo homologado" (.0500) como flag consultável

## Card Linear
https://linear.app/forjuris/issue/FOR-159

## Contexto (motivação)

Em 2026-09-13, durante uma auditoria manual de deals (planilha de negócios/CRM vs.
banco), o usuário confirmou ao vivo — via print do e-SAJ — que o processo `.0500`
0180464-42.2021.8.26.0500 tinha o andamento **"Comunicado de Acordo de Requisitório"**
(30/07/2026) numa tabela chamada **"Petições diversas"**, separada da tabela
"Movimentação" (`#tabelaTodasMovimentacoes`). O crawler só lia a tabela de
"Movimentação" — nunca "Petições diversas" — então esse tipo de acordo nunca era
persistido em `djen_depre.andamentos`, mesmo pra esse caso confirmado.

**Causa raiz já corrigida** (commit `2f36e91`, já deployado na VPS de produção):
`worker-crawler/src/parse.ts` ganhou `extractPeticoesDiversas()`, mesclada em
`crawl.ts:crawlRequisitorio()` antes do upsert em `djen_depre.andamentos`. Testado
contra o HTML real do e-SAJ e confirmado extraindo corretamente o andamento do
exemplo acima.

O que falta (escopo desta issue) é: (a) expandir o backfill retroativo pra TODOS os
`.0500` já crawleados (hoje só ~1670 de um lote específico foram re-crawleados), e
(b) persistir o resultado como um flag booleano consultável — hoje o dado só existe
dentro do jsonb `djen_depre.andamentos`, sem forma direta de filtrar/exibir.

## Meta (resultado esperado)

- `djen_depre` ganha uma coluna `acordo_homologado` (boolean, nullable — ver decisão
  de schema abaixo) que reflete se aquele `.0500` teve o andamento "Comunicado de
  Acordo de Requisitório" na tabela "Petições diversas".
- A coluna é calculada automaticamente toda vez que `persistRequisitorio()` roda
  (crawl novo ou re-crawl), sem trabalho manual futuro.
- Todos os `.0500` já existentes em `djen_depre` (56.761 registros) são re-crawleados
  em algum momento (via fila, `origem='backfill'`, sem competir com trabalho
  prioritário) pra que a coluna deixe de ser `null` pra eles.
- Isso desbloqueia FOR-160 (admin) e FOR-161 (e-mail/site público), que vão consumir
  essa coluna via JOIN por `numero_depre`.

## Estratégia (direcional, sem detalhes de implementação)

1. Migration via script SQL avulso em `sql/` (convenção real do projeto desde
   FOR-102/~julho — `supabase/migrations/` está parado desde junho/FOR-76): adiciona
   a coluna `acordo_homologado boolean` (nullable) em `djen_depre`.
2. Código: `worker-crawler/src/supabase.ts:persistRequisitorio()` passa a computar o
   flag a partir do array `andamentos` já montado (mesmo filtro validado em
   `sql/2026-09-13_diag_acordo_depre.sql`: `btrim(descricao) ilike 'Comunicado de
   Acordo de Requisit%'`) e incluir no `row` do upsert.
3. Backfill imediato (parte do mesmo script SQL ou um script separado): para
   `.0500` que JÁ têm `andamentos` populado por um crawl feito DEPOIS do deploy de
   hoje (2026-09-13, commit `2f36e91`), computar `acordo_homologado` direto do jsonb
   existente — sem precisar de novo crawl.
4. Enfileirar o restante da base (`.0500` cujo `andamentos` ainda não passou pelo
   parser novo) com `origem='backfill'` — despriorizado por design em
   `claim_crawler_jobs` (ver `sql/2026-08-16_for143_claim_prioriza_nao_backfill.sql`),
   pra não repetir o incidente desta mesma sessão em que um backfill de 56.761 jobs
   `origem='manual'` foi parar na frente de tudo por engano.

## Decisão de schema (fechada no /engineer:start)

`acordo_homologado boolean NULL` (sem `DEFAULT false`) — `null` = "ainda não
verificado com o parser novo"; `true`/`false` = resultado real depois do re-crawl.
Evita o problema apontado em FOR-160: sem essa distinção, todo `.0500` ainda não
re-crawleado apareceria como "Não" por falta de dado, não porque de fato não teve
acordo.

## APIs/ferramentas novas?

Nenhuma. Reusa: `djen_depre` (tabela existente), `crawler_queue` +
`enqueue_crawler_job_forcado`/`claim_crawler_jobs` (RPCs existentes),
`extractPeticoesDiversas()` (já implementada e deployada).

## Validação

- Unit: já validado manualmente nesta sessão contra HTML real capturado do e-SAJ
  (extractPeticoesDiversas extraiu corretamente os 3 itens esperados, incluindo o
  "Comunicado de Acordo de Requisitório").
- Pós-migration: reaproveitar `sql/2026-09-13_diag_acordo_depre.sql` (já teria a
  lógica de filtro certa) pra conferir uma amostra de `.0500` conhecidos (o exemplo
  confirmado 0180464-42.2021.8.26.0500 deve vir `acordo_homologado = true`).
- Status do backfill: reaproveitar padrão de
  `sql/2026-09-13_status_recrawl_1670_depres.sql` (agrupar por
  `acordo_homologado is null` vs não-null pra medir progresso).

## Dependências

- Nenhuma dependência de outra issue. FOR-159 é a base — FOR-160 e FOR-161 dependem
  dela (não o contrário).
- Deploy do parser (commit `2f36e91`) já feito na VPS — pré-requisito já satisfeito.

## Limitações

- Sem acesso direto ao Postgres de produção nesta sessão (sem `.env`/credenciais
  locais, sem `supabase login` configurado) — toda alteração de schema e todo
  backfill em massa continuam sendo entregues como script `.sql` pro usuário aplicar
  manualmente no SQL Editor do Supabase, como em toda esta sessão até aqui.
- O backfill completo dos ~55 mil `.0500` restantes não é instantâneo — depende do
  throughput real do worker-crawler (~235 jobs/h observado historicamente), então
  pode levar dias até `acordo_homologado` deixar de ser `null` pra base inteira.
