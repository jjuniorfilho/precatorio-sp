-- FOR-143 — Import do CSV legado vai enfileirar ~28k jobs `origem='backfill'` de uma vez pra
-- complementar os registros importados via crawl real. claim_crawler_jobs hoje ordena só por
-- scheduled_at (FIFO puro) — um volume desse tamanho, todo com scheduled_at=NOW() no momento
-- do enqueue, ficaria à frente de qualquer job dje_diario/manual/refresh que chegue depois
-- (scheduled_at maior = ordenado depois), potencialmente atrasando descoberta diária e ações
-- interativas do usuário (ex.: consulta OAB ad-hoc) por dias.
--
-- Fix: origem='backfill' sempre por último na ordenação, independente de scheduled_at — só
-- consome capacidade ociosa da fila. Reusável por qualquer backfill futuro, não só este.
--
-- Idêntica à definição original (FOR-73, supabase/migrations/20260627195519_for73_fila_
-- crons_monitor.sql) exceto pelo ORDER BY. Re-executável (CREATE OR REPLACE). Aplicar no SQL
-- Editor.

create or replace function public.claim_crawler_jobs(p_limit int)
returns setof crawler_queue
language sql security definer set search_path = public as $$
  update crawler_queue q
     set status='processando', claimed_at=now(), updated_at=now()
   where q.id in (
     select id from crawler_queue
      where status='pendente' and scheduled_at <= now()
      order by case when origem = 'backfill' then 1 else 0 end, scheduled_at
      for update skip locked
      limit p_limit
   )
  returning q.*;
$$;

-- Verificação (rodar manualmente após aplicar; limpar os jobs de teste em seguida):
-- insert into crawler_queue (processo_codigo, origem, scheduled_at, status) values
--   ('TESTE-FOR143-backfill', 'backfill', now() - interval '1 hour', 'pendente'),
--   ('TESTE-FOR143-manual',   'manual',   now(),                     'pendente');
-- select processo_codigo, origem from claim_crawler_jobs(1);
-- -- esperado: TESTE-FOR143-manual (mesmo sendo mais recente que o backfill)
-- update crawler_queue set status='ok' where processo_codigo like 'TESTE-FOR143-%';
-- delete from crawler_queue where processo_codigo like 'TESTE-FOR143-%';
