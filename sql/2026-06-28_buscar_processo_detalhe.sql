-- FOR-74 — Detalhe do processo via RPC (SECURITY DEFINER), espelhando buscar_processos.
-- Motivo: a área /admin é anônima (sem login); o detalhe fazia SELECT direto em
-- processos/incidentes/partes/andamentos, que a RLS bloqueia para anon → "não encontrado".
-- A lista já contorna isso via RPC. Esta função faz o mesmo p/ o detalhe e NÃO expõe
-- partes.documento (CPF/CNPJ) — LGPD.
-- Aplicar no SQL Editor do Supabase.

create or replace function public.buscar_processo_detalhe(p_incidente_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with raiz as (
    select pr.id as processo_id
    from public.incidentes i
    join public.processos pr on pr.id = i.processo_id
    where i.id = p_incidente_id
  ),
  incs as (
    select id from public.incidentes where processo_id = (select processo_id from raiz)
  )
  select jsonb_build_object(
    'processo',     (select to_jsonb(pr) from public.processos pr where pr.id = (select processo_id from raiz)),
    'cumprimentos', coalesce((select jsonb_agg(to_jsonb(c))
                     from public.cumprimentos c where c.processo_id = (select processo_id from raiz)), '[]'::jsonb),
    'incidentes',   coalesce((select jsonb_agg(to_jsonb(i))
                     from public.incidentes i where i.processo_id = (select processo_id from raiz)), '[]'::jsonb),
    -- projeção explícita: omite partes.documento (CPF/CNPJ)
    'partes',       coalesce((select jsonb_agg(jsonb_build_object(
                       'id', pt.id, 'incidente_id', pt.incidente_id, 'papel', pt.papel,
                       'nome', pt.nome, 'advogado_nome', pt.advogado_nome, 'oab', pt.oab))
                     from public.partes pt where pt.incidente_id in (select id from incs)), '[]'::jsonb),
    'andamentos',   coalesce((select jsonb_agg(to_jsonb(a) order by a.data desc nulls last)
                     from public.andamentos a where a.incidente_id in (select id from incs)), '[]'::jsonb)
  );
$$;

grant execute on function public.buscar_processo_detalhe(uuid) to anon, authenticated;
