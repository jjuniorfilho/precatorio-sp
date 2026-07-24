-- FOR-107 (fix 3) — "Fase mais avançada"/"Nesta fase desde" no grid mostram sempre o
-- agregado do PROCESSO INTEIRO (o incidente mais adiantado do pipeline), mas os filtros
-- p_fase/p_fase_desde_de/ate casavam com QUALQUER incidente do processo — resultado: um
-- processo podia aparecer filtrado por "fase=incidente, fase_desde em 2020" mostrando
-- "Fase mais avançada: Ordem cronológica · desde 2025-12-05" na tela, porque o incidente
-- que bateu o filtro nem era o mesmo que aparece na linha. Confirmado com o processo
-- 0051085-21.2007.8.26.0506 (6.095 incidentes) — o que exibia é de um incidente #257/#281
-- (fase=oc), o que batia o filtro estava perdido em algum lugar dos outros milhares.
--
-- Fix: p_fase e p_fase_desde_de/ate passam a filtrar as MESMAS colunas pré-computadas que
-- são exibidas (m.fase_mais_avancada / m.fase_desde) em vez de "algum incidente do
-- processo tem essa fase" — o que é filtrado sempre bate com o que aparece na tela.
--
-- Aplica só no corpo da function (assinatura não muda) — CREATE OR REPLACE basta.
-- Aplicar no SQL Editor.

create or replace function public.buscar_processos_agrupado(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_created_de date default null, p_created_ate date default null,
  p_limit integer default 25, p_offset integer default 0)
returns table(
  processo_id uuid, cnj text, processo_codigo text, ente_nome text, ente_esfera text,
  status text, n_incidentes bigint, fase_mais_avancada text, fase_desde date,
  valor_total bigint, has_more boolean)
language sql stable security definer set search_path = public
as $function$
  with filtrado as (
    select m.*
      from public.mv_processos_agrupado m
     where (p_esfera    is null or m.ente_esfera = p_esfera)
       -- Filtra pela MESMA coluna que a tela exibe (fase mais avançada do processo), não
       -- por "algum incidente tem essa fase" — o que aparece sempre bate com o que filtrou.
       and (p_fase      is null or m.fase_mais_avancada = p_fase)
       and (p_fase_desde_de  is null or m.fase_desde >= p_fase_desde_de)
       and (p_fase_desde_ate is null or m.fase_desde <= p_fase_desde_ate)
       and (p_tipo      is null or p_tipo = any(m.tipos_presentes))
       and (p_macrofase is null or p_macrofase = any(m.macrofases_presentes))
       and (p_status    is null or m.status_presentes && string_to_array(p_status, ','))
       and (p_elegivel  is null or (p_elegivel and m.tem_elegivel_true) or (not p_elegivel and m.tem_elegivel_false))
       -- filtros abaixo continuam "ao vivo" (semi-join não correlacionado — o planner resolve
       -- o subselect uma vez via índice, não linha a linha).
       and (p_q is null or m.processo_id in (
             select i.processo_id from public.incidentes i
              where i.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
                 or regexp_replace(coalesce(i.numero_depre,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
             union
             select i2.processo_id from public.incidentes i2
             join public.partes d on d.incidente_id = i2.id
              where d.documento ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
             union
             select p2.id from public.processos p2
              where regexp_replace(coalesce(p2.cnj,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
           ))
       and (p_valor_min is null or m.processo_id in (
             select i.processo_id from public.incidentes i where i.valor_acao >= p_valor_min))
       and (p_valor_max is null or m.processo_id in (
             select i.processo_id from public.incidentes i where i.valor_acao <= p_valor_max))
       and (p_advogado is null or m.processo_id in (
             select i.processo_id from public.incidentes i
             join public.partes a on a.incidente_id = i.id
              where a.papel='ativa'
                and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g'))
                    ilike '%'||btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g'))||'%'
           ))
       and (p_oab is null or m.processo_id in (
             select i.processo_id from public.incidentes i
             join public.partes a on a.incidente_id = i.id
              where a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))
           ))
       -- Janela de descoberta (created_at) — liga o clique nos badges "hoje"/"últimos 7
       -- dias" do totalizador a uma restrição de data real, em vez de só filtrar por fase.
       and ((p_created_de is null and p_created_ate is null) or m.processo_id in (
             select i.processo_id from public.incidentes i
              where (p_created_de  is null or i.created_at >= (p_created_de::timestamp at time zone 'America/Sao_Paulo'))
                and (p_created_ate is null or i.created_at < ((p_created_ate + 1)::timestamp at time zone 'America/Sao_Paulo'))
           ))
  ),
  page as (
    select * from filtrado
     order by valor_total desc nulls last
     limit greatest(p_limit,1) + 1 offset greatest(p_offset,0)
  ),
  paged as (
    select * from page limit greatest(p_limit,1)
  )
  select pg.processo_id, pg.cnj, pg.processo_codigo, pg.ente_nome, pg.ente_esfera, pg.status,
         pg.n_incidentes, pg.fase_mais_avancada, pg.fase_desde, pg.valor_total,
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg
   order by pg.valor_total desc nulls last;
$function$;
