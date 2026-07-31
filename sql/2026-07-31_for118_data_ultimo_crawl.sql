-- FOR-118 — Data do último crawl (filtro + coluna) em Processo × Incidente / Processos.
--
-- Descoberta-chave (ver .claude/sessions/for-118-data-ultimo-crawl/architecture.md):
-- `processos.last_crawled_at` já existe (schema original FOR-69) e já é mantido pelo
-- worker (worker-crawler/src/supabase.ts:111, dentro de persistTree() — só roda em
-- sucesso). Não precisa de coluna nova, trigger, nem subquery em crawler_queue: só expor
-- o campo que já existe nas duas telas.
--
-- Sem staging — validar cada bloco com EXPLAIN ANALYZE (só leitura) antes de seguir pro
-- próximo. Aplicar no SQL Editor, nesta ordem.

-- ===============================================================
-- SEÇÃO 1 — tela flat (/admin/processo-incidente)
-- ===============================================================

-- -------------------------------------------------------------
-- 1.1) Índice novo — hoje só existe índice em next_crawl_at, nenhum em last_crawled_at.
-- -------------------------------------------------------------
create index if not exists idx_processos_last_crawled_at
  on public.processos (last_crawled_at);

-- -------------------------------------------------------------
-- 1.2) _where_processo_incidente — helper interno (não exposto via PostgREST) usado por
-- buscar_processos_incidente e contar_processos_incidente. +3 parâmetros no final
-- (CREATE OR REPLACE aceita adicionar parâmetros com default no fim, mesmo padrão já
-- usado ao adicionar p_ano_oc/p_em_cumprimento antes).
-- -------------------------------------------------------------
create or replace function public._where_processo_incidente(
  p_esfera text, p_tipo text, p_fase text, p_macrofase text, p_status text,
  p_valor_min bigint, p_valor_max bigint, p_elegivel boolean,
  p_fase_desde_de date, p_fase_desde_ate date, p_ano_oc integer,
  p_ente_devedor text, p_em_cumprimento boolean,
  p_q text, p_advogado text, p_oab text,
  p_crawler_data_de date default null, p_crawler_data_ate date default null,
  p_crawleado boolean default null
) returns text
language plpgsql
stable
as $function$
declare
  v_where text := 'p.flag_sp';
  v_digits text;
  v_pattern text;
  v_advogado_norm text;
  v_oab_norm text;
begin
  if p_esfera is not null then
    v_where := v_where || format(' and p.ente_esfera = %L', p_esfera);
  end if;
  if p_tipo is not null then
    v_where := v_where || format(' and i.tipo_previsto = %L', p_tipo);
  end if;
  if p_fase is not null then
    v_where := v_where || format(' and i.fase = %L', p_fase);
  end if;
  if p_macrofase is not null then
    v_where := v_where || format(' and i.macrofase = %L', p_macrofase);
  end if;
  if p_status is not null then
    v_where := v_where || format(' and i.status = %L', p_status);
  end if;
  if p_valor_min is not null then
    v_where := v_where || format(
      $sql$ and least(i.valor_acao, (select max(pr.saldo_depre) from precatorios pr where pr.processo_depre = i.numero_depre)) >= %L::bigint$sql$,
      p_valor_min);
  end if;
  if p_valor_max is not null then
    v_where := v_where || format(
      $sql$ and least(i.valor_acao, (select max(pr.saldo_depre) from precatorios pr where pr.processo_depre = i.numero_depre)) <= %L::bigint$sql$,
      p_valor_max);
  end if;
  if p_elegivel is not null then
    v_where := v_where || format(' and i.elegivel = %L::boolean', p_elegivel);
  end if;
  if p_fase_desde_de is not null then
    v_where := v_where || format(' and i.fase_desde >= %L::date', p_fase_desde_de);
  end if;
  if p_fase_desde_ate is not null then
    v_where := v_where || format(' and i.fase_desde <= %L::date', p_fase_desde_ate);
  end if;
  if p_ano_oc is not null then
    v_where := v_where || format(' and i.ano_oc = %L::integer', p_ano_oc);
  end if;
  if p_ente_devedor is not null then
    v_where := v_where || format(
      $sql$ and i.processo_id in (select pp.processo_id from partes pp where pp.papel = 'passiva' and pp.nome = %L)$sql$,
      p_ente_devedor);
  end if;
  if p_em_cumprimento is not null then
    v_where := v_where || format(' and i.em_cumprimento_real = %L::boolean', p_em_cumprimento);
  end if;
  -- FOR-118: last_crawled_at é coluna real em processos (p) — comparação direta, sem
  -- subquery. p_crawler_data_ate usa limite exclusivo (+1 dia) pra não perder o próprio
  -- dia final (mesmo padrão de fase_desde/descoberto).
  if p_crawler_data_de is not null then
    v_where := v_where || format(' and p.last_crawled_at >= %L::timestamptz', p_crawler_data_de);
  end if;
  if p_crawler_data_ate is not null then
    v_where := v_where || format(' and p.last_crawled_at < %L::timestamptz', (p_crawler_data_ate + 1));
  end if;
  if p_crawleado is not null then
    if p_crawleado then
      v_where := v_where || ' and p.last_crawled_at is not null';
    else
      v_where := v_where || ' and p.last_crawled_at is null';
    end if;
  end if;
  if p_q is not null then
    v_digits := regexp_replace(p_q, '\D', '', 'g');
    v_pattern := '%' || v_digits || '%';
    v_where := v_where || format(
      $sql$ and (
        i.processo_id in (
          select pp.id from processos pp where pp.cnj_normalizado ilike %L
          union
          select ii.processo_id from incidentes ii
          join cumprimentos cc on cc.id = ii.cumprimento_id
           where cc.cnj_normalizado ilike %L
        )
        or i.id in (
          select iii.id from incidentes iii
           where regexp_replace(coalesce(iii.numero_depre,''), '\D', '', 'g') ilike %L
        )
      )$sql$,
      v_pattern, v_pattern, v_pattern);
  end if;
  if p_advogado is not null then
    v_advogado_norm := '%' || btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g')) || '%';
    v_where := v_where || format(
      $sql$ and exists (
        select 1 from partes a where a.incidente_id = i.id and a.papel='ativa'
          and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g')) ilike %L
      )$sql$,
      v_advogado_norm);
  end if;
  if p_oab is not null then
    v_oab_norm := upper(regexp_replace(p_oab, '[^0-9A-Za-z]', '', 'g'));
    v_where := v_where || format(
      $sql$ and exists (
        select 1 from partes a where a.incidente_id = i.id and a.papel='ativa' and a.oab_normalizada = %L
      )$sql$,
      v_oab_norm);
  end if;

  return v_where;
end;
$function$;

-- -------------------------------------------------------------
-- 1.3) buscar_processos_incidente — RETURNS TABLE muda (nova coluna last_crawled_at),
-- então precisa DROP FUNCTION IF EXISTS com a assinatura ATUAL (18 params) antes do
-- CREATE (Postgres não permite CREATE OR REPLACE mudar colunas de retorno).
-- -------------------------------------------------------------
drop function if exists public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer,boolean
);

create or replace function public.buscar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_limit integer default 50, p_offset integer default 0,
  p_ente_devedor text default null, p_ano_oc integer default null,
  p_em_cumprimento boolean default null,
  p_crawler_data_de date default null, p_crawler_data_ate date default null,
  p_crawleado boolean default null)
returns table(
  incidente_id uuid, cumprimento_cnj text, numero_incidente text, numero_depre text,
  parte_ativa text, parte_passiva text, valor_acao bigint,
  fase text, fase_desde date, status text,
  tipo_previsto text, macrofase text, elegivel boolean, possivelmente_pago boolean,
  ordem_cronologica boolean, tramitacao_prioritaria boolean, ano_oc integer,
  saldo_depre bigint, valor_pago bigint,
  titular_nome text, titular_documento text,
  data_base date, data_ultimo_andamento date,
  crawler_status text, last_crawled_at timestamptz,
  has_more boolean)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_where text;
  v_limit integer := greatest(coalesce(p_limit, 50), 1);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_sql text;
begin
  v_where := public._where_processo_incidente(
    p_esfera, p_tipo, p_fase, p_macrofase, p_status,
    p_valor_min, p_valor_max, p_elegivel,
    p_fase_desde_de, p_fase_desde_ate, p_ano_oc,
    p_ente_devedor, p_em_cumprimento,
    p_q, p_advogado, p_oab,
    p_crawler_data_de, p_crawler_data_ate, p_crawleado);

  v_sql := format($sql$
    with base as (
      select i.id as incidente_id,
             coalesce(c.cnj, p.cnj) as cumprimento_cnj,
             p.cnj as processo_cnj,
             i.numero_incidente, i.numero_depre, i.valor_acao,
             i.fase, i.fase_desde, i.status,
             i.tipo_previsto, i.macrofase, i.elegivel, i.possivelmente_pago,
             i.ordem_cronologica, i.tramitacao_prioritaria, i.ano_oc, i.data_base,
             p.ente_nome as parte_passiva,
             p.last_crawled_at
        from incidentes i
        join processos p on p.id = i.processo_id
        left join cumprimentos c on c.id = i.cumprimento_id
       where %s
    ),
    page as (
      select b.* from base b
       order by b.valor_acao desc nulls last
       limit %s offset %s
    ),
    paged as (
      select * from page limit %s
    )
    select pg.incidente_id, pg.cumprimento_cnj, pg.numero_incidente, pg.numero_depre,
           (select nome from partes where incidente_id=pg.incidente_id and papel='ativa' and nome is not null limit 1) as parte_ativa,
           pg.parte_passiva,
           pg.valor_acao,
           pg.fase, pg.fase_desde, pg.status,
           pg.tipo_previsto, pg.macrofase, pg.elegivel, pg.possivelmente_pago,
           pg.ordem_cronologica, pg.tramitacao_prioritaria, pg.ano_oc,
           (select max(saldo_depre) from precatorios where processo_depre = pg.numero_depre) as saldo_depre,
           (select sum(valor)::bigint from precatorios_pagamentos where processo_depre = pg.numero_depre) as valor_pago,
           (select titular_nome from djen_depre where cnj_normalizado = regexp_replace(coalesce(pg.numero_depre,''), '\D', '', 'g') limit 1) as titular_nome,
           (select titular_documento from djen_depre where cnj_normalizado = regexp_replace(coalesce(pg.numero_depre,''), '\D', '', 'g') limit 1) as titular_documento,
           pg.data_base,
           (select max(a.data) from andamentos a where a.incidente_id = pg.incidente_id) as data_ultimo_andamento,
           (select cq.status from crawler_queue cq where cq.processo_codigo = pg.processo_cnj order by cq.updated_at desc limit 1) as crawler_status,
           pg.last_crawled_at,
           (select count(*) from page) > %s as has_more
      from paged pg order by pg.valor_acao desc nulls last
  $sql$, v_where, v_limit + 1, v_offset, v_limit, v_limit);

  return query execute v_sql;
end;
$function$;

grant execute on function public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer,boolean,date,date,boolean
) to anon, authenticated;

-- -------------------------------------------------------------
-- 1.4) contar_processos_incidente — retorno continua bigint, sem DROP necessário, só
-- adiciona os 3 params e repassa pro helper.
-- -------------------------------------------------------------
create or replace function public.contar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_ente_devedor text default null, p_ano_oc integer default null,
  p_em_cumprimento boolean default null,
  p_crawler_data_de date default null, p_crawler_data_ate date default null,
  p_crawleado boolean default null)
returns bigint
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_where text;
  v_sql text;
  v_count bigint;
begin
  v_where := public._where_processo_incidente(
    p_esfera, p_tipo, p_fase, p_macrofase, p_status,
    p_valor_min, p_valor_max, p_elegivel,
    p_fase_desde_de, p_fase_desde_ate, p_ano_oc,
    p_ente_devedor, p_em_cumprimento,
    p_q, p_advogado, p_oab,
    p_crawler_data_de, p_crawler_data_ate, p_crawleado);

  v_sql := format(
    'select count(*) from incidentes i join processos p on p.id = i.processo_id where %s',
    v_where);

  execute v_sql into v_count;
  return v_count;
end;
$function$;

grant execute on function public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,text,integer,boolean,date,date,boolean
) to anon, authenticated;

-- -------------------------------------------------------------
-- 1.5) Validação manual (colar resultado antes de seguir pra próxima fase):
-- -------------------------------------------------------------
-- explain analyze select * from buscar_processos_incidente(p_crawleado := false, p_limit := 10);
-- explain analyze select contar_processos_incidente(p_crawler_data_de := '2026-07-01');
-- select incidente_id, cumprimento_cnj, crawler_status, last_crawled_at
--   from buscar_processos_incidente(p_limit := 10)
--  order by last_crawled_at desc nulls last;

-- ===============================================================
-- SEÇÃO 2 — tela agrupada (/admin/processos)
-- ===============================================================

-- -------------------------------------------------------------
-- 2.1) mv_processos_agrupado — Postgres não suporta ALTER MATERIALIZED VIEW ADD COLUMN,
-- então precisa DROP + CREATE. Definição idêntica à de sql/2026-07-24_for112_mv_e_filtro_oc.sql
-- (já committada), só com `p.last_crawled_at` a mais no SELECT/GROUP BY. Recria todos os
-- índices existentes + o novo, e roda o refresh na hora (senão a tela fica sem dado até o
-- próximo ciclo do pg_cron, a cada 30min).
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
         p.last_crawled_at,
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
   group by e.processo_id, p.cnj, p.processo_codigo, p.ente_nome, p.ente_esfera, p.status, p.last_crawled_at;

create unique index mv_processos_agrupado_uidx on public.mv_processos_agrupado (processo_id);
create index mv_processos_agrupado_esfera_idx on public.mv_processos_agrupado (ente_esfera);
create index mv_processos_agrupado_valor_idx on public.mv_processos_agrupado (valor_total desc nulls last);
create index mv_processos_agrupado_fases_gin on public.mv_processos_agrupado using gin (fases_presentes);
create index mv_processos_agrupado_tipos_gin on public.mv_processos_agrupado using gin (tipos_presentes);
create index mv_processos_agrupado_status_gin on public.mv_processos_agrupado using gin (status_presentes);
create index mv_processos_agrupado_macrofases_gin on public.mv_processos_agrupado using gin (macrofases_presentes);
create index mv_processos_agrupado_anos_oc_gin on public.mv_processos_agrupado using gin (anos_oc_presentes);
-- FOR-118: índice novo pro filtro/coluna de crawl.
create index mv_processos_agrupado_crawler_idx on public.mv_processos_agrupado (last_crawled_at);

grant select on public.mv_processos_agrupado to anon, authenticated;

-- refresh_mv_processos_agrupado() e o agendamento pg_cron (a cada 30min) já existem e
-- referenciam a MV pelo nome — não precisam ser recriados. Refresh manual imediato pra não
-- esperar a janela de 30min:
select public.refresh_mv_processos_agrupado();

-- -------------------------------------------------------------
-- 2.2) buscar_processos_agrupado — RETURNS TABLE muda (nova coluna last_crawled_at),
-- então precisa DROP FUNCTION IF EXISTS com a assinatura ATUAL (19 params) antes do CREATE.
-- Filtros comparam m.last_crawled_at direto (já vem da MV, sem subquery/semi-join).
-- -------------------------------------------------------------
drop function if exists public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer,text,integer
);

create or replace function public.buscar_processos_agrupado(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_created_de date default null, p_created_ate date default null,
  p_limit integer default 25, p_offset integer default 0,
  p_ente_devedor text default null, p_ano_oc integer default null,
  p_crawler_data_de date default null, p_crawler_data_ate date default null,
  p_crawleado boolean default null)
returns table(
  processo_id uuid, cnj text, processo_codigo text, ente_nome text, ente_esfera text,
  status text, n_incidentes bigint, fase_mais_avancada text, fase_desde date,
  valor_total bigint, has_more boolean, total_processos bigint, crawler_status text,
  anos_oc_presentes integer[], last_crawled_at timestamptz)
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
       and (p_crawler_data_de  is null or m.last_crawled_at >= p_crawler_data_de::timestamptz)
       and (p_crawler_data_ate is null or m.last_crawled_at < (p_crawler_data_ate + 1)::timestamptz)
       and (p_crawleado is null or (p_crawleado and m.last_crawled_at is not null) or (not p_crawleado and m.last_crawled_at is null))
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
             select i.processo_id from public.incidentes i
             where least(i.valor_acao,
                     (select max(pr.saldo_depre) from precatorios pr where pr.processo_depre = i.numero_depre)) >= p_valor_min))
       and (p_valor_max is null or m.processo_id in (
             select i.processo_id from public.incidentes i
             where least(i.valor_acao,
                     (select max(pr.saldo_depre) from precatorios pr where pr.processo_depre = i.numero_depre)) <= p_valor_max))
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
         pg.anos_oc_presentes,
         pg.last_crawled_at
    from paged pg
   order by pg.valor_total desc nulls last;
$function$;

grant execute on function public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer,text,integer,date,date,boolean
) to anon, authenticated;

-- -------------------------------------------------------------
-- 2.3) Validação manual (colar resultado antes de seguir pra FASE 3/4):
-- -------------------------------------------------------------
-- select count(*) from mv_processos_agrupado where last_crawled_at is not null; -- > 0
-- explain analyze select * from buscar_processos_agrupado(p_crawleado := true, p_limit := 10);
-- select jobname, schedule from cron.job where jobname ilike '%processos_agrupado%'; -- confirmar cron ainda agendado

-- ===============================================================
-- SEÇÃO 3 — buscar_processos (CSV da tela agrupada /admin/processos, e /admin/curadoria)
-- ===============================================================
--
-- Escopo ampliado (2026-07-31): a tela /admin/processos exporta CSV via uma RPC
-- DIFERENTE da usada pro grid on-screen — buscar_processos (ProcessoListRow), não
-- buscar_processos_agrupado. Não tinha last_crawled_at nem crawler_status. Só a coluna
-- de saída — NÃO adiciona p_crawler_data_de/ate/p_crawleado como filtro aqui: a função
-- wrapper do frontend (buscarProcessos) já não repassa vários outros filtros da tela
-- (enteDevedor, anoOc, faseDesdeDe/Ate, descobertoDe/Ate) pra essa RPC — isso é uma
-- limitação pré-existente do CSV dessa tela, não uma regressão introduzida aqui.
--
-- Definição confirmada via `select pg_get_functiondef('public.buscar_processos'::regproc)`
-- rodado em produção em 2026-07-31 (idêntica à versão "semi-join" — a versão que
-- restringia os campos de busca, sql/2026-07-27_busca_so_numero_processo_outras_telas.sql,
-- NUNCA chegou a ser aplicada). RETURNS TABLE muda (nova coluna), então precisa DROP
-- FUNCTION IF EXISTS antes do CREATE.
-- -------------------------------------------------------------
drop function if exists public.buscar_processos(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
);

create or replace function public.buscar_processos(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null, p_andamento_de date default null,
  p_andamento_ate date default null, p_limit integer default 50, p_offset integer default 0)
returns table(incidente_id uuid, processo_codigo text, cnj text, numero_incidente text,
  tipo_previsto text, numero_depre text, macrofase text, fase text, status text,
  valor_acao bigint, data_base date, data_ultimo_andamento date, ente_nome text,
  ente_esfera text, autor_nome text, advogados text, oabs text, elegivel boolean,
  last_crawled_at timestamptz,
  has_more boolean)
language sql
security definer
set search_path to 'public'
as $function$
  with base as (
    select i.id as incidente_id, i.processo_codigo, coalesce(i.cnj, p.cnj) as cnj,
           i.numero_incidente, i.tipo_previsto, i.numero_depre, i.macrofase, i.fase, i.status,
           i.valor_acao, i.data_base, i.elegivel, p.ente_nome, p.ente_esfera,
           p.last_crawled_at
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
       and (p_andamento_de  is null or (select max(a.data) from andamentos a where a.incidente_id = i.id) >= p_andamento_de)
       and (p_andamento_ate is null or (select max(a.data) from andamentos a where a.incidente_id = i.id) <= p_andamento_ate)
       and (p_q is null or i.processo_id in (
             select pp.id from processos pp
              where pp.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
             union
             select ii.processo_id from incidentes ii
             join cumprimentos cc on cc.id = ii.cumprimento_id
              where cc.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
           )
           or i.id in (
             select iii.id from incidentes iii
              where regexp_replace(coalesce(iii.numero_depre,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
           ))
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
  select pg.incidente_id, pg.processo_codigo, pg.cnj, pg.numero_incidente, pg.tipo_previsto, pg.numero_depre,
         pg.macrofase, pg.fase, pg.status, pg.valor_acao, pg.data_base,
         (select max(a.data) from andamentos a where a.incidente_id = pg.incidente_id) as data_ultimo_andamento,
         pg.ente_nome, pg.ente_esfera,
         (select nome from partes where incidente_id=pg.incidente_id and papel='ativa' and nome is not null limit 1) as autor_nome,
         (select string_agg(distinct advogado_nome, ', ') from partes where incidente_id=pg.incidente_id and papel='ativa' and advogado_nome is not null) as advogados,
         (select string_agg(distinct oab, ', ') from partes where incidente_id=pg.incidente_id and papel='ativa' and oab is not null) as oabs,
         pg.elegivel,
         pg.last_crawled_at,
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg order by pg.valor_acao desc nulls last;
$function$;

grant execute on function public.buscar_processos(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
) to anon, authenticated;

-- -------------------------------------------------------------
-- 3.1) Validação manual:
-- -------------------------------------------------------------
-- select incidente_id, cnj, last_crawled_at from buscar_processos(p_limit := 10)
--  order by last_crawled_at desc nulls last;

-- ===============================================================
-- SEÇÃO 4 — FIX: contar_processos_incidente ficou duplicada (bug pós-deploy, 2026-07-31)
-- ===============================================================
--
-- Causa: na Seção 1.4, usei CREATE OR REPLACE pra adicionar p_crawler_data_de/ate/
-- p_crawleado em contar_processos_incidente, assumindo que "retorno continua bigint,
-- sem DROP necessário" bastava. Errado: Postgres só substitui uma function via CREATE OR
-- REPLACE quando a lista de tipos de parâmetro é IDÊNTICA à existente — adicionar
-- parâmetros novos (mesmo com default) muda essa lista, então o Postgres CRIA uma
-- function nova sobreposta em vez de substituir. Resultado: ficaram DUAS
-- contar_processos_incidente em produção (16 params antiga + 19 params nova) e o
-- PostgREST não consegue escolher entre elas quando a chamada não deixa claro qual usar
-- (erro PGRST203 "Could not choose the best candidate function").
--
-- Confirmado que a versão nova funciona certo quando chamada com os parâmetros novos
-- explícitos (é o que o frontend sempre faz) — mas a function antiga órfã continua lá,
-- um risco pra qualquer outro caller que não passe esses parâmetros. Removendo.
--
-- Aplicar no SQL Editor.
drop function if exists public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,text,integer,boolean
);

-- Validação: depois de rodar o DROP acima, isto tem que funcionar sem erro de ambiguidade
-- (antes do fix, dava PGRST203):
-- select contar_processos_incidente();
