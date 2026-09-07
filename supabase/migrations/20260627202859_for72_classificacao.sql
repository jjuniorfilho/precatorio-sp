-- =============================================================
-- FOR-72 — Derivação de macrofase/fase a partir dos andamentos
-- Módulo Precatórios SP (FOR-68). Depende de FOR-69 (incidentes/
-- processos/andamentos) e FOR-73 (coleta_config) já aplicados.
-- Opção A: caso "sem incidente" é representado por um incidente
-- placeholder (tipo_previsto='Indefinido') criado pela FOR-71.
-- Rodar no SQL Editor. Re-executável.
-- =============================================================

-- -------------------------------------------------------------
-- Tabela de padrões de classificação (editável sem deploy)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS classificacao_regras (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  flag       TEXT NOT NULL CHECK (flag IN
               ('calculo_homologado','termo_declaracao','oficio_expedido','ordem_cronologica','possivelmente_pago')),
  padrao     TEXT NOT NULL,                  -- ILIKE/regex sobre andamentos.descricao
  tipo       TEXT NOT NULL DEFAULT 'ilike' CHECK (tipo IN ('ilike','regex')),
  prioridade INT NOT NULL DEFAULT 100,
  ativo      BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE classificacao_regras ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_all_classificacao_regras" ON classificacao_regras;
CREATE POLICY "admin_all_classificacao_regras" ON classificacao_regras FOR ALL TO authenticated USING (true);

-- Seed inicial (starter; ajustável sem migration)
INSERT INTO classificacao_regras (flag, padrao, tipo) VALUES
  ('calculo_homologado', '%homologaç%cálculo%',            'ilike'),
  ('termo_declaracao',   '%termo de declaraç%',            'ilike'),
  ('oficio_expedido',    '%ofício requisitório%expedido%', 'ilike'),
  ('oficio_expedido',    '%precatório expedido%',          'ilike'),
  ('oficio_expedido',    '%pequeno valor expedido%',       'ilike'),
  ('ordem_cronologica',  '%ordem cronológica%',            'ilike'),
  ('possivelmente_pago', '%arquivado definitivamente%',    'ilike')
ON CONFLICT DO NOTHING;

-- -------------------------------------------------------------
-- classify_processo(processo_id): recomputa flags/fase/macrofase/
-- elegivel/possivelmente_pago dos incidentes + next_crawl_at (TTL).
-- Idempotente. Inclui incidentes placeholder ('Indefinido').
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
           bool_or(r.flag = 'calculo_homologado') AS f_calc,
           bool_or(r.flag = 'termo_declaracao')   AS f_termo,
           bool_or(r.flag = 'oficio_expedido')    AS f_oficio,
           bool_or(r.flag = 'ordem_cronologica')  AS f_oc,
           bool_or(r.flag = 'possivelmente_pago') AS f_pago
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
    calculo_homologado = COALESCE(m.f_calc,  false),
    termo_declaracao   = COALESCE(m.f_termo, false),
    oficio_expedido    = COALESCE(m.f_oficio,false),
    ordem_cronologica  = COALESCE(m.f_oc,    false),
    possivelmente_pago = COALESCE(m.f_pago,  false),
    fase = CASE
             WHEN COALESCE(m.f_oc,    false) THEN 'oc'
             WHEN COALESCE(m.f_oficio,false) THEN 'oficio'
             WHEN m.has_depre                THEN 'depre'
             WHEN COALESCE(m.f_termo, false) THEN 'termo'
             WHEN i.tipo_previsto <> 'Indefinido' THEN 'incidente'
             ELSE 'calculo'
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

  -- TTL uniforme (não alongado por possivelmente_pago)
  UPDATE processos
     SET next_crawl_at = COALESCE(last_crawled_at, NOW()) + (v_ttl || ' days')::interval,
         updated_at = NOW()
   WHERE id = p_processo_id;
END; $$;

-- Reclassificação em massa (backfill / mudança de regras)
CREATE OR REPLACE FUNCTION classify_all()
RETURNS INT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r RECORD; n INT := 0;
BEGIN
  FOR r IN SELECT id FROM processos LOOP
    PERFORM classify_processo(r.id);
    n := n + 1;
  END LOOP;
  RETURN n;
END; $$;

GRANT EXECUTE ON FUNCTION classify_processo(UUID) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION classify_all()          TO service_role;

-- =============================================================
-- FIM — FOR-72
-- Aplicar APÓS FOR-69 e FOR-73. tramitacao_prioritaria é capturado
-- pela FOR-71 (capa), não aqui. possivelmente_pago é informativo.
-- =============================================================
