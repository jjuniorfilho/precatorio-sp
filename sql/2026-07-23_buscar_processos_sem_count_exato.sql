-- FOR-104 — buscar_processos sem count(*) over(): timeout persistia mesmo com os índices
-- (sql/2026-07-23_indices_buscar_processos.sql) e ANALYZE nas tabelas. Causa raiz real: o
-- count(*) over() obrigava o Postgres a materializar/contar TODO o conjunto filtrado antes
-- de aplicar o LIMIT — mesmo com filtro seletivo, isso já é caro o suficiente pra estourar o
-- statement timeout.
--
-- Troca por padrão "limit+1": busca uma linha a mais que o pedido, descarta ela e devolve só
-- um booleano has_more (tem próxima página ou não) — nunca precisa contar o total exato.
--
-- Muda o tipo de retorno (total_count bigint → has_more boolean), por isso precisa DROP
-- antes de recriar (CREATE OR REPLACE não permite mudar colunas de retorno). Aplicar no SQL
-- Editor. Frontend (buscarProcessos) precisa ser atualizado junto — não é retrocompatível.

DROP FUNCTION IF EXISTS public.buscar_processos(
  text, text, text, text, text, text, text, bigint, bigint, boolean, text, date, date, integer, integer
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
  has_more boolean)
language sql
security definer
set search_path to 'public'
as $function$
  with base as (
    select i.id as incidente_id, i.processo_codigo, coalesce(i.cnj, p.cnj) as cnj,
           i.numero_incidente, i.tipo_previsto, i.numero_depre, i.macrofase, i.fase, i.status,
           i.valor_acao, i.data_base, i.elegivel, p.ente_nome, p.ente_esfera
      from incidentes i join processos p on p.id = i.processo_id
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
       and (p_q is null or i.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or p.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or regexp_replace(coalesce(i.numero_depre,''),'\D','','g') ilike '%'||regexp_replace(p_q,'\D','','g')||'%'  -- FOR-77: busca por número DEPRE
            or exists (select 1 from partes d where d.incidente_id = i.id and d.documento ilike '%'||regexp_replace(p_q,'\D','','g')||'%'))
       -- p_advogado tolerante a espaço (nbsp→espaço, colapsa runs, trim) nos dois lados:
       and (p_advogado is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa'
              and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g'))
                  ilike '%'||btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g'))||'%'))
       and (p_oab is null or exists (select 1 from partes a where a.incidente_id = i.id and a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
  ),
  page as (
    -- limit+1: se vier a linha extra, sabemos que tem próxima página, sem contar o total.
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
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg order by pg.valor_acao desc nulls last;
$function$;
