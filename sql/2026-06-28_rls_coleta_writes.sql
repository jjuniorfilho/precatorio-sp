-- FOR-70 — RLS de escrita nas tabelas de controle da coleta.
-- O worker autentica como admin (role authenticated). Estas tabelas tinham RLS ligada
-- SEM policy de escrita → writes falhavam (42501) silenciosamente:
--   - djen_dias: idempotência por dia nunca pegava (re-processava tudo)
--   - coleta_runs: nenhum run registrado (observabilidade vazia)
--   - eproc_pendentes: roteamento eproc não persistia
-- Aplicar no SQL Editor.

-- djen_dias (+ índice único em `data` p/ o onConflict do upsert)
alter table public.djen_dias enable row level security;
drop policy if exists djen_dias_authenticated_all on public.djen_dias;
create policy djen_dias_authenticated_all on public.djen_dias
  for all to authenticated using (true) with check (true);
create unique index if not exists djen_dias_data_uidx on public.djen_dias (data);

-- coleta_runs
alter table public.coleta_runs enable row level security;
drop policy if exists coleta_runs_authenticated_all on public.coleta_runs;
create policy coleta_runs_authenticated_all on public.coleta_runs
  for all to authenticated using (true) with check (true);

-- eproc_pendentes
alter table public.eproc_pendentes enable row level security;
drop policy if exists eproc_pendentes_authenticated_all on public.eproc_pendentes;
create policy eproc_pendentes_authenticated_all on public.eproc_pendentes
  for all to authenticated using (true) with check (true);
