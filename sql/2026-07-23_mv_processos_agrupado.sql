-- FOR-107 (fix) — buscar_processos_agrupado estourava statement timeout (57014) em
-- filtros pouco seletivos (ex.: só esfera, ou só fase — é exatamente o que um clique num
-- badge do totalizador de /admin/processos dispara). Causa raiz é a mesma lição do FOR-105
-- (mv_resumo_descobertas): a RPC precisa materializar TODO o conjunto filtrado antes de
-- poder agrupar por processo e escolher o top-25 por valor — não dá pra usar o truque de
-- "index scan + limit com early-exit" quando o ORDER BY/LIMIT vem DEPOIS de um GROUP BY.
--
-- Fix: pré-computa o agregado por processo (fase mais avançada, valor total, nº incidentes
-- etc.) numa materialized view, refrescada via pg_cron — a RPC deixa de agregar ao vivo e
-- só filtra/ordena/pagina linhas já prontas. Os filtros "estruturais" (esfera, fase, tipo,
-- macrofase, status, elegível) passam a usar colunas de presença pré-computadas na MV;
-- os filtros que já eram rápidos por serem seletivos e indexados nas tabelas vivas (busca
-- textual, valor, advogado/OAB, período de andamento) continuam ao vivo, mas como um
-- semi-join não correlacionado (m.processo_id IN (SELECT ...)) em vez de EXISTS correlacionado
-- por linha — deixa o planner resolver o subselect uma vez só via índice, igual já
-- acontecia antes.
--
-- Aplicar no SQL Editor.

-- -------------------------------------------------------------
-- 1) mv_processos_agrupado — um agregado por processo (todos os incidentes, sem filtro)
-- -------------------------------------------------------------
drop materialized view if exists public.mv_processos_agrupado;

create materialized view public.mv_processos_agrupado as
  with enriquecido as (
    select i.id as incidente_id, i.processo_id, i.tipo_previsto, i.fase, i.fase_desde,
           i.status, i.elegivel, i.macrofase,
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
         bool_or(e.elegivel is true) as tem_elegivel_true,
         bool_or(e.elegivel is false) as tem_elegivel_false
    from enriquecido e
    join public.processos p on p.id = e.processo_id
   group by e.processo_id, p.cnj, p.processo_codigo, p.ente_nome, p.ente_esfera, p.status;

-- Índice único — pré-requisito pra REFRESH CONCURRENTLY.
create unique index mv_processos_agrupado_uidx on public.mv_processos_agrupado (processo_id);

-- Suporte aos filtros estruturais + ao ORDER BY valor_total padrão (sem filtro nenhum,
-- listar já ordenado por valor precisa ser rápido também).
create index mv_processos_agrupado_esfera_idx on public.mv_processos_agrupado (ente_esfera);
create index mv_processos_agrupado_valor_idx on public.mv_processos_agrupado (valor_total desc nulls last);
create index mv_processos_agrupado_fases_gin on public.mv_processos_agrupado using gin (fases_presentes);
create index mv_processos_agrupado_tipos_gin on public.mv_processos_agrupado using gin (tipos_presentes);
create index mv_processos_agrupado_status_gin on public.mv_processos_agrupado using gin (status_presentes);
create index mv_processos_agrupado_macrofases_gin on public.mv_processos_agrupado using gin (macrofases_presentes);

-- Materialized view não suporta RLS; mesmo dado já exposto via RPC security definer, sem
-- informação sensível/pessoal (nomes de partes não entram aqui).
grant select on public.mv_processos_agrupado to anon, authenticated;

create or replace function public.refresh_mv_processos_agrupado()
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  refresh materialized view concurrently public.mv_processos_agrupado;
end;
$$;

create extension if not exists pg_cron;

do $$
begin
  perform cron.unschedule('refresh-mv-processos-agrupado');
exception when others then null; -- ainda não existe na 1ª aplicação
end $$;

-- A cada 30 min — essa MV varre TODOS os incidentes flag_sp (não só os últimos 7 dias como
-- a mv_resumo_descobertas), então o refresh é mais pesado; 30min equilibra frescor x custo.
select cron.schedule(
  'refresh-mv-processos-agrupado',
  '*/30 * * * *',
  $$select public.refresh_mv_processos_agrupado();$$
);

-- -------------------------------------------------------------
-- 2) buscar_processos_agrupado — reescrita pra ler da MV em vez de agregar ao vivo
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
       -- o subselect uma vez via índice, não linha a linha) porque já eram seletivos/rápidos
       -- antes do MV e não se prestam bem a um array de "presença" pré-computado.
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
       and (p_andamento_de is null or m.processo_id in (
             select i.processo_id from public.incidentes i
             join public.andamentos an on an.incidente_id = i.id
              where an.data >= p_andamento_de
           ))
       and (p_andamento_ate is null or m.processo_id in (
             select i.processo_id from public.incidentes i
             join public.andamentos an on an.incidente_id = i.id
              where an.data <= p_andamento_ate
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
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer
) to anon, authenticated;

-- Conferir: select jobname, schedule, command from cron.job where jobname = 'refresh-mv-processos-agrupado';
