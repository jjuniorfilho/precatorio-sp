-- FOR-179 (achado durante o code-review do FOR-178) — HOTFIX DE SEGURANÇA CRÍTICO.
--
-- As RPCs merge_legado_processo / merge_legado_incidente (FOR-143,
-- sql/2026-08-19_for143_merge_legado_rpcs.sql, agosto) nasceram com EXECUTE liberado pra PUBLIC
-- e anon. Confirmado em produção via `pg_proc.proacl`:
--   merge_legado_processo:  {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
--   merge_legado_incidente: {=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}
-- ("=X/postgres" é PUBLIC; "anon=X/postgres" é o anon key, que é PÚBLICO — embutido no bundle
-- JS do frontend, qualquer visitante do site tem acesso a ele).
--
-- As duas são SECURITY DEFINER (rodam com privilégio elevado, RLS não se aplica) e
-- `merge_legado_processo` faz `delete from processos where id = p_legado_id` SEM checar se a
-- linha é de fato um placeholder "LEGADO-" — um caller anônimo podia chamar essa RPC passando o
-- id de QUALQUER processo real como p_legado_id e apagá-lo (cascata pra tabelas dependentes via
-- FK ON DELETE CASCADE). Rota de destruição de dados em massa sem autenticação.
--
-- Mesmo erro do FOR-174 (upsert_precatorios_pagamentos nasceu sem REVOKE, corrigido no FOR-174b)
-- — a migration de agosto nunca rodou REVOKE depois do CREATE FUNCTION, e toda função nova
-- nasce com EXECUTE liberado pra PUBLIC por padrão no Postgres.
--
-- Fix:
--  1. REVOKE de PUBLIC/anon nas duas (mesmo padrão do FOR-174b).
--  2. Guarda "só age se a linha for LEGADO-%" em ambas — mesma defesa que a RPC nova do FOR-178
--     (merge_legado_processo_para_cumprimento) já nasceu com. Defesa em profundidade: mesmo que
--     um caller autorizado (authenticated/service_role) erre o id por engano, a função nunca
--     apaga uma linha real.
--
-- `authenticated` continua com EXECUTE de propósito — é o worker da VPS (crawler roda logado
-- via ADMIN_EMAIL/PASSWORD quando não tem service_role_key, ver worker-crawler/src/supabase.ts).
--
-- Aplicar no SQL Editor. Re-executável.

create or replace function public.merge_legado_processo(p_legado_id uuid, p_real_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_id = p_real_id then return; end if;
  if not exists (
    select 1 from processos where id = p_legado_id and processo_codigo like 'LEGADO-%'
  ) then
    return;
  end if;
  update incidentes set processo_id = p_real_id where processo_id = p_legado_id;
  update partes     set processo_id = p_real_id where processo_id = p_legado_id;
  delete from processos where id = p_legado_id;
end; $$;

create or replace function public.merge_legado_incidente(p_legado_id uuid, p_real_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_id = p_real_id then return; end if;
  if not exists (
    select 1 from incidentes where id = p_legado_id and processo_codigo like 'LEGADO-%'
  ) then
    return;
  end if;
  delete from partes     where incidente_id = p_legado_id;
  delete from andamentos where incidente_id = p_legado_id;
  delete from incidentes where id = p_legado_id;
end; $$;

revoke all on function public.merge_legado_processo(uuid, uuid)  from public, anon;
revoke all on function public.merge_legado_incidente(uuid, uuid) from public, anon;
grant execute on function public.merge_legado_processo(uuid, uuid)  to service_role, authenticated;
grant execute on function public.merge_legado_incidente(uuid, uuid) to service_role, authenticated;

-- Verificação (rodar manualmente após aplicar):
-- select proname, proacl from pg_proc where proname in ('merge_legado_processo','merge_legado_incidente');
-- (esperado: proacl SEM "=X/" solto nem "anon=X/")
