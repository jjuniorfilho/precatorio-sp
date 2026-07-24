-- FOR-112 (parte 2) — expõe o OC calculado (ver 2026-07-24_for112_oc_calculado.sql) nas
-- duas telas: filtro `p_ano_oc` em buscar_processos_agrupado/buscar_processos_incidente/
-- contar_processos_incidente, e coluna `anos_oc_presentes` no grid agrupado (um processo
-- pode ter incidentes com OC diferente — mesmo padrão de `fases_presentes`/`tipos_presentes`
-- já usado pra macrofase/fase/tipo, agregado por processo).
--
-- Aplicar DEPOIS de 2026-07-24_for112_oc_calculado.sql e depois da reclassificação em
-- massa (senão a MV materializa ano_oc ainda nulo/antigo pra tudo). Aplicar no SQL Editor.

-- -------------------------------------------------------------
-- 1) mv_processos_agrupado — recriada com anos_oc_presentes.
-- -------------------------------------------------------------
drop materialized view if exists public.mv_processos_agrupado;

create materialized view public.mv_processos_agrupado as
  with enriquecido as (
    select i.id as incidente_id, i.processo_id, i.tipo_previsto, i.fase, i.fase_desde,
           i.status, i.elegivel, i.macrofase, i.ano_oc,
           coalesce(dd.valor_acao, i.valor_acao) as valor_incidente,
           case i.fase
             when 'oc' then 8 when 'oficio' then 7 when 'depre' then 6
             when 'oficio_deferido' then 5 when 'termo' then 4 when 'incidente' then 3
             when 'calculo' then 2 when 'inicial' then 1 else 0
           end as fase_rank
      from public.incidentes i
      join public.processos p on p.id = i.processo_id
      left join public.djen_depre dd
        on i.numero_depre is not null
       and dd.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
     where p.flag_sp
  )
  select e.processo_id,
         p.cnj, p.processo_codigo, p.ente_nome, p.ente_esfera, p.status,
         count(*)::bigint as n_incidentes,
         sum(e.valor_incidente)::bigint as valor_total,
         (array_agg(e.fase order by e.fase_rank desc, e.fase_desde desc nulls last))[1] as fase_mais_avancada,
         (array_agg(e.fase_desde order by e.fase_rank desc, e.fase_desde desc nulls last))[1] as fase_desde,
         array_agg(distinct e.fase) filter (where e.fase is not null) as fases_presentes,
         array_agg(distinct e.tipo_previsto) filter (where e.tipo_previsto is not null) as tipos_presentes,
         array_agg(distinct e.status) filter (where e.status is not null) as status_presentes,
         array_agg(distinct e.macrofase) filter (where e.macrofase is not null) as macrofases_presentes,
         array_agg(distinct e.ano_oc) filter (where e.ano_oc is not null) as anos_oc_presentes,
         bool_or(e.elegivel is true) as tem_elegivel_true,
         bool_or(e.elegivel is false) as tem_elegivel_false
    from enriquecido e
    join public.processos p on p.id = e.processo_id
   group by e.processo_id, p.cnj, p.processo_codigo, p.ente_nome, p.ente_esfera, p.status;

create unique index mv_processos_agrupado_uidx on public.mv_processos_agrupado (processo_id);
create index mv_processos_agrupado_esfera_idx on public.mv_processos_agrupado (ente_esfera);
create index mv_processos_agrupado_valor_idx on public.mv_processos_agrupado (valor_total desc nulls last);
create index mv_processos_agrupado_fases_gin on public.mv_processos_agrupado using gin (fases_presentes);
create index mv_processos_agrupado_tipos_gin on public.mv_processos_agrupado using gin (tipos_presentes);
create index mv_processos_agrupado_status_gin on public.mv_processos_agrupado using gin (status_presentes);
create index mv_processos_agrupado_macrofases_gin on public.mv_processos_agrupado using gin (macrofases_presentes);
create index mv_processos_agrupado_anos_oc_gin on public.mv_processos_agrupado using gin (anos_oc_presentes);

grant select on public.mv_processos_agrupado to anon, authenticated;

-- refresh_mv_processos_agrupado() e o agendamento pg_cron (a cada 30min) já existem e
-- referenciam a MV pelo nome — não precisam ser recriados (ver 2026-07-23_mv_processos_
-- agrupado.sql). Refresh manual imediato pra não esperar até 30min de janela:
select public.refresh_mv_processos_agrupado();

-- -------------------------------------------------------------
-- 2) buscar_processos_agrupado — + p_ano_oc + retorna anos_oc_presentes.
-- -------------------------------------------------------------
drop function if exists public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer,text
);

create or replace function public.buscar_processos_agrupado(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_created_de date default null, p_created_ate date default null,
  p_limit integer default 25, p_offset integer default 0,
  p_ente_devedor text default null, p_ano_oc integer default null)
returns table(
  processo_id uuid, cnj text, processo_codigo text, ente_nome text, ente_esfera text,
  status text, n_incidentes bigint, fase_mais_avancada text, fase_desde date,
  valor_total bigint, has_more boolean, total_processos bigint, crawler_status text,
  anos_oc_presentes integer[])
language sql stable security definer set search_path = public
as $function$
  with filtrado as (
    select m.*
      from public.mv_processos_agrupado m
     where (p_esfera    is null or m.ente_esfera = p_esfera)
       and (p_fase      is null or m.fase_mais_avancada = p_fase)
       and (p_fase_desde_de  is null or m.fase_desde >= p_fase_desde_de)
       and (p_fase_desde_ate is null or m.fase_desde <= p_fase_desde_ate)
       and (p_tipo      is null or p_tipo = any(m.tipos_presentes))
       and (p_macrofase is null or p_macrofase = any(m.macrofases_presentes))
       and (p_status    is null or m.status_presentes && string_to_array(p_status, ','))
       and (p_elegivel  is null or (p_elegivel and m.tem_elegivel_true) or (not p_elegivel and m.tem_elegivel_false))
       and (p_ano_oc    is null or p_ano_oc = any(m.anos_oc_presentes))
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
                    ilike '%'||btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g'))||'%'))
       and (p_oab is null or m.processo_id in (
             select i.processo_id from public.incidentes i
             join public.partes a on a.incidente_id = i.id
              where a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
       and (p_ente_devedor is null or m.processo_id in (
             select pp.processo_id from public.partes pp where pp.papel = 'passiva' and pp.nome = p_ente_devedor))
       and ((p_created_de is null and p_created_ate is null) or m.processo_id in (
             select i.processo_id from public.incidentes i
              where (p_created_de  is null or i.created_at >= (p_created_de::timestamp at time zone 'America/Sao_Paulo'))
                and (p_created_ate is null or i.created_at < ((p_created_ate + 1)::timestamp at time zone 'America/Sao_Paulo'))
           ))
  ),
  total as (
    select count(*) as n from filtrado
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
         (select count(*) from page) > greatest(p_limit,1) as has_more,
         (select n from total) as total_processos,
         (select cq.status from public.crawler_queue cq where cq.processo_codigo = pg.cnj order by cq.updated_at desc limit 1) as crawler_status,
         pg.anos_oc_presentes
    from paged pg
   order by pg.valor_total desc nulls last;
$function$;

grant execute on function public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer,text,integer
) to anon, authenticated;

-- -------------------------------------------------------------
-- 3) buscar_processos_incidente — + p_ano_oc (ano_oc já era retornado, só falta filtro).
-- -------------------------------------------------------------
drop function if exists public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text
);

create or replace function public.buscar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_limit integer default 50, p_offset integer default 0,
  p_ente_devedor text default null, p_ano_oc integer default null)
returns table(
  incidente_id uuid, cumprimento_cnj text, numero_incidente text, numero_depre text,
  parte_ativa text, parte_passiva text, valor_acao bigint,
  fase text, fase_desde date, status text,
  tipo_previsto text, macrofase text, elegivel boolean, possivelmente_pago boolean,
  ordem_cronologica boolean, tramitacao_prioritaria boolean, ano_oc integer,
  saldo_depre bigint, valor_pago bigint,
  titular_nome text, titular_documento text,
  data_base date, data_ultimo_andamento date,
  crawler_status text,
  has_more boolean)
language sql
security definer
set search_path to 'public'
as $function$
  with base as (
    select i.id as incidente_id,
           coalesce(c.cnj, p.cnj) as cumprimento_cnj,
           p.cnj as processo_cnj,
           i.numero_incidente, i.numero_depre, i.valor_acao,
           i.fase, i.fase_desde, i.status,
           i.tipo_previsto, i.macrofase, i.elegivel, i.possivelmente_pago,
           i.ordem_cronologica, i.tramitacao_prioritaria, i.ano_oc, i.data_base,
           p.ente_nome as parte_passiva
      from incidentes i
      join processos p on p.id = i.processo_id
      left join cumprimentos c on c.id = i.cumprimento_id
     where p.flag_sp
       and (p_esfera    is null or p.ente_esfera = p_esfera)
       and (p_tipo      is null or i.tipo_previsto = p_tipo)
       and (p_fase      is null or i.fase = p_fase)
       and (p_macrofase is null or i.macrofase = p_macrofase)
       and (p_status    is null or i.status = p_status)
       and (p_valor_min is null or i.valor_acao >= p_valor_min)
       and (p_valor_max is null or i.valor_acao <= p_valor_max)
       and (p_elegivel  is null or i.elegivel = p_elegivel)
       and (p_fase_desde_de  is null or i.fase_desde >= p_fase_desde_de)
       and (p_fase_desde_ate is null or i.fase_desde <= p_fase_desde_ate)
       and (p_ano_oc is null or i.ano_oc = p_ano_oc)
       and (p_ente_devedor is null or i.processo_id in (
             select pp.processo_id from partes pp where pp.papel = 'passiva' and pp.nome = p_ente_devedor))
       and (p_q is null or i.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or p.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or regexp_replace(coalesce(i.numero_depre,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or exists (select 1 from partes d where d.incidente_id = i.id and d.documento ilike '%'||regexp_replace(p_q,'\D','','g')||'%'))
       and (p_advogado is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa'
              and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g'))
                  ilike '%'||btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g'))||'%'))
       and (p_oab is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
  ),
  page as (
    select b.* from base b
     order by b.valor_acao desc nulls last
     limit greatest(p_limit,1) + 1 offset greatest(p_offset,0)
  ),
  paged as (
    select * from page limit greatest(p_limit,1)
  )
  select pg.incidente_id, pg.cumprimento_cnj, pg.numero_incidente, pg.numero_depre,
         (select nome from partes where incidente_id=pg.incidente_id and papel='ativa' and nome is not null limit 1) as parte_ativa,
         pg.parte_passiva,
         pg.valor_acao,
         pg.fase, pg.fase_desde, pg.status,
         pg.tipo_previsto, pg.macrofase, pg.elegivel, pg.possivelmente_pago,
         pg.ordem_cronologica, pg.tramitacao_prioritaria, pg.ano_oc,
         (select max(saldo_depre) from precatorios where processo_depre = pg.numero_depre) as saldo_depre,
         (select sum(valor) from precatorios_pagamentos where processo_depre = pg.numero_depre) as valor_pago,
         (select titular_nome from djen_depre where cnj_normalizado = regexp_replace(coalesce(pg.numero_depre,''),'\D','','g') limit 1) as titular_nome,
         (select titular_documento from djen_depre where cnj_normalizado = regexp_replace(coalesce(pg.numero_depre,''),'\D','','g') limit 1) as titular_documento,
         pg.data_base,
         (select max(a.data) from andamentos a where a.incidente_id = pg.incidente_id) as data_ultimo_andamento,
         (select cq.status from crawler_queue cq where cq.processo_codigo = pg.processo_cnj order by cq.updated_at desc limit 1) as crawler_status,
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg order by pg.valor_acao desc nulls last;
$function$;

grant execute on function public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer
) to anon, authenticated;

-- -------------------------------------------------------------
-- 4) contar_processos_incidente — + p_ano_oc (mesmo filtro, RPC assíncrona à parte).
-- -------------------------------------------------------------
drop function if exists public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,text
);

create or replace function public.contar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_ente_devedor text default null, p_ano_oc integer default null)
returns bigint
language sql stable security definer set search_path = public
as $function$
  select count(*)
    from incidentes i
    join processos p on p.id = i.processo_id
   where p.flag_sp
     and (p_esfera    is null or p.ente_esfera = p_esfera)
     and (p_tipo      is null or i.tipo_previsto = p_tipo)
     and (p_fase      is null or i.fase = p_fase)
     and (p_macrofase is null or i.macrofase = p_macrofase)
     and (p_status    is null or i.status = p_status)
     and (p_valor_min is null or i.valor_acao >= p_valor_min)
     and (p_valor_max is null or i.valor_acao <= p_valor_max)
     and (p_elegivel  is null or i.elegivel = p_elegivel)
     and (p_fase_desde_de  is null or i.fase_desde >= p_fase_desde_de)
     and (p_fase_desde_ate is null or i.fase_desde <= p_fase_desde_ate)
     and (p_ano_oc is null or i.ano_oc = p_ano_oc)
     and (p_ente_devedor is null or i.processo_id in (
           select pp.processo_id from partes pp where pp.papel = 'passiva' and pp.nome = p_ente_devedor))
     and (p_q is null or i.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
          or p.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
          or regexp_replace(coalesce(i.numero_depre,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
          or exists (select 1 from partes d where d.incidente_id = i.id and d.documento ilike '%'||regexp_replace(p_q,'\D','','g')||'%'))
     and (p_advogado is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa'
            and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g'))
                ilike '%'||btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g'))||'%'))
     and (p_oab is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))));
$function$;

grant execute on function public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,text,integer
) to anon, authenticated;
