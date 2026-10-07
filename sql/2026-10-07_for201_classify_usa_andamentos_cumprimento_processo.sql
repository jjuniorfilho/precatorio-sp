-- FOR-201 (passo 2) — classify_processo/classify_incidentes passam a considerar também
-- os andamentos da PRÓPRIA página do cumprimento e do processo raiz (colunas jsonb novas
-- do passo 1, `cumprimentos.andamentos`/`processos.andamentos`), não só os da tabela
-- relacional `andamentos` (escopo: incidente).
--
-- Por quê: cessao_credito, ano_oc, fase, macrofase (e os flags que os alimentam:
-- calculo_homologado, incidente_instaurado, termo_declaracao, oficio_deferido,
-- oficio_expedido, ordem_cronologica, possivelmente_pago) são calculados via ILIKE/regex
-- de `classificacao_regras` contra o texto do andamento — mas hoje só contra andamentos do
-- INCIDENTE. Se o termo relevante (ex. "Ofício Requisitório - Cessão de Crédito") só
-- aparece no texto da página do cumprimento/processo pai (não replicado no incidente-filho),
-- nunca era detectado — nem no legado, nem em nenhum crawl futuro, porque é limitação de
-- COLETA, não de classificação. O passo 1 (migration anterior, FOR-201) já fez o crawler
-- passar a persistir esses andamentos; esta migration faz a classificação passar a lê-los.
--
-- PRÉ-REQUISITO: aplicar ANTES desta — sql/2026-10-07_for201_andamentos_cumprimento_processo.sql
-- (adiciona as colunas `cumprimentos.andamentos`/`processos.andamentos`). Sem elas, o
-- `jsonb_array_elements(c.andamentos)`/`jsonb_array_elements(p.andamentos)` abaixo falha
-- com "column does not exist".
--
-- Definição base: tirada via `pg_get_functiondef` DIRETO da produção em 2026-10-07 (não do
-- arquivo sql/2026-09-02_for143_classify_cessao_credito.sql, que por chronology de arquivo
-- parecia superado pelo fix de FOR-112 (ano_oc via calcular_oc(data_oficio_expedido)) mas
-- NÃO é — a função realmente em produção hoje ainda usa o regex antigo
-- `regexp_match(a.descricao, '(20\d{2})')`, confirmado ao vivo via pg_get_functiondef.
-- Ou seja: o fix do FOR-112 nunca chegou a ficar em produção (foi sobrescrito por um
-- CREATE OR REPLACE posterior que partiu de uma versão anterior ao FOR-112). Isso é uma
-- divergência pré-existente, FORA DO ESCOPO desta issue — não "corrigimos" aqui, só
-- preservamos o comportamento atual de produção ao estender a função. Vale uma issue
-- separada se o produto decidir que calcular_oc(data_oficio_expedido) é o comportamento
-- correto.
--
-- Mesma assinatura exata nas duas funções (0 mudança de parâmetros) — CREATE OR REPLACE
-- não exige DROP nem quebra PostgREST/grants existentes.
--
-- Sem DROP FUNCTION necessário (assinatura idêntica à de produção).

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
    -- FOR-201: une as 3 fontes de andamentos hoje persistidas. incidente (tabela
    -- relacional, pré-existente) UNION ALL cumprimento (jsonb, novo) UNION ALL processo
    -- raiz (jsonb, novo). Todo incidente tem cumprimento_id e processo_id preenchidos
    -- (confirmado em produção: 100% de cobertura), então os 2 JOINs novos nunca excluem
    -- nenhum incidente. jsonb_array_elements sobre coluna NULL (linha pré-migration ou
    -- ainda não recrawleada) dá zero linhas via COALESCE — nunca erro.
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
           max(ta.data) FILTER (WHERE r.flag = 'calculo_homologado')   AS d_calc,
           max(ta.data) FILTER (WHERE r.flag = 'incidente_instaurado') AS d_incidente,
           max(ta.data) FILTER (WHERE r.flag = 'termo_declaracao')     AS d_termo,
           max(ta.data) FILTER (WHERE r.flag = 'oficio_deferido')      AS d_deferido,
           max(ta.data) FILTER (WHERE r.flag = 'oficio_expedido')      AS d_oficio,
           max(ta.data) FILTER (WHERE r.flag = 'ordem_cronologica')    AS d_oc,
           -- FOR-201: substitui a subquery correlacionada que o ano_oc usava (só olhava
           -- `andamentos`, 1 tabela) — agora precisa cobrir as 3 fontes via todos_andamentos,
           -- então calcula aqui dentro do match, num scan só, em vez de reabrir outra query.
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
               WHEN COALESCE(m.f_oc,false)
                 THEN COALESCE((regexp_match(m.desc_oc, '(20\d{2})'))[1]::int, EXTRACT(YEAR FROM m.d_oc)::int)
               ELSE i.ano_oc
             END,
    updated_at = NOW()
  FROM match m
  WHERE m.incidente_id = i.id;
END; $$;

-- Validação (rodar após aplicar, no SQL Editor):
--
-- 1) smoke test — escolhe um processo real já crawleado e reclassifica, confirma que não
--    dá erro e os campos continuam coerentes (mesmo resultado de antes, já que a maioria
--    dos incidentes não tem nada novo em cumprimentos/processos.andamentos ainda):
-- select classify_processo(id) from processos where last_crawled_at is not null limit 1;
--
-- 2) depois que o worker (passo 1) já tiver recrawleado alguns processos com cumprimento
--    real + filho real, confirme que ao menos 1 caso de cessao_credito passou a vir de
--    cumprimentos.andamentos (não da tabela andamentos do próprio incidente):
-- select i.id, i.cessao_credito
--   from incidentes i
--   join cumprimentos c on c.id = i.cumprimento_id
--  where c.andamentos is not null
--    and exists (
--      select 1 from jsonb_array_elements(c.andamentos) e
--       where e->>'descricao' ilike 'Ofício Requisitório - Cessão de Crédito%'
--    )
--    and not exists (select 1 from andamentos a where a.incidente_id = i.id and a.descricao ilike 'Ofício Requisitório - Cessão de Crédito%')
--  limit 10;
