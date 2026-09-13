-- FOR-159, Fase 3 — enfileira o restante dos .0500 cujo acordo_homologado ainda
-- é null (ou seja, ainda não foram recrawleados com o parser que lê "Petições
-- diversas", commit 2f36e91). Depois de sql/2026-09-13_for159_acordo_homologado_
-- coluna.sql, isso é ~55.630 registros (contagem do momento em que a coluna foi
-- criada — pode já ter mudado um pouco pelo backfill anterior desta mesma sessão).
--
-- IMPORTANTE (lição do incidente desta mesma sessão, mais cedo hoje): usa
-- origem='backfill', NUNCA 'manual'. claim_crawler_jobs despriorizada jobs
-- origem='backfill' (sempre por último, ver sql/2026-08-16_for143_claim_
-- prioriza_nao_backfill.sql); 'manual' não é despriorizado e um lote deste
-- tamanho (~55k) tomaria a frente de qualquer trabalho real (ingestão DJEN
-- diária, consultas ad-hoc) por potencialmente dias, do jeito que aconteceu
-- com sql/2026-09-13_forca_recrawl_peticoes_diversas_depre.sql antes de ser
-- corrigido em sql/2026-09-13_corrige_prioridade_recrawl_0500.sql.
--
-- Sem chamada a priorizar_jobs_manual aqui de propósito — backfill não deve
-- furar fila. Throughput histórico observado ~235 jobs/h; aceitável levar
-- vários dias até acordo_homologado deixar de ser null pra base inteira.
--
-- Idempotente: enqueue_crawler_job_forcado ignora (ON CONFLICT DO NOTHING) CNJs
-- que já têm job aberto (pendente/processando) — inclusive os que já foram
-- rebaixados pra origem='backfill' em sql/2026-09-13_corrige_prioridade_
-- recrawl_0500.sql mais cedo hoje.
--
-- Aplicar no SQL Editor.

with alvo as (
  select cnj
    from djen_depre
   where acordo_homologado is null
),
-- materialized explícito: `enqueue_crawler_job_forcado` é volátil (returns void),
-- então o efeito colateral (INSERT em crawler_queue) só acontece por a CTE não
-- inlinar — deixar explícito evita depender de um comportamento implícito do
-- planner num script que grava ~55k linhas.
processados as materialized (
  select public.enqueue_crawler_job_forcado(cnj, 'backfill') from alvo
)
-- total_processado, não "total_enfileirado": a função é ON CONFLICT DO NOTHING,
-- então isso conta quantos CNJs foram considerados (== count(alvo)), não quantos
-- jobs novos de fato entraram na fila (esses já existentes são no-op silencioso).
select count(*) as total_processado
  from processados;
