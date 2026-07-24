-- FOR-107 (Processo × Incidente) — adiciona o filtro "Nesta fase desde" (incidentes.fase_desde)
-- que faltou no relatório novo, igual já existe no grid agrupado. Como aqui é um grid flat
-- (1 linha = 1 incidente, sem agregação), o filtro é direto na própria linha — nem precisa
-- do truque de semi-join usado no grid agrupado.
-- Assinatura muda (novos parâmetros no meio) — precisa DROP antes de recriar.
-- Aplicar no SQL Editor.

drop function if exists public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
);

create function public.buscar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_limit integer default 50, p_offset integer default 0)
returns table(
  incidente_id uuid, cumprimento_cnj text, numero_incidente text, numero_depre text,
  parte_ativa text, parte_passiva text, valor_acao bigint, has_more boolean)
language sql
security definer
set search_path to 'public'
as $function$
  with base as (
    select i.id as incidente_id,
           coalesce(c.cnj, p.cnj) as cumprimento_cnj,
           i.numero_incidente, i.numero_depre, i.valor_acao,
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
         (select count(*) from page) > greatest(p_limit,1) as has_more
    from paged pg order by pg.valor_acao desc nulls last;
$function$;

grant execute on function public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,date,date,integer,integer
) to anon, authenticated;
