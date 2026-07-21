-- FOR-76 — Refresh agendado da mv_advogado_carteira (totais do dashboard de advogados).
-- Problema: a MV é um snapshot; só atualizava ao reaplicar a migration à mão. Com o
-- crawler/DJEN ingerindo todo dia, os totais (n_processos, valor_total, mix, fases)
-- ficavam congelados.
--
-- Solução: pg_cron diário com REFRESH ... CONCURRENTLY (não trava leitura — o /admin lê
-- via buscar_advogados / buscar_advogado_detalhe enquanto refresca).
--
-- Timing: o DJEN roda na VPS às 08:10 UTC e só ENFILEIRA; o crawler (pm2) drena a fila
-- depois. Por isso o refresh é às 12:00 UTC (09:00 BRT) — ~4h de folga p/ o crawler.
-- Ajuste o horário no cron.schedule se a fila demorar mais a drenar.
-- Aplicar no SQL Editor do Supabase.

-- 1. Índice único (pré-requisito do CONCURRENTLY). adv_key é a chave do group by → único.
create unique index if not exists mv_advogado_carteira_adv_key_uidx
  on public.mv_advogado_carteira (adv_key);

-- 2. Função wrapper (mantém o command do cron simples e versionável).
create or replace function public.refresh_mv_advogado_carteira()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.mv_advogado_carteira;
end;
$$;

-- 3. Agendamento pg_cron — diário 12:00 UTC (09:00 BRT). Horários do pg_cron são UTC.
create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule('refresh-mv-advogado-carteira');
exception when others then null; -- ainda não existe na 1ª aplicação
end $$;

select cron.schedule(
  'refresh-mv-advogado-carteira',
  '0 12 * * *',
  $$select public.refresh_mv_advogado_carteira();$$
);

-- Conferir: select jobname, schedule, command from cron.job where jobname = 'refresh-mv-advogado-carteira';
