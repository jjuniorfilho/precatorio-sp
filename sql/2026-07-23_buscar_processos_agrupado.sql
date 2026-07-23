-- FOR-107 — Grid de /admin/processos agrupado por processo raiz (Processo → Cumprimento →
-- Incidente), com paginação em dois níveis e os 4 campos de valor com fonte própria.
-- Substitui a listagem flat de buscar_processos (FOR-104) por duas RPCs:
--
--   1) buscar_processos_agrupado — paginada por PROCESSO (25 por página, nunca corta um
--      processo no meio). Cada linha é um agregado: nº de incidentes, fase mais avançada
--      (maior rank no pipeline calculo→incidente→termo→oficio_deferido→depre→oficio→oc),
--      fase_desde desse mesmo incidente, e valor_total (soma de "valor incidente" de todos
--      os incidentes do processo).
--
--   2) buscar_incidentes_processo — dado um processo_id, devolve os incidentes paginados
--      (25 por vez, "mostrar mais") — chamada ao expandir um processo no grid. O maior
--      processo real identificado (0027112-62.2012.8.26.0053) tem 8.513 incidentes sozinho,
--      então isso NUNCA pode carregar tudo de uma vez.
--
-- Os 4 campos de valor (definidos ao longo da sessão, validados com mockup):
--   - Valor incidente: djen_depre.valor_acao (ficha do próprio .0500) com fallback
--     incidentes.valor_acao.
--   - Valor pago: soma de precatorios_pagamentos (FOR-102, dado vivo do portal TJSP — só
--     existe pra .0500 já consultado).
--   - Saldo DEPRE: precatorios.saldo_depre (tabela legada, mesmo join já usado em
--     mv_advogado_carteira — processo_depre = numero_depre).
--   - Valor total: soma de "Valor incidente" de todos os incidentes do processo (só na RPC 1).
--
-- Aplicar no SQL Editor.

-- -------------------------------------------------------------
-- 1) buscar_processos_agrupado — nível processo, paginado
-- -------------------------------------------------------------
create or replace function public.buscar_processos_agrupado(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null, p_andamento_de date default null,
  p_andamento_ate date default null, p_limit integer default 25, p_offset integer default 0)
returns table(
  processo_id uuid, cnj text, processo_codigo text, ente_nome text, ente_esfera text,
  status text, n_incidentes bigint, fase_mais_avancada text, fase_desde date,
  valor_total bigint, has_more boolean)
language sql stable security definer set search_path = public
as $function$
  -- Filtra PRIMEIRO (mesma estrutura indexada da buscar_processos/FOR-104, já validada
  -- rápida) — só depois de já ter um conjunto pequeno é que enriquece com djen_depre e
  -- agrega por processo. A primeira versão fazia o LEFT JOIN djen_depre + rank de fase
  -- pra TODOS os incidentes antes de filtrar, o que estourava timeout mesmo com filtro
  -- bem seletivo (o enriquecimento rodava pra tabela inteira de qualquer jeito).
  with filtrado as (
    select i.id as incidente_id, i.processo_id, i.tipo_previsto, i.fase, i.fase_desde,
           i.numero_depre, i.status, i.elegivel, i.macrofase, i.valor_acao
      from incidentes i
      join processos p on p.id = i.processo_id
     where p.flag_sp
       and (p_esfera    is null or p.ente_esfera = p_esfera)
       and (p_tipo      is null or i.tipo_previsto = p_tipo)
       and (p_fase      is null or i.fase = p_fase)
       and (p_macrofase is null or i.macrofase = p_macrofase)
       and (p_status    is null or i.status = p_status)
       -- valor_min/max filtra pelo valor_acao bruto (pré-enriquecimento djen_depre) —
       -- aproximação deliberada pra manter o filtro sargable; na prática os dois valores
       -- raramente divergem o suficiente pra mudar se o processo entra ou não.
       and (p_valor_min is null or i.valor_acao >= p_valor_min)
       and (p_valor_max is null or i.valor_acao <= p_valor_max)
       and (p_elegivel  is null or i.elegivel = p_elegivel)
       and (p_andamento_de  is null or (select max(a.data) from andamentos a where a.incidente_id = i.id) >= p_andamento_de)
       and (p_andamento_ate is null or (select max(a.data) from andamentos a where a.incidente_id = i.id) <= p_andamento_ate)
       and (p_q is null or i.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or p.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or regexp_replace(coalesce(i.numero_depre,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or exists (select 1 from partes d where d.incidente_id = i.id and d.documento ilike '%'||regexp_replace(p_q,'\D','','g')||'%'))
       and (p_advogado is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa'
              and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g'))
                  ilike '%'||btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g'))||'%'))
       and (p_oab is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
  ),
  enriquecido as (
    select f.*,
           coalesce(dd.valor_acao, f.valor_acao) as valor_incidente,
           case f.fase
             when 'oc' then 8 when 'oficio' then 7 when 'depre' then 6
             when 'oficio_deferido' then 5 when 'termo' then 4 when 'incidente' then 3
             when 'calculo' then 2 when 'inicial' then 1 else 0
           end as fase_rank
      from filtrado f
      left join djen_depre dd
        on f.numero_depre is not null
       and dd.cnj_normalizado = regexp_replace(f.numero_depre, '\D', '', 'g')
  ),
  agregado as (
    select processo_id,
           count(*) as n_incidentes,
           sum(valor_incidente) as valor_total,
           (array_agg(fase order by fase_rank desc, fase_desde desc nulls last))[1] as fase_mais_avancada,
           (array_agg(fase_desde order by fase_rank desc, fase_desde desc nulls last))[1] as fase_desde
      from enriquecido
     group by processo_id
  ),
  page as (
    select a.*, p.cnj, p.processo_codigo, p.ente_nome, p.ente_esfera, p.status
      from agregado a
      join processos p on p.id = a.processo_id
     order by a.valor_total desc nulls last
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
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
) to anon, authenticated;

-- -------------------------------------------------------------
-- 2) buscar_incidentes_processo — nível incidente, paginado, chamada ao expandir
-- -------------------------------------------------------------
create or replace function public.buscar_incidentes_processo(
  p_processo_id uuid, p_limit integer default 25, p_offset integer default 0)
returns table(
  incidente_id uuid, numero_incidente text, tipo_previsto text, numero_depre text,
  fase text, fase_desde date, status text,
  valor_incidente bigint, valor_pago bigint, saldo_depre bigint,
  autor_nome text, has_more boolean)
language sql stable security definer set search_path = public
as $function$
  with base as (
    select i.id as incidente_id, i.numero_incidente, i.tipo_previsto, i.numero_depre,
           i.fase, i.fase_desde, i.status,
           coalesce(dd.valor_acao, i.valor_acao) as valor_incidente,
           pg_pago.total_pago as valor_pago,
           prec.saldo_depre as saldo_depre,
           (select nome from partes where incidente_id = i.id and papel = 'ativa' and nome is not null limit 1) as autor_nome
      from incidentes i
      left join djen_depre dd
        on i.numero_depre is not null
       and dd.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
      left join lateral (
        select sum(valor) as total_pago from precatorios_pagamentos pp where pp.processo_depre = i.numero_depre
      ) pg_pago on i.numero_depre is not null
      left join lateral (
        select max(saldo_depre) as saldo_depre from precatorios pr where pr.processo_depre = i.numero_depre
      ) prec on i.numero_depre is not null
     where i.processo_id = p_processo_id
  ),
  page as (
    select * from base
     order by numero_incidente nulls last, incidente_id
     limit greatest(p_limit,1) + 1 offset greatest(p_offset,0)
  ),
  paged as (select * from page limit greatest(p_limit,1))
  select pg.incidente_id, pg.numero_incidente, pg.tipo_previsto, pg.numero_depre,
         pg.fase, pg.fase_desde, pg.status, pg.valor_incidente, pg.valor_pago, pg.saldo_depre,
         pg.autor_nome,
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg
   order by pg.numero_incidente nulls last, pg.incidente_id;
$function$;

grant execute on function public.buscar_incidentes_processo(uuid,integer,integer) to anon, authenticated;
