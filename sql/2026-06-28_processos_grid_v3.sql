-- FOR-74 — Grid de processos: data do último andamento (coluna + filtro), faixa de
-- valor (min/max) e resumo de descobertas (dia/semana por esfera/instrumento/fase).
-- Aplicar no SQL Editor. Substitui buscar_processos; adiciona resumo_descobertas.

-- Remove a assinatura antiga (12 params) p/ não criar overload ambíguo.
drop function if exists public.buscar_processos(text,text,text,text,text,text,text,bigint,boolean,text,integer,integer);

create or replace function public.buscar_processos(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_andamento_de date default null, p_andamento_ate date default null,
  p_limit integer default 50, p_offset integer default 0)
returns table(incidente_id uuid, processo_codigo text, cnj text, numero_incidente text,
  tipo_previsto text, numero_depre text, macrofase text, fase text, status text,
  valor_acao bigint, data_base date, data_ultimo_andamento date, ente_nome text, ente_esfera text,
  autor_nome text, advogados text, oabs text, elegivel boolean, total_count bigint)
language sql security definer set search_path to 'public'
as $function$
  with base as (
    select i.id as incidente_id, i.processo_codigo, coalesce(i.cnj, p.cnj) as cnj,
           i.numero_incidente, i.tipo_previsto, i.numero_depre, i.macrofase, i.fase, i.status,
           i.valor_acao, i.data_base, i.elegivel, p.ente_nome, p.ente_esfera,
           p.cnj_normalizado as p_cnj_norm,
           (select max(a.data) from andamentos a where a.incidente_id = i.id) as data_ultimo_andamento
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
       and (p_q is null or i.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or p.cnj_normalizado ilike '%'||regexp_replace(p_q,'\D','','g')||'%'
            or exists (select 1 from partes d where d.incidente_id = i.id
                        and d.documento ilike '%'||regexp_replace(p_q,'\D','','g')||'%'))
       and (p_advogado is null or exists (select 1 from partes a where a.incidente_id = i.id
                        and a.papel='ativa' and a.advogado_nome ilike '%'||p_advogado||'%'))
       and (p_oab is null or exists (select 1 from partes a where a.incidente_id = i.id
                        and a.papel='ativa' and a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
  ),
  ag as (
    select b.*,
           (select nome from partes where incidente_id=b.incidente_id and papel='ativa' and nome is not null limit 1) as autor_nome,
           (select string_agg(distinct advogado_nome, ', ') from partes where incidente_id=b.incidente_id and papel='ativa' and advogado_nome is not null) as advogados,
           (select string_agg(distinct oab, ', ') from partes where incidente_id=b.incidente_id and papel='ativa' and oab is not null) as oabs,
           count(*) over() as total_count
      from base b
  )
  select incidente_id, processo_codigo, cnj, numero_incidente, tipo_previsto, numero_depre,
         macrofase, fase, status, valor_acao, data_base, data_ultimo_andamento, ente_nome, ente_esfera,
         autor_nome, advogados, oabs, elegivel, total_count
    from ag
   order by valor_acao desc nulls last
   limit greatest(p_limit,1) offset greatest(p_offset,0);
$function$;

grant execute on function public.buscar_processos(text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer) to anon, authenticated;

-- Resumo de descobertas (incidentes criados hoje / últimos 7 dias, BRT), em linhas
-- planas (periodo, dimensao, chave, n) — o frontend pivota em cards.
create or replace function public.resumo_descobertas()
returns table(periodo text, dimensao text, chave text, n bigint)
language sql stable security definer set search_path to 'public'
as $function$
  with base as (
    select i.tipo_previsto, i.fase, coalesce(p.ente_esfera,'Outro') as esfera,
           (i.created_at at time zone 'America/Sao_Paulo')::date as d
    from incidentes i join processos p on p.id = i.processo_id
    where p.flag_sp
  ),
  per as (
    select 'dia'::text as periodo, tipo_previsto, fase, esfera from base
      where d = (now() at time zone 'America/Sao_Paulo')::date
    union all
    select 'semana'::text, tipo_previsto, fase, esfera from base
      where d >= (now() at time zone 'America/Sao_Paulo')::date - 6
  )
  select periodo, 'total'::text, 'total'::text, count(*) from per group by periodo
  union all select periodo, 'esfera', esfera, count(*) from per group by periodo, esfera
  union all select periodo, 'instrumento', coalesce(tipo_previsto,'Indefinido'), count(*) from per group by periodo, tipo_previsto
  union all select periodo, 'fase', coalesce(fase,'(sem fase)'), count(*) from per group by periodo, fase;
$function$;

grant execute on function public.resumo_descobertas() to anon, authenticated;
