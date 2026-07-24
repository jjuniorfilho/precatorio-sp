-- FOR-107 (fix 2) — dois ajustes no grid agrupado de /admin/processos:
--
-- 1) Clicar num badge do totalizador "descobertos hoje/últimos 7 dias" não restringia por
--    data nenhuma — os dois cards (hoje/semana) chamam o MESMO handler de toggle, então
--    "Incidente instaurado: 65 (hoje)" filtrava por fase='incidente' em TODO o histórico,
--    não só nos 65 descobertos hoje. Adiciona p_created_de/p_created_ate (janela de
--    descoberta, incidentes.created_at) pra fechar esse gap — o front passa a diferenciar
--    qual card foi clicado.
--
-- 2) Troca o filtro "Último andamento" (andamentos.data, sem relação com a fase atual) por
--    "Nesta fase desde" (incidentes.fase_desde — data em que o processo entrou na fase
--    atual, já existente desde a revisão da FOR-72). Quando combinado com p_fase, filtra
--    pela data de entrada NAQUELA fase especificamente.
--
-- Precisa recriar a function porque a assinatura muda (remove p_andamento_de/ate).
-- Aplicar no SQL Editor.

create index if not exists idx_incidentes_created_at on public.incidentes (created_at);
create index if not exists idx_incidentes_fase_desde on public.incidentes (fase_desde);

drop function if exists public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
);

create function public.buscar_processos_agrupado(
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
       and (p_fase      is null or p_fase = any(m.fases_presentes))
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
       -- "Nesta fase desde": quando p_fase também está setado, restringe a data de entrada
       -- NAQUELA fase especificamente (mesmo espírito da FOR-72: data do último marco que
       -- definiu a fase atual, não qualquer andamento avulso).
       and ((p_fase_desde_de is null and p_fase_desde_ate is null) or m.processo_id in (
             select i.processo_id from public.incidentes i
              where (p_fase is null or i.fase = p_fase)
                and (p_fase_desde_de  is null or i.fase_desde >= p_fase_desde_de)
                and (p_fase_desde_ate is null or i.fase_desde <= p_fase_desde_ate)
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

grant execute on function public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer
) to anon, authenticated;
