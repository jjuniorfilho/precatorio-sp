-- FOR-143 — CORREÇÃO URGENTE: enqueue_stale_processos() enfileira qualquer processos
-- flag_sp com next_crawl_at NULL ou vencido. O import do CSV legado gravou next_crawl_at=NULL
-- nos ~12.126 processos "LEGADO-" (placeholder, sem código real do e-SAJ), com a intenção de
-- que NUNCA fossem enfileirados pelo refresh automático (só pelo enqueue de backfill manual do
-- próprio script). Só que classify_processo() (chamado logo depois, em todo insert) SEMPRE
-- sobrescreve next_crawl_at = COALESCE(last_crawled_at, NOW()) + TTL — com last_crawled_at
-- NULL, isso vira NOW()+7 dias. Confirmado em produção: todos os LEGADO- estão com
-- next_crawl_at ≈ 2026-08-24.
--
-- Sem esse fix, a partir de ~24/08 o cron horário (refresh-stale-hourly) vai enfileirar os
-- 12.126 códigos "LEGADO-..." com origem='refresh'. O worker não reconhece esse prefixo como
-- CNJ nem como código e-SAJ válido → crawlSeed falha sempre → fail_crawler_job reseta pra
-- 'pendente' → próxima hora reenfileira tudo de novo → loop infinito. Pior: 'refresh' tem
-- prioridade MAIOR que 'backfill' (sql/2026-08-16_for143_claim_prioriza_nao_backfill.sql), então
-- isso também travaria os 12.124 jobs de backfill legítimos do FOR-143 pra sempre, e lotes com
-- alta taxa de erro disparam o circuit breaker do worker (index.ts), degradando dje_diario junto.
--
-- Fix: excluir processo_codigo LIKE 'LEGADO-%' do CTE `stale`. Idêntica à definição original
-- (FOR-73/FOR-112) exceto por essa exclusão. Re-executável. Aplicar no SQL Editor O QUANTO ANTES
-- (antes de 2026-08-23).

create or replace function public.enqueue_stale_processos()
returns int
language plpgsql security definer set search_path = public as $$
declare v_run uuid; n int := 0;
begin
  if not coalesce((select enabled from coleta_config where rotina='refresh'), true) then
    return 0;
  end if;
  insert into coleta_runs (rotina, status) values ('refresh','running') returning id into v_run;
  with stale as (
    select processo_codigo from processos
     where flag_sp
       and (next_crawl_at is null or next_crawl_at <= now())
       and processo_codigo not like 'LEGADO-%'
  ), ins as (
    insert into crawler_queue (processo_codigo, origem)
    select processo_codigo, 'refresh' from stale
    on conflict do nothing
    returning 1
  )
  select count(*) into n from ins;
  update coleta_runs set status='sucesso', finished_at=now(), itens_ok=n where id=v_run;
  return n;
end; $$;

-- Verificação (rodar após aplicar):
-- select count(*) from processos where flag_sp and processo_codigo like 'LEGADO-%'
--   and (next_crawl_at is null or next_crawl_at <= now() + interval '7 days');
-- -- esse número (deve ser ~12k) NUNCA deve aparecer em crawler_queue com origem='refresh':
-- select count(*) from crawler_queue where origem='refresh' and processo_codigo like 'LEGADO-%';
-- -- esperado: 0, antes e depois de rodar select enqueue_stale_processos();

-- Limpeza (só se algum job LEGADO- já tiver entrado na fila antes deste fix ser aplicado):
-- delete from crawler_queue where processo_codigo like 'LEGADO-%' and origem='refresh' and status='pendente';
