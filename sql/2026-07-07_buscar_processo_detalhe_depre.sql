-- FOR-70 — Detalhe do processo: além de processo/incidentes/partes/andamentos,
-- traz o bloco `depre` = ficha + andamentos do(s) requisitório(s) .0500 (djen_depre)
-- referenciado(s) pelo numero_depre dos incidentes deste processo. Cada item vem
-- marcado com incidente_id para o frontend anexar ao incidente certo.
-- Pré-requisito: 2026-07-07_depre_requisitorio_ficha.sql. Aplicar no SQL Editor.

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
                     from public.andamentos a where a.incidente_id in (select id from incs)), '[]'::jsonb),
    -- requisitório(s) .0500 vinculados por numero_depre → ficha + andamentos da DEPRE
    'depre',        coalesce((select jsonb_agg(jsonb_build_object(
                       'incidente_id', i.id,
                       'cnj', dd.cnj,
                       'valor_acao', dd.valor_acao,
                       'status', dd.status,
                       'classe', dd.classe,
                       'data_base', dd.data_base,
                       'devedora', dd.devedora,
                       'origem_cnjs', dd.origem_cnjs,
                       'andamentos', coalesce(dd.andamentos, '[]'::jsonb),
                       'ficha_crawled_at', dd.ficha_crawled_at))
                     from public.incidentes i
                     join public.djen_depre dd
                       on dd.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
                     where i.processo_id = (select processo_id from raiz)
                       and i.numero_depre is not null), '[]'::jsonb)
  );
$$;

grant execute on function public.buscar_processo_detalhe(uuid) to anon, authenticated;
