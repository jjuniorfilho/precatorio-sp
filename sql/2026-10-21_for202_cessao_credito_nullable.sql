-- FOR-202 — incidentes.cessao_credito vira nullable: NULL = nunca verificado, true/false
-- = verificado de verdade. Mesmo padrão exato de djen_depre.acordo_homologado (FOR-159).
--
-- Causa raiz do bug atual: dentro de classify_processo/classify_incidentes, quando um
-- incidente não tem NENHUM andamento nas 3 fontes (tabela `andamentos`, jsonb
-- `cumprimentos.andamentos`, jsonb `processos.andamentos` — FOR-201), `f_cessao` já sai
-- NULL naturalmente do bool_or/LEFT JOIN. O UPDATE final fazia
-- `cessao_credito = COALESCE(m.f_cessao, false)` — esse COALESCE apagava a diferença
-- entre "verificado, negativo" e "nunca verificado".
--
-- Medido em produção (2026-10-21, amostra estatística TABLESAMPLE SYSTEM(5) — contagem
-- exata com 3 subqueries correlacionadas competia I/O com o crawler e não terminava em
-- tempo razoável): de 871.127 incidentes com cessao_credito=false, ~23% (≈200.800) nunca
-- foram verificados de verdade. Backfill de correção é script separado
-- (sql/2026-10-21_for202_backfill_cessao_credito.sql), roda DEPOIS desta migration.
--
-- Revisão de pares (subagent database-architect, independente): abordagem confirmada
-- como a mais simples (nullable boolean, não timestamp separado, não enum de texto —
-- já são exatamente 3 estados, boolean nullable já expressa isso e mantém o mesmo tipo
-- dos outros 7 flags da mesma função). SET lock_timeout/statement_timeout antes do ALTER
-- por recomendação do revisor — evita enfileirar atrás de um classify_processo em
-- andamento e bloquear o crawler de produção (ALTER COLUMN DROP NOT NULL/DROP DEFAULT é
-- catálogo puro, sem rewrite das 887k linhas, mas pode esperar lock mais fraco segurado
-- por outra sessão).
--
-- Escopo: só `cessao_credito`. Os outros 7 flags (`calculo_homologado`,
-- `incidente_instaurado`, `termo_declaracao`, `oficio_deferido`, `oficio_expedido`,
-- `ordem_cronologica`, `possivelmente_pago`) e o resto da lógica (fase/macrofase/
-- elegivel/ano_oc/next_crawl_at) ficam byte-a-byte iguais ao que está em produção hoje —
-- decisão explícita do dono do produto (FOR-202 não ataca a mesma ambiguidade nos outros
-- flags; ver issue de follow-up a ser criada no fechamento).
--
-- Definição base capturada ao vivo via pg_get_functiondef em 2026-10-21 (não do arquivo
-- sql/2026-10-07_for201_classify_usa_andamentos_cumprimento_processo.sql — já virou
-- hábito deste projeto desconfiar do arquivo mais recente do repo e confirmar contra
-- produção, depois do achado do drift de ano_oc/calcular_oc no FOR-201). Confirmado:
-- idêntica ao que foi deployado no FOR-201, sem divergência.
--
-- Aplicar no SQL Editor. Ordem: este arquivo PRIMEIRO, depois o backfill, depois as RPCs
-- (sql/2026-10-21_for202_rpcs_cessao_credito_enum.sql).

-- -------------------------------------------------------------
-- 1. Schema: tira NOT NULL/DEFAULT. Catálogo puro — sem scan das 887k linhas.
-- -------------------------------------------------------------
SET lock_timeout = '3s';
SET statement_timeout = '5s';

ALTER TABLE incidentes
  ALTER COLUMN cessao_credito DROP NOT NULL,
  ALTER COLUMN cessao_credito DROP DEFAULT;

RESET lock_timeout;
RESET statement_timeout;

-- -------------------------------------------------------------
-- 2. classify_processo — só o bloco de cessao_credito muda.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.classify_processo(p_processo_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ttl INT;
BEGIN
  SELECT COALESCE((params->>'ttl_dias')::int, 7) INTO v_ttl
    FROM coleta_config WHERE rotina = 'crawler_esaj';
  v_ttl := COALESCE(v_ttl, 7);

  WITH todos_andamentos AS (
    SELECT i.id AS incidente_id, a.data, a.descricao
      FROM incidentes i
      JOIN andamentos a ON a.incidente_id = i.id
     WHERE i.processo_id = p_processo_id
    UNION ALL
    SELECT i.id, (elem->>'data')::date, elem->>'descricao'
      FROM incidentes i
      JOIN cumprimentos c ON c.id = i.cumprimento_id
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(c.andamentos, '[]'::jsonb)) AS elem
     WHERE i.processo_id = p_processo_id
    UNION ALL
    SELECT i.id, (elem->>'data')::date, elem->>'descricao'
      FROM incidentes i
      JOIN processos p ON p.id = i.processo_id
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.andamentos, '[]'::jsonb)) AS elem
     WHERE i.processo_id = p_processo_id
  ),
  match AS (
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
           -- FOR-202: true se existe QUALQUER andamento real (nas 3 fontes) pra este
           -- incidente, independente de ter batido alguma regra — distingue "tinha
           -- andamento mas nenhuma regra de cessão bateu" (= false, verificado) de "não
           -- tinha nenhum andamento em lugar nenhum" (= NULL, nunca verificado). Só usado
           -- pra cessao_credito; os outros flags continuam COALESCE(...,false) direto.
           bool_or(ta.incidente_id IS NOT NULL) AS tem_andamento,
           max(ta.data) FILTER (WHERE r.flag = 'calculo_homologado')   AS d_calc,
           max(ta.data) FILTER (WHERE r.flag = 'incidente_instaurado') AS d_incidente,
           max(ta.data) FILTER (WHERE r.flag = 'termo_declaracao')     AS d_termo,
           max(ta.data) FILTER (WHERE r.flag = 'oficio_deferido')      AS d_deferido,
           max(ta.data) FILTER (WHERE r.flag = 'oficio_expedido')      AS d_oficio,
           max(ta.data) FILTER (WHERE r.flag = 'ordem_cronologica')    AS d_oc,
           (array_agg(ta.descricao ORDER BY ta.data DESC NULLS LAST)
             FILTER (WHERE r.flag = 'ordem_cronologica'))[1] AS desc_oc
      FROM incidentes i
      LEFT JOIN todos_andamentos ta ON ta.incidente_id = i.id
      LEFT JOIN classificacao_regras r
        ON r.ativo
       AND ( (r.tipo = 'ilike' AND ta.descricao ILIKE r.padrao)
          OR (r.tipo = 'regex' AND ta.descricao ~* r.padrao) )
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
    -- FOR-202: era COALESCE(m.f_cessao, false) sempre — agora NULL quando não há
    -- nenhum andamento em nenhuma fonte (nunca verificado).
    cessao_credito         = CASE WHEN m.tem_andamento THEN COALESCE(m.f_cessao, false) ELSE NULL END,
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
               WHEN COALESCE(m.f_oc,false)
                 THEN COALESCE((regexp_match(m.desc_oc, '(20\d{2})'))[1]::int, EXTRACT(YEAR FROM m.d_oc)::int)
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
-- 3. classify_incidentes — mesma alteração espelhada (caminho batch, "mega" processos).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.classify_incidentes(p_incidente_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  WITH todos_andamentos AS (
    SELECT i.id AS incidente_id, a.data, a.descricao
      FROM incidentes i
      JOIN andamentos a ON a.incidente_id = i.id
     WHERE i.id = ANY(p_incidente_ids)
    UNION ALL
    SELECT i.id, (elem->>'data')::date, elem->>'descricao'
      FROM incidentes i
      JOIN cumprimentos c ON c.id = i.cumprimento_id
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(c.andamentos, '[]'::jsonb)) AS elem
     WHERE i.id = ANY(p_incidente_ids)
    UNION ALL
    SELECT i.id, (elem->>'data')::date, elem->>'descricao'
      FROM incidentes i
      JOIN processos p ON p.id = i.processo_id
      CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.andamentos, '[]'::jsonb)) AS elem
     WHERE i.id = ANY(p_incidente_ids)
  ),
  match AS (
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
           bool_or(ta.incidente_id IS NOT NULL) AS tem_andamento,
           max(ta.data) FILTER (WHERE r.flag = 'calculo_homologado')   AS d_calc,
           max(ta.data) FILTER (WHERE r.flag = 'incidente_instaurado') AS d_incidente,
           max(ta.data) FILTER (WHERE r.flag = 'termo_declaracao')     AS d_termo,
           max(ta.data) FILTER (WHERE r.flag = 'oficio_deferido')      AS d_deferido,
           max(ta.data) FILTER (WHERE r.flag = 'oficio_expedido')      AS d_oficio,
           max(ta.data) FILTER (WHERE r.flag = 'ordem_cronologica')    AS d_oc,
           (array_agg(ta.descricao ORDER BY ta.data DESC NULLS LAST)
             FILTER (WHERE r.flag = 'ordem_cronologica'))[1] AS desc_oc
      FROM incidentes i
      LEFT JOIN todos_andamentos ta ON ta.incidente_id = i.id
      LEFT JOIN classificacao_regras r
        ON r.ativo
       AND ( (r.tipo = 'ilike' AND ta.descricao ILIKE r.padrao)
          OR (r.tipo = 'regex' AND ta.descricao ~* r.padrao) )
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
    cessao_credito         = CASE WHEN m.tem_andamento THEN COALESCE(m.f_cessao, false) ELSE NULL END,
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
               WHEN COALESCE(m.f_oc,false)
                 THEN COALESCE((regexp_match(m.desc_oc, '(20\d{2})'))[1]::int, EXTRACT(YEAR FROM m.d_oc)::int)
               ELSE i.ano_oc
             END,
    updated_at = NOW()
  FROM match m
  WHERE m.incidente_id = i.id;
END; $$;

-- Validação (rodar após aplicar, no SQL Editor):
-- select cessao_credito, count(*) from incidentes group by 1; -- 3 grupos agora: true/false/null
-- select classify_processo(id) from processos where last_crawled_at is not null limit 1; -- sem erro
