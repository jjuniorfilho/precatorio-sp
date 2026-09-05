-- FOR-143 — R8 do code-review: claim_crawler_jobs (sql/2026-08-16_for143_claim_prioriza_nao_
-- backfill.sql) ordena por `CASE WHEN origem='backfill' THEN 1 ELSE 0 END, scheduled_at`, mas
-- o índice existente (idx_crawler_queue_claim em (status, scheduled_at)) não cobre essa
-- expressão — cada claim (a cada ~15s) reordena a fila pendente inteira em memória. Barato
-- hoje (~12k pendentes), mas cresce com a fila. Índice parcial casando a mesma expressão do
-- ORDER BY, coberto pelo mesmo predicado (status='pendente') do WHERE.
--
-- Re-executável. Aplicar no SQL Editor.

create index if not exists idx_crawler_queue_claim_prioridade
  on crawler_queue ((origem = 'backfill'), scheduled_at)
  where status = 'pendente';

-- Verificação (rodar após aplicar):
-- explain select id from crawler_queue where status='pendente' and scheduled_at <= now()
--  order by (origem = 'backfill'), scheduled_at limit 25 for update skip locked;
-- -- esperado: Index Scan usando idx_crawler_queue_claim_prioridade (não Seq Scan + Sort)
