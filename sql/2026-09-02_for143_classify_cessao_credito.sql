-- FOR-143 — integra a detecção de cessão de crédito ao classificador automático
-- (classificacao_regras + classify_processo/classify_incidentes), em vez de depender do
-- script ad-hoc diag_cessao_credito.sql rodado manualmente por lote. As 4 regras ILIKE abaixo
-- são as mesmas já validadas em sql/2026-09-02_diag_cessao_credito.sql. Com isso, o flag passa
-- a ser mantido sozinho: classify_processo() já é chamado inline pelo crawler e-SAJ contínuo
-- (worker-crawler/src/index.ts:104, alimentado pelo cron diário do DJEN via
-- enqueue_crawler_job) e pelo import de CSV legado (import-csv-legado.ts:452) — nenhuma
-- mudança de código TypeScript é necessária.
--
-- Precatórios conhecidos só via PDF DEPRE (sem incidente crawleado no e-SAJ) continuam sem
-- cessao_credito definido — não têm andamentos pra checar. Não é regressão, é a mesma limitação
-- de cobertura já mapeada (achado dos ~353 "sem incidente" no lote de 2.156 números de
-- acordos0500).
--
-- Aplicar no SQL Editor. Depois de aplicar, rodar `npm run reclassify-oc` uma vez na VPS pra
-- backfill retroativo em todos os incidentes já existentes.

-- -------------------------------------------------------------
-- 1. classificacao_regras: novo flag + regras.
-- -------------------------------------------------------------
ALTER TABLE classificacao_regras DROP CONSTRAINT IF EXISTS classificacao_regras_flag_check;
ALTER TABLE classificacao_regras ADD CONSTRAINT classificacao_regras_flag_check
  CHECK (flag IN ('calculo_homologado','incidente_instaurado','termo_declaracao',
                   'oficio_deferido','oficio_expedido','ordem_cronologica','possivelmente_pago',
                   'cessao_credito'));

INSERT INTO classificacao_regras (flag, padrao, tipo) VALUES
  ('cessao_credito', 'DEPRE - Informação de Cessão de Crédito%',  'ilike'),
  ('cessao_credito', 'Ofício Requisitório - Cessão de Crédito%',  'ilike'),
  ('cessao_credito', 'Decisão - Homologada a Cessão de Crédito%', 'ilike'),
  ('cessao_credito', '%+ Ofício Cessão de Crédito%',              'ilike')
ON CONFLICT (flag, padrao) DO NOTHING;

-- -------------------------------------------------------------
-- 2. incidentes: coluna nova.
-- -------------------------------------------------------------
ALTER TABLE incidentes
  ADD COLUMN IF NOT EXISTS cessao_credito BOOLEAN NOT NULL DEFAULT false;

-- -------------------------------------------------------------
-- 3. classify_processo: adiciona f_cessao ao match e cessao_credito ao UPDATE. Resto
--    idêntico a sql/2026-07-23_classificacao_regras_revisao.sql — cessão de crédito não
--    afeta fase/macrofase/elegivel/ano_oc, é só mais um flag informativo (como
--    possivelmente_pago).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION classify_processo(p_processo_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ttl INT;
BEGIN
  SELECT COALESCE((params->>'ttl_dias')::int, 7) INTO v_ttl
    FROM coleta_config WHERE rotina = 'crawler_esaj';
  v_ttl := COALESCE(v_ttl, 7);

  WITH match AS (
    SELECT i.id AS incidente_id,
           i.tipo_previsto,
           (i.numero_depre IS NOT NULL) AS has_depre,
           bool_or(r.flag = 'calculo_homologado')   AS f_calc,
           bool_or(r.flag = 'incidente_instaurado') AS f_incidente,
           bool_or(r.flag = 'termo_declaracao')     AS f_termo,
           bool_or(r.flag = 'oficio_deferido')      AS f_deferido,
           bool_or(r.flag = 'oficio_expedido')      AS f_oficio,
           bool_or(r.flag = 'ordem_cronologica')    AS f_oc,
           bool_or(r.flag = 'possivelmente_pago')   AS f_pago,
           bool_or(r.flag = 'cessao_credito')       AS f_cessao,
           max(a.data) FILTER (WHERE r.flag = 'calculo_homologado')   AS d_calc,
           max(a.data) FILTER (WHERE r.flag = 'incidente_instaurado') AS d_incidente,
           max(a.data) FILTER (WHERE r.flag = 'termo_declaracao')     AS d_termo,
           max(a.data) FILTER (WHERE r.flag = 'oficio_deferido')      AS d_deferido,
           max(a.data) FILTER (WHERE r.flag = 'oficio_expedido')      AS d_oficio,
           max(a.data) FILTER (WHERE r.flag = 'ordem_cronologica')    AS d_oc
      FROM incidentes i
      LEFT JOIN andamentos a ON a.incidente_id = i.id
      LEFT JOIN classificacao_regras r
        ON r.ativo
       AND ( (r.tipo = 'ilike' AND a.descricao ILIKE r.padrao)
          OR (r.tipo = 'regex' AND a.descricao ~* r.padrao) )
     WHERE i.processo_id = p_processo_id
     GROUP BY i.id, i.tipo_previsto, i.numero_depre
  )
  UPDATE incidentes i SET
    calculo_homologado   = COALESCE(m.f_calc,      false),
    incidente_instaurado = COALESCE(m.f_incidente, false),
    termo_declaracao      = COALESCE(m.f_termo,    false),
    oficio_deferido        = COALESCE(m.f_deferido, false),
    oficio_expedido        = COALESCE(m.f_oficio,   false),
    ordem_cronologica      = COALESCE(m.f_oc,       false),
    possivelmente_pago     = COALESCE(m.f_pago,     false),
    cessao_credito         = COALESCE(m.f_cessao,   false),
    fase = CASE
             WHEN COALESCE(m.f_oc,       false) THEN 'oc'
             WHEN COALESCE(m.f_oficio,   false) THEN 'oficio'
             WHEN m.has_depre                   THEN 'depre'
             WHEN COALESCE(m.f_deferido, false) THEN 'oficio_deferido'
             WHEN COALESCE(m.f_termo,    false) THEN 'termo'
             WHEN COALESCE(m.f_incidente,false) OR i.tipo_previsto <> 'Indefinido' THEN 'incidente'
             WHEN COALESCE(m.f_calc,     false) THEN 'calculo'
             ELSE 'inicial'
           END,
    fase_desde = CASE
             WHEN COALESCE(m.f_oc,       false) THEN m.d_oc
             WHEN COALESCE(m.f_oficio,   false) THEN m.d_oficio
             WHEN m.has_depre                   THEN NULL
             WHEN COALESCE(m.f_deferido, false) THEN m.d_deferido
             WHEN COALESCE(m.f_termo,    false) THEN m.d_termo
             WHEN COALESCE(m.f_incidente,false) THEN m.d_incidente
             WHEN i.tipo_previsto <> 'Indefinido' THEN NULL
             WHEN COALESCE(m.f_calc,     false) THEN m.d_calc
             ELSE NULL
           END,
    macrofase = CASE
                  WHEN COALESCE(m.f_oficio,false) AND i.tipo_previsto = 'RPV'        THEN 'rpv_efetivo'
                  WHEN COALESCE(m.f_oficio,false) AND i.tipo_previsto = 'Precatorio' THEN 'precatorio_efetivo'
                  ELSE 'direito_creditorio'
                END,
    elegivel = COALESCE(m.f_termo,false) AND NOT COALESCE(m.f_pago,false),
    ano_oc = CASE
               WHEN COALESCE(m.f_oc,false) THEN (
                 SELECT COALESCE(
                          (regexp_match(a.descricao, '(20\d{2})'))[1]::int,
                          EXTRACT(YEAR FROM a.data)::int )
                   FROM andamentos a
                   JOIN classificacao_regras r ON r.ativo AND r.flag = 'ordem_cronologica'
                    AND ( (r.tipo='ilike' AND a.descricao ILIKE r.padrao)
                       OR (r.tipo='regex' AND a.descricao ~* r.padrao) )
                  WHERE a.incidente_id = i.id
                  ORDER BY a.data DESC NULLS LAST
                  LIMIT 1 )
               ELSE i.ano_oc
             END,
    updated_at = NOW()
  FROM match m
  WHERE m.incidente_id = i.id;

  UPDATE processos
     SET next_crawl_at = COALESCE(last_crawled_at, NOW()) + (v_ttl || ' days')::interval,
         updated_at = NOW()
   WHERE id = p_processo_id;
END; $$;

-- -------------------------------------------------------------
-- 4. classify_incidentes: mesma alteração espelhada (contorno pra processos "mega").
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION classify_incidentes(p_incidente_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  WITH match AS (
    SELECT i.id AS incidente_id,
           i.tipo_previsto,
           (i.numero_depre IS NOT NULL) AS has_depre,
           bool_or(r.flag = 'calculo_homologado')   AS f_calc,
           bool_or(r.flag = 'incidente_instaurado') AS f_incidente,
           bool_or(r.flag = 'termo_declaracao')     AS f_termo,
           bool_or(r.flag = 'oficio_deferido')      AS f_deferido,
           bool_or(r.flag = 'oficio_expedido')      AS f_oficio,
           bool_or(r.flag = 'ordem_cronologica')    AS f_oc,
           bool_or(r.flag = 'possivelmente_pago')   AS f_pago,
           bool_or(r.flag = 'cessao_credito')       AS f_cessao,
           max(a.data) FILTER (WHERE r.flag = 'calculo_homologado')   AS d_calc,
           max(a.data) FILTER (WHERE r.flag = 'incidente_instaurado') AS d_incidente,
           max(a.data) FILTER (WHERE r.flag = 'termo_declaracao')     AS d_termo,
           max(a.data) FILTER (WHERE r.flag = 'oficio_deferido')      AS d_deferido,
           max(a.data) FILTER (WHERE r.flag = 'oficio_expedido')      AS d_oficio,
           max(a.data) FILTER (WHERE r.flag = 'ordem_cronologica')    AS d_oc
      FROM incidentes i
      LEFT JOIN andamentos a ON a.incidente_id = i.id
      LEFT JOIN classificacao_regras r
        ON r.ativo
       AND ( (r.tipo = 'ilike' AND a.descricao ILIKE r.padrao)
          OR (r.tipo = 'regex' AND a.descricao ~* r.padrao) )
     WHERE i.id = ANY(p_incidente_ids)
     GROUP BY i.id, i.tipo_previsto, i.numero_depre
  )
  UPDATE incidentes i SET
    calculo_homologado   = COALESCE(m.f_calc,      false),
    incidente_instaurado = COALESCE(m.f_incidente, false),
    termo_declaracao      = COALESCE(m.f_termo,    false),
    oficio_deferido        = COALESCE(m.f_deferido, false),
    oficio_expedido        = COALESCE(m.f_oficio,   false),
    ordem_cronologica      = COALESCE(m.f_oc,       false),
    possivelmente_pago     = COALESCE(m.f_pago,     false),
    cessao_credito         = COALESCE(m.f_cessao,   false),
    fase = CASE
             WHEN COALESCE(m.f_oc,       false) THEN 'oc'
             WHEN COALESCE(m.f_oficio,   false) THEN 'oficio'
             WHEN m.has_depre                   THEN 'depre'
             WHEN COALESCE(m.f_deferido, false) THEN 'oficio_deferido'
             WHEN COALESCE(m.f_termo,    false) THEN 'termo'
             WHEN COALESCE(m.f_incidente,false) OR i.tipo_previsto <> 'Indefinido' THEN 'incidente'
             WHEN COALESCE(m.f_calc,     false) THEN 'calculo'
             ELSE 'inicial'
           END,
    fase_desde = CASE
             WHEN COALESCE(m.f_oc,       false) THEN m.d_oc
             WHEN COALESCE(m.f_oficio,   false) THEN m.d_oficio
             WHEN m.has_depre                   THEN NULL
             WHEN COALESCE(m.f_deferido, false) THEN m.d_deferido
             WHEN COALESCE(m.f_termo,    false) THEN m.d_termo
             WHEN COALESCE(m.f_incidente,false) THEN m.d_incidente
             WHEN i.tipo_previsto <> 'Indefinido' THEN NULL
             WHEN COALESCE(m.f_calc,     false) THEN m.d_calc
             ELSE NULL
           END,
    macrofase = CASE
                  WHEN COALESCE(m.f_oficio,false) AND i.tipo_previsto = 'RPV'        THEN 'rpv_efetivo'
                  WHEN COALESCE(m.f_oficio,false) AND i.tipo_previsto = 'Precatorio' THEN 'precatorio_efetivo'
                  ELSE 'direito_creditorio'
                END,
    elegivel = COALESCE(m.f_termo,false) AND NOT COALESCE(m.f_pago,false),
    ano_oc = CASE
               WHEN COALESCE(m.f_oc,false) THEN (
                 SELECT COALESCE(
                          (regexp_match(a.descricao, '(20\d{2})'))[1]::int,
                          EXTRACT(YEAR FROM a.data)::int )
                   FROM andamentos a
                   JOIN classificacao_regras r ON r.ativo AND r.flag = 'ordem_cronologica'
                    AND ( (r.tipo='ilike' AND a.descricao ILIKE r.padrao)
                       OR (r.tipo='regex' AND a.descricao ~* r.padrao) )
                  WHERE a.incidente_id = i.id
                  ORDER BY a.data DESC NULLS LAST
                  LIMIT 1 )
               ELSE i.ano_oc
             END,
    updated_at = NOW()
  FROM match m
  WHERE m.incidente_id = i.id;
END; $$;

-- Verificação (rodar após aplicar):
-- select flag, count(*) from classificacao_regras where flag = 'cessao_credito' group by 1;  -- 4
-- select cessao_credito from incidentes where cnj = '0254129-96.2018.8.26.0500';              -- true
