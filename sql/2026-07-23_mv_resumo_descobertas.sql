-- FOR-105 — Pré-calcula resumo_descobertas (totalizadores "descobertos hoje/últimos 7
-- dias" do admin/processos) via materialized view + pg_cron, em vez de agregar ao vivo a
-- cada carregamento de tela. A function resumo_descobertas() estourava statement timeout
-- (57014) mesmo com índice em incidentes.created_at e MATERIALIZED nas CTEs — causa raiz é
-- estrutural: agregar sobre dezenas de milhares de linhas (backfill ativo — ~13% da tabela
-- de incidentes foi criada nos últimos 7 dias) sempre custa alguns segundos, não some só
-- com índice. Mesmo padrão já usado pra mv_advogado_carteira (FOR-76) — REFRESH
-- CONCURRENTLY não trava leitura durante o refresh. Aplicar no SQL Editor.

create materialized view if not exists public.mv_resumo_descobertas as
  with base as (
    select i.tipo_previsto, i.fase, coalesce(p.ente_esfera,'Outro') as esfera, i.created_at
      from public.incidentes i
      join public.processos p on p.id = i.processo_id
     where p.flag_sp
       and i.created_at >= (date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo') - interval '6 days'
  ),
  per as (
    select 'dia'::text as periodo, tipo_previsto, fase, esfera from base
      where created_at >= (date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo')
    union all
    select 'semana'::text, tipo_previsto, fase, esfera from base
  )
  select periodo, 'total'::text as dimensao, 'total'::text as chave, count(*) as n from per group by periodo
  union all select periodo, 'esfera', esfera, count(*) from per group by periodo, esfera
  union all select periodo, 'instrumento', coalesce(tipo_previsto,'Indefinido'), count(*) from per group by periodo, tipo_previsto
  union all select periodo, 'fase', coalesce(fase,'(sem fase)'), count(*) from per group by periodo, fase;

-- Índice único — pré-requisito pra REFRESH CONCURRENTLY. (periodo, dimensao, chave)
-- identifica cada linha de forma única (mesma chave composta que o frontend já pivota).
create unique index if not exists mv_resumo_descobertas_uidx
  on public.mv_resumo_descobertas (periodo, dimensao, chave);

-- Leitura pública — mesmo dado que já era exposto via RPC a anon/authenticated.
-- Materialized view não suporta RLS; GRANT simples já basta (não tem dado sensível/pessoal).
grant select on public.mv_resumo_descobertas to anon, authenticated;

create or replace function public.refresh_mv_resumo_descobertas()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.mv_resumo_descobertas;
end;
$$;

create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule('refresh-mv-resumo-descobertas');
exception when others then null; -- ainda não existe na 1ª aplicação
end $$;

-- A cada 15 min — "hoje/últimos 7 dias" é mais sensível a tempo que o refresh diário do
-- advogado (FOR-76); ajustar se ficar pesado demais rodar com essa frequência.
select cron.schedule(
  'refresh-mv-resumo-descobertas',
  '*/15 * * * *',
  $$select public.refresh_mv_resumo_descobertas();$$
);

-- Conferir: select jobname, schedule, command from cron.job where jobname = 'refresh-mv-resumo-descobertas';
