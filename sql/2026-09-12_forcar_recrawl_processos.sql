-- Enfileira um processo IGNORANDO o guard de "ainda fresco" (next_crawl_at > now())
-- que o enqueue_crawler_job normal respeita. Uso: depois de um fix no parser (aqui,
-- FOR-156/157 — extractPartes perdia credores conjuntos, ver conversa) e é preciso
-- forçar o re-crawl de processos JÁ 'ok' pra pegar o dado corrigido, sem esperar o
-- próximo ciclo natural de refresh.
--
-- INSERT direto na tabela (via authenticated) bate em RLS (42501) — só RPC
-- security definer passa, mesmo padrão do enqueue_crawler_job/priorizar_jobs_manual.
-- Aplicar no SQL Editor.

create or replace function public.enqueue_crawler_job_forcado(p_processo_codigo text, p_origem text default 'manual')
returns void
language plpgsql security definer set search_path = public
as $$
begin
  insert into crawler_queue (processo_codigo, origem)
  values (p_processo_codigo, p_origem)
  on conflict do nothing; -- já tem job aberto pra esse processo_codigo → ok, ignora
end;
$$;

grant execute on function public.enqueue_crawler_job_forcado(text, text) to anon, authenticated;
