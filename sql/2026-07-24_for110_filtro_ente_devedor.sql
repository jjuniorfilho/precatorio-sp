-- FOR-110 — Filtro "Ente devedor" (parte passiva) nas telas /admin/processos e
-- /admin/processo-incidente. Busca contra `partes` (papel='passiva', já tem processo_id
-- direto, não precisa passar por incidentes) — precisão de incidente/processo, não o campo
-- genérico processos.ente_nome. Combobox único: campo vazio em foco mostra os 10 maiores
-- (por nº de processos); digitando, autocomplete assume e busca em todos os entes.
--
-- Aplicar no SQL Editor.

-- 1) Top 10 entes devedores por nº de processos — pro estado "campo em foco, vazio"
create or replace function public.partes_passivas_mais_comuns(p_limit integer default 10)
returns table(nome text, n_processos bigint)
language sql stable security definer set search_path = public
as $function$
  select pp.nome, count(distinct pp.processo_id) as n_processos
    from partes pp
    join processos p on p.id = pp.processo_id
   where pp.papel = 'passiva' and pp.nome is not null and p.flag_sp
   group by pp.nome
   order by n_processos desc
   limit greatest(p_limit, 1);
$function$;

grant execute on function public.partes_passivas_mais_comuns(integer) to anon, authenticated;

-- 2) Autocomplete — pro estado "digitando"
create or replace function public.partes_passivas_buscar(p_q text, p_limit integer default 20)
returns table(nome text, n_processos bigint)
language sql stable security definer set search_path = public
as $function$
  select pp.nome, count(distinct pp.processo_id) as n_processos
    from partes pp
    join processos p on p.id = pp.processo_id
   where pp.papel = 'passiva' and pp.nome is not null and p.flag_sp
     and (p_q is null or pp.nome ilike '%'||p_q||'%')
   group by pp.nome
   order by n_processos desc
   limit greatest(p_limit, 1);
$function$;

grant execute on function public.partes_passivas_buscar(text, integer) to anon, authenticated;

-- 3) Filtro p_ente_devedor no grid agrupado — casamento exato (o combobox só entrega nomes
-- que já existem, via as duas RPCs acima), semi-join não correlacionado igual advogado/oab.
-- Adiciona parâmetro → muda aridade → precisa DROP da assinatura antiga antes (CREATE OR
-- REPLACE não substitui quando o nº de parâmetros muda, cria um overload novo do lado).
drop function if exists public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer
);

create or replace function public.buscar_processos_agrupado(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_created_de date default null, p_created_ate date default null,
  p_limit integer default 25, p_offset integer default 0,
  p_ente_devedor text default null)
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
       and (p_fase      is null or m.fase_mais_avancada = p_fase)
       and (p_fase_desde_de  is null or m.fase_desde >= p_fase_desde_de)
       and (p_fase_desde_ate is null or m.fase_desde <= p_fase_desde_ate)
       and (p_tipo      is null or p_tipo = any(m.tipos_presentes))
       and (p_macrofase is null or p_macrofase = any(m.macrofases_presentes))
       and (p_status    is null or m.status_presentes && string_to_array(p_status, ','))
       and (p_elegivel  is null or (p_elegivel and m.tem_elegivel_true) or (not p_elegivel and m.tem_elegivel_false))
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

-- 4) Filtro p_ente_devedor no relatório flat (Processo × Incidente) — precisão de incidente.
drop function if exists public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
);

create or replace function public.buscar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_limit integer default 50, p_offset integer default 0,
  p_ente_devedor text default null)
returns table(
  incidente_id uuid, cumprimento_cnj text, numero_incidente text, numero_depre text,
  parte_ativa text, parte_passiva text, valor_acao bigint,
  fase text, fase_desde date, status text,
  tipo_previsto text, macrofase text, elegivel boolean, possivelmente_pago boolean,
  ordem_cronologica boolean, tramitacao_prioritaria boolean, ano_oc integer,
  saldo_depre bigint, valor_pago bigint,
  titular_nome text, titular_documento text,
  data_base date, data_ultimo_andamento date,
  has_more boolean)
language sql
security definer
set search_path to 'public'
as $function$
  with base as (
    select i.id as incidente_id,
           coalesce(c.cnj, p.cnj) as cumprimento_cnj,
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
       and (p_ente_devedor is null or exists (
             select 1 from partes pp where pp.processo_id = i.processo_id and pp.papel = 'passiva' and pp.nome = p_ente_devedor))
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
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg order by pg.valor_acao desc nulls last;
$function$;

grant execute on function public.buscar_processos_agrupado(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer,text
) to anon, authenticated;

grant execute on function public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text
) to anon, authenticated;
