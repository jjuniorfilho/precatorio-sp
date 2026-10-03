-- FOR-195 (achado em produção, 2026-10-03) — /admin/processo-incidente nunca teve coluna
-- "Processo Principal", ao contrário de /admin/leads e /admin/processos/:id. O CNJ do processo
-- principal (`processos.cnj` via `incidentes.processo_id`) já é lido e usado DENTRO da própria
-- RPC `buscar_processos_incidente` — a CTE `base` já seleciona `p.cnj as processo_cnj` (usado só
-- pra achar `crawler_status`) — mas o valor nunca chegava no SELECT final nem no RETURNS TABLE:
-- era calculado e descartado.
--
-- Fix: EXPÕE a coluna que já existe. Nenhum filtro, join ou cláusula WHERE muda — só o SELECT
-- final (acrescenta `pg.processo_cnj`) e o RETURNS TABLE (acrescenta `processo_cnj text` no FIM,
-- mesmo padrão já usado em `leads_processos`/FOR-177 pra nunca dar 42P16 trocando o shape de
-- colunas existentes). `_where_processo_incidente` e `contar_processos_incidente` (FOR-118/
-- FOR-189, cuidado documentado com performance via SQL dinâmico) ficam INTOCADOS.
--
-- Base: captura viva em sql/2026-10-01_for189_baseline_where_processo_incidente_live.sql.
--
-- DROP explícito OBRIGATÓRIO: Postgres não permite CREATE OR REPLACE FUNCTION mudar o shape de
-- RETURNS TABLE nem só ACRESCENTANDO uma coluna no fim (diferente de VIEW, que permite) — testado
-- no sandbox local, erro "cannot change return type of existing function" sem o DROP. Mesma lição
-- já documentada em sql/2026-07-31_for118_data_ultimo_crawl.sql pra esta função.
-- Aplicar no SQL Editor. Re-executável (DROP ... IF EXISTS cobre reaplicação).

DROP FUNCTION IF EXISTS public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer,boolean,date,date,boolean,boolean,text
);

CREATE FUNCTION public.buscar_processos_incidente(p_q text DEFAULT NULL::text, p_esfera text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text, p_fase text DEFAULT NULL::text, p_macrofase text DEFAULT NULL::text, p_advogado text DEFAULT NULL::text, p_oab text DEFAULT NULL::text, p_valor_min bigint DEFAULT NULL::bigint, p_valor_max bigint DEFAULT NULL::bigint, p_elegivel boolean DEFAULT NULL::boolean, p_status text DEFAULT NULL::text, p_fase_desde_de date DEFAULT NULL::date, p_fase_desde_ate date DEFAULT NULL::date, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0, p_ente_devedor text DEFAULT NULL::text, p_ano_oc integer DEFAULT NULL::integer, p_em_cumprimento boolean DEFAULT NULL::boolean, p_crawler_data_de date DEFAULT NULL::date, p_crawler_data_ate date DEFAULT NULL::date, p_crawleado boolean DEFAULT NULL::boolean, p_cessao_credito boolean DEFAULT NULL::boolean, p_acordo_homologado text DEFAULT NULL::text)
 RETURNS TABLE(incidente_id uuid, cumprimento_cnj text, numero_incidente text, numero_depre text, parte_ativa text, parte_passiva text, valor_acao bigint, fase text, fase_desde date, status text, tipo_previsto text, macrofase text, elegivel boolean, possivelmente_pago boolean, ordem_cronologica boolean, tramitacao_prioritaria boolean, ano_oc integer, saldo_depre bigint, valor_pago bigint, titular_nome text, titular_documento text, data_base date, data_ultimo_andamento date, crawler_status text, last_crawled_at timestamp with time zone, cessao_credito boolean, acordo_homologado boolean, has_more boolean, processo_cnj text)
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
           (select count(*) from page) > %s as has_more,
           pg.processo_cnj
      from paged pg order by pg.valor_acao desc nulls last
  $sql$, v_where, v_limit + 1, v_offset, v_limit, v_limit);

  return query execute v_sql;
end;
$function$;

-- Mesmo grant de sempre pra esta função (ver sql/2026-09-15_for160_cessao_acordo_colunas.sql) —
-- o DROP acima apaga os grants, então precisa reconceder (achado: GRANT não sobrevive a DROP).
grant execute on function public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer,boolean,date,date,boolean,boolean,text
) to anon, authenticated;

-- Verificação (rodar manualmente após aplicar):
-- select processo_cnj, cumprimento_cnj, numero_depre from buscar_processos_incidente(p_limit := 3);
-- (esperado: processo_cnj preenchido pra todo incidente — é NOT NULL em processos.id/i.processo_id)
-- select has_function_privilege('anon', 'buscar_processos_incidente(text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer,boolean,date,date,boolean,boolean,text)', 'execute');
-- (esperado: t — sem isso /admin/processo-incidente (anônimo) perde acesso à função)
