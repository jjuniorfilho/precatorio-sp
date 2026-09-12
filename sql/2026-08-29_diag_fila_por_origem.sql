-- Diagnóstico: volume pendente por origem, pra entender por que jobs 'manual' recém-criados
-- não estão sendo drenados mesmo com o crawler saudável (LEGADO- já purgado).
-- Read-only. Aplicar no SQL Editor.

create or replace function public.diag_fila_por_origem()
returns table(origem text, status text, n bigint, scheduled_mais_antigo timestamptz, scheduled_mais_recente timestamptz)
language sql stable security definer set search_path = public
as $$
  select origem, status, count(*), min(scheduled_at), max(scheduled_at)
    from crawler_queue
   group by 1, 2
   order by 2, 3 desc;
$$;

grant execute on function public.diag_fila_por_origem() to anon, authenticated;
