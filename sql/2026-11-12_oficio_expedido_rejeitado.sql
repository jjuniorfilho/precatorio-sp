-- Ofício requisitório no incidente: data de expedição, ofício rejeitado pelo DEPRE e data de deferimento.
-- (substitui 2026-11-12_data_oficio_buscar_processos_incidente.sql — os DROPs abaixo cobrem as
--  assinaturas daquele arquivo e a original; pode aplicar mesmo se aquele já tiver sido aplicado)
--
-- Contexto de negócio: a partir da expedição do ofício a dívida está reconhecida e com valor
-- determinado (marco para oferta de compra). MAS o DEPRE pode REJEITAR o ofício ("Ofício Precatório -
-- Protocolo Eletrônico Rejeitado - DEPRE ... sem processamento no DEPRE"): o precatório não recebe
-- ordem cronológica, o incidente é extinto e a vara cadastra um NOVO incidente com novo ofício.
-- Ex.: 0016525-29.2022.8.26.0053 — incidentes 01 e 02 rejeitados; o incidente 03 vale (ofício de 22/03/2023).
--
-- 1) incidentes ganha: oficio_rejeitado (sim/não/NULL = não verificado), data_oficio_rejeitado,
--    data_oficio_deferido. data_oficio_expedido (já existente) passa a ser a PRIMEIRA expedição válida.
-- 2) recalcula_oficio_incidentes(ids): calcula as 4 colunas SÓ com os andamentos do próprio incidente
--    (não usa os andamentos de cumprimento/processo, que são compartilhados entre incidentes irmãos e
--    contaminariam o incidente 03 com a rejeição do 01).
-- 3) triggers de statement em andamentos (mesmo padrão de qtd_partes_ativas) + backfill em lotes.
-- 4) buscar/contar_processos_incidente: filtros p_oficio_de/p_oficio_ate (expedição) e p_oficio_rejeitado,
--    colunas data_oficio_expedido, oficio_rejeitado, data_oficio_rejeitado, data_oficio_deferido.
-- 5) buscar_campos_grid_processo(processo_id): campos do grid que o card do incidente não tinha.
--
-- NÃO altera ano_oc: classify_* continua calculando o ano da OC por conta própria (max das datas que casam
-- 'oficio_expedido' nas 3 fontes). Ver nota no fim sobre esse ponto.
-- Ordem: 1) este arquivo  2) backfill em lotes (fim do arquivo)  3) deploy do front.
-- Re-executável.

-- ---------------------------------------------------------------------------------------------
-- 1) colunas
-- ---------------------------------------------------------------------------------------------
ALTER TABLE public.incidentes
  ADD COLUMN IF NOT EXISTS oficio_rejeitado BOOLEAN,
  ADD COLUMN IF NOT EXISTS data_oficio_rejeitado DATE,
  ADD COLUMN IF NOT EXISTS data_oficio_deferido DATE;

COMMENT ON COLUMN public.incidentes.oficio_rejeitado IS
  'true = o DEPRE rejeitou o ofício deste incidente; false = andamentos lidos e sem rejeição; NULL = não verificado (sem andamentos).';
COMMENT ON COLUMN public.incidentes.data_oficio_expedido IS
  'Data da PRIMEIRA expedição válida do ofício requisitório (andamentos do incidente que casam as regras oficio_expedido, excluídos avisos de rejeição).';

CREATE INDEX IF NOT EXISTS idx_incidentes_data_oficio_expedido
  ON public.incidentes (data_oficio_expedido) WHERE data_oficio_expedido IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_incidentes_oficio_rejeitado
  ON public.incidentes (oficio_rejeitado) WHERE oficio_rejeitado IS TRUE;

-- ---------------------------------------------------------------------------------------------
-- 2) recálculo por incidente
-- ---------------------------------------------------------------------------------------------
-- SECURITY DEFINER + GRANT: o worker pode autenticar como `authenticated` (login admin) e o trigger roda com a
-- role de quem insere em andamentos — sem isso dá "permission denied for function" (vide
-- 2026-11-09_fix_recalcula_qtd_partes_ativas_grant.sql).
CREATE OR REPLACE FUNCTION public.recalcula_oficio_incidentes(p_ids uuid[])
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  WITH ands AS (
    SELECT a.incidente_id, a.data,
           -- aviso de rejeição pelo DEPRE (título "...Protocolo Eletrônico Rejeitado - DEPRE", o texto
           -- "foi rejeitado, sem processamento no DEPRE" e o despacho "ofício requisitório rejeitado pela DEPRE")
           (a.descricao ILIKE '%Protocolo Eletrônico Rejeitado%'
            OR a.descricao ILIKE '%rejeitado, sem processamento no DEPRE%'
            OR a.descricao ILIKE '%ofício requisitório rejeitado pela DEPRE%') AS rej,
           EXISTS (SELECT 1 FROM public.classificacao_regras r
                    WHERE r.ativo AND r.flag = 'oficio_expedido'
                      AND ((r.tipo = 'ilike' AND a.descricao ILIKE r.padrao)
                        OR (r.tipo = 'regex' AND a.descricao ~* r.padrao))) AS is_exp,
           EXISTS (SELECT 1 FROM public.classificacao_regras r
                    WHERE r.ativo AND r.flag = 'oficio_deferido'
                      AND ((r.tipo = 'ilike' AND a.descricao ILIKE r.padrao)
                        OR (r.tipo = 'regex' AND a.descricao ~* r.padrao))) AS is_def
      FROM public.andamentos a
     WHERE a.incidente_id = ANY (p_ids)
  ),
  agg AS (
    SELECT x.id,
           count(a.incidente_id)                                             AS n,
           min(a.data) FILTER (WHERE a.is_exp AND NOT a.rej)                 AS d_exp,
           min(a.data) FILTER (WHERE a.is_def AND NOT a.rej)                 AS d_def,
           bool_or(a.rej)                                                    AS tem_rej,
           min(a.data) FILTER (WHERE a.rej)                                  AS d_rej
      FROM unnest(p_ids) AS x(id)
      LEFT JOIN ands a ON a.incidente_id = x.id
     GROUP BY x.id
  )
  UPDATE public.incidentes i
     SET -- sem andamento próprio que case: mantém a data que o classify gravou (pode vir de andamento de
         -- cumprimento/processo), exceto se ela for a data de um aviso de rejeição (valor errado herdado)
         data_oficio_expedido  = COALESCE(agg.d_exp,
                                   CASE WHEN i.data_oficio_expedido IS NOT DISTINCT FROM agg.d_rej
                                        THEN NULL ELSE i.data_oficio_expedido END),
         data_oficio_deferido  = agg.d_def,
         oficio_rejeitado      = CASE WHEN agg.n = 0 THEN NULL ELSE COALESCE(agg.tem_rej, false) END,
         data_oficio_rejeitado = agg.d_rej
    FROM agg
   WHERE i.id = agg.id
     AND (i.data_oficio_expedido  IS DISTINCT FROM COALESCE(agg.d_exp,
                CASE WHEN i.data_oficio_expedido IS NOT DISTINCT FROM agg.d_rej THEN NULL ELSE i.data_oficio_expedido END)
       OR i.data_oficio_deferido  IS DISTINCT FROM agg.d_def
       OR i.oficio_rejeitado      IS DISTINCT FROM (CASE WHEN agg.n = 0 THEN NULL ELSE COALESCE(agg.tem_rej, false) END)
       OR i.data_oficio_rejeitado IS DISTINCT FROM agg.d_rej);
$$;

-- ---------------------------------------------------------------------------------------------
-- 3) triggers de statement em andamentos (o crawler faz delete+insert por incidente)
-- ---------------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_andamentos_oficio_ins() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.recalcula_oficio_incidentes(ARRAY(SELECT DISTINCT incidente_id FROM new_rows WHERE incidente_id IS NOT NULL));
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.trg_andamentos_oficio_del() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  PERFORM public.recalcula_oficio_incidentes(ARRAY(SELECT DISTINCT incidente_id FROM old_rows WHERE incidente_id IS NOT NULL));
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS andamentos_oficio_ins ON public.andamentos;
CREATE TRIGGER andamentos_oficio_ins AFTER INSERT ON public.andamentos
  REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_andamentos_oficio_ins();

DROP TRIGGER IF EXISTS andamentos_oficio_del ON public.andamentos;
CREATE TRIGGER andamentos_oficio_del AFTER DELETE ON public.andamentos
  REFERENCING OLD TABLE AS old_rows FOR EACH STATEMENT EXECUTE FUNCTION public.trg_andamentos_oficio_del();

-- Backfill por keyset (evita timeout do SQL Editor). Devolve o último id do lote; repetir com o retorno
-- como p_after até vir NULL. Comece com p_limit baixo (ex.: 5000) e meça.
--   select public.backfill_oficio_incidentes_lote(null, 5000);
CREATE OR REPLACE FUNCTION public.backfill_oficio_incidentes_lote(p_after uuid DEFAULT NULL, p_limit int DEFAULT 5000)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE ids uuid[]; ultimo uuid;
BEGIN
  SELECT array_agg(id ORDER BY id) INTO ids FROM (
    SELECT id FROM public.incidentes
     WHERE (p_after IS NULL OR id > p_after)
     ORDER BY id LIMIT p_limit) s;
  IF ids IS NULL THEN RETURN NULL; END IF;
  ultimo := ids[array_length(ids, 1)];
  PERFORM public.recalcula_oficio_incidentes(ids);
  RETURN ultimo;
END $$;

CREATE OR REPLACE FUNCTION public.backfill_oficio_incidentes_loop(
  p_after uuid DEFAULT NULL, p_lotes int DEFAULT 3, p_limit int DEFAULT 5000)
RETURNS uuid LANGUAGE plpgsql AS $$
DECLARE cur uuid := p_after; prox uuid;
BEGIN
  FOR i IN 1..greatest(p_lotes, 1) LOOP
    prox := public.backfill_oficio_incidentes_lote(cur, p_limit);
    IF prox IS NULL THEN RETURN NULL; END IF;
    cur := prox;
  END LOOP;
  RETURN cur;
END $$;

REVOKE ALL ON FUNCTION public.recalcula_oficio_incidentes(uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.recalcula_oficio_incidentes(uuid[]) TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.backfill_oficio_incidentes_lote(uuid, int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.backfill_oficio_incidentes_loop(uuid, int, int) FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 4) buscar_processos_incidente (base: 2026-11-08_qtd_partes_buscar_processos_incidente.sql)
--    Os filtros novos entram POR FORA de _where_processo_incidente (concatenados ao v_where devolvido):
--    essa função foi reescrita várias vezes em produção (for189/for203) e copiar o corpo daqui
--    arriscaria reverter correções ao vivo. Conferir antes que a versão ao vivo não divergiu:
--      select pg_get_functiondef('public.buscar_processos_incidente'::regproc);
-- ---------------------------------------------------------------------------------------------
drop function if exists public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,
  integer,integer,text,integer,boolean,date,date,boolean,text,text
);
drop function if exists public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,
  integer,integer,text,integer,boolean,date,date,boolean,text,text,date,date
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
  p_crawleado boolean default null,
  p_cessao_credito text default null,
  p_acordo_homologado text default null,
  p_oficio_de date default null, p_oficio_ate date default null,
  p_oficio_rejeitado text default null)
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
  cessao_credito boolean, acordo_homologado boolean,
  has_more boolean, processo_cnj text,
  adv_autor_nome text, adv_autor_oab text,
  qtd_partes_ativas integer,
  data_oficio_expedido date, oficio_rejeitado boolean,
  data_oficio_rejeitado date, data_oficio_deferido date)
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
    p_crawler_data_de, p_crawler_data_ate, p_crawleado,
    p_cessao_credito, p_acordo_homologado);

  -- "Ofício expedido em": período inclusivo; linhas sem data (ofício não expedido) ficam de fora.
  if p_oficio_de is not null then
    v_where := v_where || format(' and i.data_oficio_expedido >= %L::date', p_oficio_de);
  end if;
  if p_oficio_ate is not null then
    v_where := v_where || format(' and i.data_oficio_expedido <= %L::date', p_oficio_ate);
  end if;
  -- "Ofício rejeitado": sim / nao / nao_verificado (NULL = incidente sem andamentos lidos).
  if p_oficio_rejeitado = 'sim' then
    v_where := v_where || ' and i.oficio_rejeitado is true';
  elsif p_oficio_rejeitado = 'nao' then
    v_where := v_where || ' and i.oficio_rejeitado is false';
  elsif p_oficio_rejeitado = 'nao_verificado' then
    v_where := v_where || ' and i.oficio_rejeitado is null';
  end if;

  v_sql := format($sql$
    with base as (
      select i.id as incidente_id,
             coalesce(c.cnj, p.cnj) as cumprimento_cnj,
             p.cnj as processo_cnj,
             i.numero_incidente, i.numero_depre, i.valor_acao,
             i.fase, i.fase_desde, i.status,
             i.tipo_previsto, i.macrofase, i.elegivel, i.possivelmente_pago,
             i.ordem_cronologica, i.tramitacao_prioritaria, i.ano_oc, i.data_base,
             i.cessao_credito, i.qtd_partes_ativas,
             i.data_oficio_expedido, i.oficio_rejeitado, i.data_oficio_rejeitado, i.data_oficio_deferido,
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
           pg.processo_cnj,
           adv.nome as adv_autor_nome, adv.oab as adv_autor_oab,
           pg.qtd_partes_ativas,
           pg.data_oficio_expedido, pg.oficio_rejeitado, pg.data_oficio_rejeitado, pg.data_oficio_deferido
      from paged pg
      left join lateral (
        select string_agg(x.advogado_nome, '; ' order by x.advogado_nome) as nome,
               string_agg(coalesce(x.oab, '—'), '; ' order by x.advogado_nome) as oab
          from (select distinct pt.advogado_nome, pt.oab
                  from partes pt
                 where pt.incidente_id = pg.incidente_id and pt.papel = 'ativa'
                   and pt.advogado_nome is not null) x
      ) adv on true
     order by pg.valor_acao desc nulls last
  $sql$, v_where, v_limit + 1, v_offset, v_limit, v_limit);

  return query execute v_sql;
end;
$function$;

grant execute on function public.buscar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,
  integer,integer,text,integer,boolean,date,date,boolean,text,text,date,date,text
) to anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- contar_processos_incidente (base: 2026-10-21_for202_rpcs_cessao_credito_enum.sql)
-- ---------------------------------------------------------------------------------------------
drop function if exists public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,
  text,integer,boolean,date,date,boolean,text,text
);
drop function if exists public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,
  text,integer,boolean,date,date,boolean,text,text,date,date
);

create or replace function public.contar_processos_incidente(
  p_q text default null, p_esfera text default null, p_tipo text default null,
  p_fase text default null, p_macrofase text default null, p_advogado text default null,
  p_oab text default null, p_valor_min bigint default null, p_valor_max bigint default null,
  p_elegivel boolean default null, p_status text default null,
  p_fase_desde_de date default null, p_fase_desde_ate date default null,
  p_ente_devedor text default null, p_ano_oc integer default null,
  p_em_cumprimento boolean default null,
  p_crawler_data_de date default null, p_crawler_data_ate date default null,
  p_crawleado boolean default null,
  p_cessao_credito text default null,
  p_acordo_homologado text default null,
  p_oficio_de date default null, p_oficio_ate date default null,
  p_oficio_rejeitado text default null)
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
    p_crawler_data_de, p_crawler_data_ate, p_crawleado,
    p_cessao_credito, p_acordo_homologado);

  if p_oficio_de is not null then
    v_where := v_where || format(' and i.data_oficio_expedido >= %L::date', p_oficio_de);
  end if;
  if p_oficio_ate is not null then
    v_where := v_where || format(' and i.data_oficio_expedido <= %L::date', p_oficio_ate);
  end if;
  if p_oficio_rejeitado = 'sim' then
    v_where := v_where || ' and i.oficio_rejeitado is true';
  elsif p_oficio_rejeitado = 'nao' then
    v_where := v_where || ' and i.oficio_rejeitado is false';
  elsif p_oficio_rejeitado = 'nao_verificado' then
    v_where := v_where || ' and i.oficio_rejeitado is null';
  end if;

  v_sql := format(
    'select count(*) from incidentes i join processos p on p.id = i.processo_id where %s',
    v_where);

  execute v_sql into v_count;
  return v_count;
end;
$function$;

grant execute on function public.contar_processos_incidente(
  text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,
  text,integer,boolean,date,date,boolean,text,text,date,date,text
) to anon, authenticated;

-- ---------------------------------------------------------------------------------------------
-- 5) campos do grid que o card do incidente não mostrava (1 chamada por processo, não por incidente)
--    valor pago, titular, acordo homologado e último andamento — mesmas fontes do grid.
-- ---------------------------------------------------------------------------------------------
create or replace function public.buscar_campos_grid_processo(p_processo_id uuid)
returns table(
  incidente_id uuid, valor_pago bigint, titular_nome text, titular_documento text,
  acordo_homologado boolean, data_ultimo_andamento date)
language sql stable security definer set search_path to 'public'
as $$
  select i.id,
         (select sum(pg.valor)::bigint from precatorios_pagamentos pg where pg.processo_depre = i.numero_depre),
         (select d.titular_nome from djen_depre d where d.cnj_normalizado = regexp_replace(coalesce(i.numero_depre,''), '\D', '', 'g') limit 1),
         (select d.titular_documento from djen_depre d where d.cnj_normalizado = regexp_replace(coalesce(i.numero_depre,''), '\D', '', 'g') limit 1),
         (select d.acordo_homologado from djen_depre d where d.cnj_normalizado = regexp_replace(coalesce(i.numero_depre,''), '\D', '', 'g') limit 1),
         (select max(a.data) from andamentos a where a.incidente_id = i.id)
    from incidentes i
   where i.processo_id = p_processo_id;
$$;

grant execute on function public.buscar_campos_grid_processo(uuid) to anon, authenticated;

notify pgrst, 'reload schema';

-- ---------------------------------------------------------------------------------------------
-- BACKFILL (depois de aplicar tudo acima). Repetir com o id devolvido até vir NULL:
--   select public.backfill_oficio_incidentes_loop(null, 3, 5000);
--   select public.backfill_oficio_incidentes_loop('<id devolvido>', 3, 5000);
--
-- CONFERÊNCIA (exemplos do pedido; incidente 01 e 03 do mesmo processo):
--   select numero_incidente, numero_depre, oficio_rejeitado, data_oficio_expedido, data_oficio_rejeitado, data_oficio_deferido
--     from incidentes where numero_depre in ('0310009-34.2022.8.26.0500', '0088499-12.2023.8.26.0500', '0322104-33.2021.8.26.0500');
--   -- esperado: 0310009 -> rejeitado=true, expedido=2022-10-09, rejeitado em 2022-12-06
--   --           0088499 -> rejeitado=false, expedido=2023-03-22
--   --           0322104 -> rejeitado=false, expedido=2021-08-17, deferido=2021-08-13
--   select oficio_rejeitado, count(*) from incidentes group by 1;
--
-- NOTA (ano_oc): classify_* calcula o ano da OC com max(data) dos andamentos que casam 'oficio_expedido' nas
-- 3 fontes, incluindo avisos de rejeição. Para incidentes rejeitados o ano_oc pode estar baseado na data
-- da rejeição. Não alterado aqui; vale decidir se o ano_oc deve ignorar rejeitados.
--
-- ROLLBACK: drop trigger andamentos_oficio_ins/del on andamentos; drop das funções recalcula_oficio_incidentes,
-- backfill_oficio_incidentes_*, buscar_campos_grid_processo; recriar buscar/contar a partir das bases citadas;
-- alter table incidentes drop column oficio_rejeitado, data_oficio_rejeitado, data_oficio_deferido.
-- (data_oficio_expedido foi reescrita pelo backfill — o valor antigo não é restaurado.)
