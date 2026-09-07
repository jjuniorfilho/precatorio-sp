-- FOR-108 — RPCs pra observabilidade do worker-crawler em /admin/coleta.
--
-- Descoberta ao construir isso: a tela ATUAL já está quebrada — coleta_runs, coleta_config,
-- djen_dias e crawler_queue são lidos via SELECT direto (.from(...).select(...)) no
-- frontend, e RLS bloqueia tudo silenciosamente pro role anon (confirmado empiricamente:
-- todos retornam array vazio, sem erro). sql/2026-06-30_coleta_anon_select.sql tinha a
-- intenção de liberar isso mas não criou policy permissiva de fato (só GRANT não basta com
-- RLS habilitado). Esta migração substitui TODOS os reads dessas 4 tabelas por RPCs
-- security definer — mesmo padrão já validado hoje em reset_orfaos_crawler_queue /
-- listar_incidentes_para_refresh.
--
-- Aplicar no SQL Editor.

-- 1) Contagem da fila por status (substitui getQueueStats, que fazia 4 counts diretos)
create or replace function public.crawler_queue_status_counts()
returns table(status text, n bigint)
language sql stable security definer set search_path = public
as $function$
  select status, count(*) from crawler_queue group by status;
$function$;

grant execute on function public.crawler_queue_status_counts() to anon, authenticated;

-- 2) Ritmo de processamento: média/hora e total nas últimas 24h (status='ok'), + buckets
-- horários das últimas 24h pro sparkline. updated_at é tocado por complete_crawler_job.
create or replace function public.crawler_ritmo_processamento()
returns table(total_24h bigint, media_por_hora numeric, hora timestamptz, n_hora bigint)
language sql stable security definer set search_path = public
as $function$
  with base as (
    select date_trunc('hour', updated_at) as hora
      from crawler_queue
     where status = 'ok' and updated_at >= now() - interval '24 hours'
  ),
  por_hora as (
    select hora, count(*) as n from base group by hora
  ),
  totais as (
    select coalesce(sum(n), 0)::bigint as total_24h, coalesce(round(avg(n), 1), 0) as media_por_hora from por_hora
  )
  select t.total_24h, t.media_por_hora, p.hora, p.n
    from totais t
    left join por_hora p on true
   order by p.hora;
$function$;

grant execute on function public.crawler_ritmo_processamento() to anon, authenticated;

-- 3) coleta_runs — substitui getColetaRuns; p_rotina filtra (usado pra restarts/circuit
-- breaker/refresh-ativos além da tabela geral que já existia).
create or replace function public.coleta_runs_recentes(p_rotina text default null, p_limit integer default 20)
returns table(
  id uuid, rotina text, started_at timestamptz, finished_at timestamptz,
  status text, itens_ok integer, itens_erro integer, duracao_ms integer, detalhe jsonb)
language sql stable security definer set search_path = public
as $function$
  select id, rotina, started_at, finished_at, status, itens_ok, itens_erro, duracao_ms, detalhe
    from coleta_runs
   where p_rotina is null or rotina = p_rotina
   order by started_at desc
   limit greatest(p_limit, 1);
$function$;

grant execute on function public.coleta_runs_recentes(text, integer) to anon, authenticated;

-- 4) coleta_config — substitui getColetaConfig (as rotinas ligadas/desligadas)
create or replace function public.coleta_config_listar()
returns table(rotina text, enabled boolean, params jsonb)
language sql stable security definer set search_path = public
as $function$
  select rotina, enabled, params from coleta_config;
$function$;

grant execute on function public.coleta_config_listar() to anon, authenticated;

-- 5) setar enabled — substitui o UPDATE direto de setRotinaEnabled (mesmo motivo)
create or replace function public.coleta_config_set_enabled(p_rotina text, p_enabled boolean)
returns boolean
language plpgsql security definer set search_path = public
as $$
begin
  update coleta_config set enabled = p_enabled where rotina = p_rotina;
  return found;
end;
$$;

grant execute on function public.coleta_config_set_enabled(text, boolean) to anon, authenticated;

-- 6) djen_dias — substitui getDjenDias
create or replace function public.djen_dias_recentes(p_limit integer default 7)
returns table(data date, status text, total integer, flagueados integer, enfileirados integer, eproc integer, processado_em timestamptz)
language sql stable security definer set search_path = public
as $function$
  select data, status, total, flagueados, enfileirados, eproc, processado_em
    from djen_dias
   order by data desc
   limit greatest(p_limit, 1);
$function$;

grant execute on function public.djen_dias_recentes(integer) to anon, authenticated;
