-- FOR-110 (fix) — buscar_processos_incidente com p_ente_devedor dava timeout pra entes
-- muito comuns (ex.: "PREFEITURA MUNICIPAL DE SÃO PAULO", 7.672 processos): o filtro usava
-- EXISTS correlacionado por linha (avaliado a cada candidato durante o scan ordenado por
-- valor_acao), sem índice em partes.processo_id — cada checagem exigia um scan de partes.
-- buscar_processos_agrupado já usava semi-join (IN não correlacionado, resolvido uma vez só)
-- e funcionou em 815ms pro mesmo ente; aplica o mesmo padrão aqui + adiciona o índice.
--
-- Aplicar no SQL Editor.

create index if not exists idx_partes_papel_nome_processo on partes (papel, nome, processo_id);

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
       -- semi-join não correlacionado (igual buscar_processos_agrupado) — o planner resolve
       -- o subselect uma vez via índice, não checa linha a linha durante o scan ordenado.
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
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg order by pg.valor_acao desc nulls last;
$function$;
