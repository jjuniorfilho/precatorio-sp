-- FOR-72 (revisão) — classificacao_regras estava VAZIA em produção (0 linhas, nem
-- inativas) — a seed original (migration FOR-72) nunca chegou a ficar persistida. Sem
-- nenhuma regra, todo flag (calculo_homologado/termo_declaracao/oficio_expedido/
-- ordem_cronologica/possivelmente_pago) sempre dava false, e o fallback do CASE (ELSE
-- 'calculo') virava o destino de quase tudo — 104.312 dos 105.919 incidentes com
-- fase='calculo' tinham calculo_homologado=false (98,5%), rotulados incorretamente como
-- "Homologação de cálculo" sem nenhuma evidência real.
--
-- Nesta revisão, validado contra andamentos reais (amostragem ao vivo via VPS):
--   - 'Incidente Processual Instaurado' — título dedicado, recorrente. NOVO flag
--     (antes só inferido estruturalmente por tipo_previsto <> 'Indefinido').
--   - 'Expedição de Ofício Requisitório Deferido' — autorização judicial do ofício,
--     fase distinta e ANTERIOR à emissão física ("...Expedido"). NOVO flag/fase.
--     O negativo ("...Indeferido") tem palavra diferente — não corre risco de match.
--   - 'cálculo homologado' isolado: não existe andamento próprio pra isso neste
--     tribunal — aparece embutido dentro do texto de "Ofício Deferido" ("nos termos do
--     cálculo homologado às fls..."). Mantido o padrão original (raro, mas inofensivo)
--     como sinal fraco; não é mais o único caminho pra sair do fallback.
--   - Fallback genuíno (nada detectado) agora vira fase='inicial', não mais 'calculo' —
--     esse é o fix do bug original (não reusar o rótulo de uma fase real pro "não sei").
--
-- Pipeline revisado (7 fases, era 6):
--   calculo → incidente → termo → oficio_deferido → depre → oficio → oc
-- (oficio_deferido fica antes de depre — o protocolo no DEPRE só existe depois que o
-- ofício foi autorizado).
--
-- Aplicar no SQL Editor.

-- -------------------------------------------------------------
-- 1. classificacao_regras: unique constraint (a original não tinha — reinserção sem
--    isso duplicaria linhas a cada reaplicação) + seed revisado.
-- -------------------------------------------------------------
ALTER TABLE classificacao_regras
  ADD CONSTRAINT classificacao_regras_flag_padrao_uniq UNIQUE (flag, padrao);

-- Novos flags possíveis (a CHECK original não previa incidente_instaurado/oficio_deferido).
ALTER TABLE classificacao_regras DROP CONSTRAINT IF EXISTS classificacao_regras_flag_check;
ALTER TABLE classificacao_regras ADD CONSTRAINT classificacao_regras_flag_check
  CHECK (flag IN ('calculo_homologado','incidente_instaurado','termo_declaracao',
                   'oficio_deferido','oficio_expedido','ordem_cronologica','possivelmente_pago'));

TRUNCATE classificacao_regras;

INSERT INTO classificacao_regras (flag, padrao, tipo) VALUES
  ('calculo_homologado',   '%homologaç%cálculo%',                       'ilike'),
  ('incidente_instaurado', '%Incidente Processual Instaurado%',         'ilike'),
  ('termo_declaracao',     '%termo de declaraç%',                       'ilike'),
  ('oficio_deferido',      '%Expedição de Ofício Requisitório Deferido%','ilike'),
  ('oficio_expedido',      '%ofício requisitório%expedido%',            'ilike'),
  ('oficio_expedido',      '%precatório expedido%',                     'ilike'),
  ('oficio_expedido',      '%pequeno valor expedido%',                  'ilike'),
  ('ordem_cronologica',    '%ordem cronológica%',                       'ilike'),
  ('possivelmente_pago',   '%arquivado definitivamente%',               'ilike');

-- -------------------------------------------------------------
-- 2. incidentes: colunas novas.
-- -------------------------------------------------------------
ALTER TABLE incidentes
  ADD COLUMN IF NOT EXISTS incidente_instaurado BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS oficio_deferido       BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS fase_desde            DATE;

-- -------------------------------------------------------------
-- 3. classify_processo: reescrita com os novos flags + fase_desde (data do andamento
--    que efetivamente determinou a fase atual — "entrou na fase pela última vez").
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
    -- Fallback genuíno agora é 'inicial' (não mais 'calculo') — não reusa o rótulo de
    -- uma fase real quando nenhum marco foi detectado.
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
             WHEN m.has_depre                   THEN NULL  -- estrutural (numero_depre), sem andamento associado
             WHEN COALESCE(m.f_deferido, false) THEN m.d_deferido
             WHEN COALESCE(m.f_termo,    false) THEN m.d_termo
             WHEN COALESCE(m.f_incidente,false) THEN m.d_incidente
             WHEN i.tipo_previsto <> 'Indefinido' THEN NULL  -- estrutural, sem andamento
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
-- NOTA sobre reclassificação em massa: NÃO rode `select classify_all();` direto no SQL
-- Editor — são ~88.700 processos, e classify_all() roda tudo numa transação só (uma
-- falha/timeout no meio derruba tudo, sem progresso parcial salvo). A reclassificação
-- será feita por um script externo (VPS), chamando classify_processo processo a
-- processo, com progresso visível e tolerância a falha individual.
-- -------------------------------------------------------------
