-- FOR-189: captura do estado VIVO em produção (nenhuma mudança de comportamento aqui).
--
-- `_where_processo_incidente` (21 params), `buscar_processos_incidente` (23 params) e
-- `contar_processos_incidente` (21 params) estavam rodando em produção sem NENHUM arquivo
-- correspondente no git — a última versão commitada de `_where_processo_incidente` é a de
-- 18 params em sql/2026-07-31_for118_data_ultimo_crawl.sql, e nunca existiu arquivo nenhum
-- pra `buscar_processos_incidente`/`contar_processos_incidente`. As colunas
-- cessao_credito/acordo_homologado (FOR-160) e crawler_data_de/ate/crawleado (FOR-118)
-- foram aplicadas direto no SQL Editor em algum momento e nunca commitadas.
--
-- Isso já causou um incidente nesta mesma sessão: reaplicar a versão de 18 params do git
-- por cima da versão viva de 21 params criou uma ambiguidade de overload (PGRST203) que
-- quebrou /admin/processo-incidente até ser diagnosticado e corrigido.
--
-- Este arquivo existe só pra fechar essa lacuna de processo — captura o texto exato
-- (via pg_get_functiondef) de como as 3 funções estavam rodando em 2026-10-01, ANTES da
-- correção de FOR-189 (ver 2026-10-01_for189_fix_where_processo_incidente_pq_timeout.sql).
-- Não precisa ser reaplicado — já está live. Serve de baseline pra qualquer `git blame`/
-- `git log` futuro neste trecho.

CREATE OR REPLACE FUNCTION public._where_processo_incidente(p_esfera text, p_tipo text, p_fase text, p_macrofase text, p_status text, p_valor_min bigint, p_valor_max bigint, p_elegivel boolean, p_fase_desde_de date, p_fase_desde_ate date, p_ano_oc integer, p_ente_devedor text, p_em_cumprimento boolean, p_q text, p_advogado text, p_oab text, p_crawler_data_de date DEFAULT NULL::date, p_crawler_data_ate date DEFAULT NULL::date, p_crawleado boolean DEFAULT NULL::boolean, p_cessao_credito boolean DEFAULT NULL::boolean, p_acordo_homologado text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
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
  if p_acordo_homologado = 'sim' then
    v_where := v_where || $sql$ and i.numero_depre is not null and exists (
      select 1 from djen_depre d
       where d.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
         and d.acordo_homologado = true
    )$sql$;
  elsif p_acordo_homologado = 'nao' then
    v_where := v_where || $sql$ and i.numero_depre is not null and exists (
      select 1 from djen_depre d
       where d.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
         and d.acordo_homologado = false
    )$sql$;
  elsif p_acordo_homologado = 'nao_verificado' then
    v_where := v_where || $sql$ and (
      i.numero_depre is null
      or not exists (
        select 1 from djen_depre d
         where d.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
           and d.acordo_homologado is not null
      )
    )$sql$;
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

CREATE OR REPLACE FUNCTION public.buscar_processos_incidente(p_q text DEFAULT NULL::text, p_esfera text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text, p_fase text DEFAULT NULL::text, p_macrofase text DEFAULT NULL::text, p_advogado text DEFAULT NULL::text, p_oab text DEFAULT NULL::text, p_valor_min bigint DEFAULT NULL::bigint, p_valor_max bigint DEFAULT NULL::bigint, p_elegivel boolean DEFAULT NULL::boolean, p_status text DEFAULT NULL::text, p_fase_desde_de date DEFAULT NULL::date, p_fase_desde_ate date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_ente_devedor text DEFAULT NULL::text, p_ano_oc integer DEFAULT NULL::integer, p_em_cumprimento boolean DEFAULT NULL::boolean, p_crawler_data_de date DEFAULT NULL::date, p_crawler_data_ate date DEFAULT NULL::date, p_crawleado boolean DEFAULT NULL::boolean, p_cessao_credito boolean DEFAULT NULL::boolean, p_acordo_homologado text DEFAULT NULL::text)
 RETURNS TABLE(incidente_id uuid, cumprimento_cnj text, numero_incidente text, numero_depre text, parte_ativa text, parte_passiva text, valor_acao bigint, fase text, fase_desde date, status text, tipo_previsto text, macrofase text, elegivel boolean, possivelmente_pago boolean, ordem_cronologica boolean, tramitacao_prioritaria boolean, ano_oc integer, saldo_depre bigint, valor_pago bigint, titular_nome text, titular_documento text, data_base date, data_ultimo_andamento date, crawler_status text, last_crawled_at timestamp with time zone, cessao_credito boolean, acordo_homologado boolean, has_more boolean)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    p_crawler_data_de, p_crawler_data_ate, p_crawleado,
    p_cessao_credito, p_acordo_homologado);

  v_sql := format($sql$
    with base as (
      select i.id as incidente_id,
             coalesce(c.cnj, p.cnj) as cumprimento_cnj,
             p.cnj as processo_cnj,
             i.numero_incidente, i.numero_depre, i.valor_acao,
             i.fase, i.fase_desde, i.status,
             i.tipo_previsto, i.macrofase, i.elegivel, i.possivelmente_pago,
             i.ordem_cronologica, i.tramitacao_prioritaria, i.ano_oc, i.data_base,
             i.cessao_credito,
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
           pg.cessao_credito,
           (select acordo_homologado from djen_depre where cnj_normalizado = regexp_replace(coalesce(pg.numero_depre,''), '\D', '', 'g') limit 1) as acordo_homologado,
           (select count(*) from page) > %s as has_more
      from paged pg order by pg.valor_acao desc nulls last
  $sql$, v_where, v_limit + 1, v_offset, v_limit, v_limit);

  return query execute v_sql;
end;
$function$;

CREATE OR REPLACE FUNCTION public.contar_processos_incidente(p_q text DEFAULT NULL::text, p_esfera text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text, p_fase text DEFAULT NULL::text, p_macrofase text DEFAULT NULL::text, p_advogado text DEFAULT NULL::text, p_oab text DEFAULT NULL::text, p_valor_min bigint DEFAULT NULL::bigint, p_valor_max bigint DEFAULT NULL::bigint, p_elegivel boolean DEFAULT NULL::boolean, p_status text DEFAULT NULL::text, p_fase_desde_de date DEFAULT NULL::date, p_fase_desde_ate date DEFAULT NULL::date, p_ente_devedor text DEFAULT NULL::text, p_ano_oc integer DEFAULT NULL::integer, p_em_cumprimento boolean DEFAULT NULL::boolean, p_crawler_data_de date DEFAULT NULL::date, p_crawler_data_ate date DEFAULT NULL::date, p_crawleado boolean DEFAULT NULL::boolean, p_cessao_credito boolean DEFAULT NULL::boolean, p_acordo_homologado text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
    p_crawler_data_de, p_crawler_data_ate, p_crawleado,
    p_cessao_credito, p_acordo_homologado);

  v_sql := format(
    'select count(*) from incidentes i join processos p on p.id = i.processo_id where %s',
    v_where);

  execute v_sql into v_count;
  return v_count;
end;
$function$;
