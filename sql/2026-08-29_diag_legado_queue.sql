-- Diagnóstico do incidente agudo do crawler_esaj (circuit-breaker travando desde 26/08):
-- fila crawler_queue sendo inundada por processo_codigo='LEGADO-*' (placeholder do import
-- FOR-143), que nunca resolve no e-SAJ. O plan.md da sessão FOR-143 registra um fix aplicado
-- em 19/08 (sql/2026-08-19_for143_exclui_legado_do_refresh.sql, exclui LEGADO- do
-- enqueue_stale_processos), mas o padrão voltou — preciso ver (a) o volume atual por
-- origem/status e (b) se esse fix ainda está de fato na função em produção.
--
-- Read-only, sem efeito colateral. Aplicar no SQL Editor.

-- 1) Volume de lixo LEGADO- na fila, por origem/status.
create or replace function public.diag_legado_queue()
returns table(origem text, status text, n bigint, mais_antigo timestamptz, mais_recente timestamptz)
language sql stable security definer set search_path = public
as $$
  select origem, status, count(*), min(created_at), max(created_at)
    from crawler_queue
   where processo_codigo like 'LEGADO-%'
   group by 1, 2
   order by 3 desc;
$$;

grant execute on function public.diag_legado_queue() to anon, authenticated;

-- 2) Código-fonte atual de enqueue_stale_processos (confirmar se a exclusão de 19/08 ainda
-- está lá). Função nomeada/escopada pra só isso — não expõe fonte de função arbitrária.
create or replace function public.diag_enqueue_stale_processos_source()
returns text
language sql stable security definer set search_path = public
as $$
  select pg_get_functiondef('public.enqueue_stale_processos'::regproc);
$$;

grant execute on function public.diag_enqueue_stale_processos_source() to anon, authenticated;
