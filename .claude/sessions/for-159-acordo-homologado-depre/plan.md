<plan>
# FOR-159 — Persistir "acordo homologado" (.0500) como flag consultável

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

## FASE 1 — Schema + backfill imediato [Completada ✅]

Cria a coluna e popula o que já dá pra popular sem nenhum novo crawl (os `.0500`
cujo `andamentos` já foi persistido pelo parser novo, commit `2f36e91`, hoje).

### Migration: `sql/2026-09-13_for159_acordo_homologado_coluna.sql` [Completada ✅]

- `ALTER TABLE djen_depre ADD COLUMN IF NOT EXISTS acordo_homologado boolean;`
  (sem `DEFAULT` — novas linhas nascem `null` até o crawl calcular; ver decisão em
  architecture.md).
- `UPDATE djen_depre SET acordo_homologado = exists(select 1 from
  jsonb_array_elements(andamentos) elem where btrim(elem->>'descricao') ilike
  'Comunicado de Acordo de Requisit%') WHERE ficha_crawled_at >= '2026-09-13'::date;`
  — só atualiza quem já foi (re)crawleado com o parser novo (usa `ficha_crawled_at`,
  não a mera presença de `andamentos`, pra não confundir "verificado, sem acordo"
  com "nunca verificado" — ver Limitações do architecture.md).
- Comentário no script explicando a causa raiz (mesmo texto de
  `sql/2026-09-13_diag_acordo_depre.sql`) e "Aplicar no SQL Editor".

### Verificação manual (comentário no fim do script) [Completada ✅]

`select cnj, acordo_homologado from djen_depre where cnj_normalizado =
'01804644220218260500';` — esperado `true` (0180464-42.2021.8.26.0500, o exemplo
confirmado pelo usuário). Incluído como comentário no fim do script, junto com uma
segunda query de progresso (`acordo_homologado is null` vs total).

### Comentários:
- Script ainda NÃO aplicado no banco (sem acesso direto ao Postgres de produção
  nesta sessão) — aguardando o usuário rodar no SQL Editor e validar antes de
  seguir pra Fase 2.
- `add column if not exists` + `where ... and acordo_homologado is null` no UPDATE
  tornam o script idempotente (pode rodar de novo sem efeito colateral se algo
  falhar no meio).

## FASE 2 — Cálculo automático em todo crawl futuro [Não Iniciada ⏳]

Garante que todo `.0500` (re)crawleado a partir de agora — não só o backfill —
já venha com `acordo_homologado` certo, sem depender de rodar SQL manual de novo.

### `worker-crawler/src/supabase.ts:persistRequisitorio()` [Não Iniciada ⏳]

- Computar `acordo_homologado` a partir do array `andamentos` já montado (mesmo
  filtro do backfill, em TS: `andamentos.some(a => /^comunicado de acordo de
  requisit/i.test(a.descricao.trim()))`).
- Incluir `acordo_homologado` no objeto `row` do upsert (linha ~318, ao lado de
  `andamentos`).

### Teste [Não Iniciada ⏳]

- Novo caso em `worker-crawler/src/parse.test.ts` (ou arquivo dedicado) cobrindo:
  (a) `andamentos` com o item "Comunicado de Acordo de Requisitório" → `true`;
  (b) `andamentos` sem esse item (mas com outros) → `false`; (c) `andamentos`
  vazio → `false` (foi verificado, só não tinha nada).
- Rodar `npm test` no worker-crawler antes de seguir.

### Comentários:
-

## FASE 3 — Backfill do restante da base (~55k) [Não Iniciada ⏳]

Enfileira, sem atropelar prioridade, o resto dos `.0500` que ainda não passaram
pelo parser novo (ficam `acordo_homologado = null` até serem processados).

### `sql/2026-09-13_for159_enfileira_backfill_restante.sql` [Não Iniciada ⏳]

- Seleciona `cnj` de `djen_depre` onde `acordo_homologado is null` (ou
  `ficha_crawled_at < '2026-09-13'`, pra pegar quem nunca foi recrawleado desde o
  fix).
- Enfileira via `enqueue_crawler_job_forcado(cnj, 'backfill')` — **`origem=
  'backfill'`, não `'manual'`** (lição do incidente de hoje mais cedo nesta mesma
  sessão: `origem='manual'` não é despriorizada por `claim_crawler_jobs`).
- **Não** chama `priorizar_jobs_manual` — backfill não deve furar fila.
- Comentário explicando throughput esperado (~235 jobs/h histórico) e que é
  aceitável levar dias.

### Script de status (read-only): `sql/2026-09-13_for159_status_backfill.sql` [Não Iniciada ⏳]

- `select acordo_homologado is null as pendente, count(*) from djen_depre group by
  1;` — pra acompanhar o progresso do backfill ao longo dos dias seguintes.

### Comentários:
-

</plan>
