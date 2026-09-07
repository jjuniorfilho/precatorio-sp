-- =============================================================
-- FOR-76 — Módulo Advogados: MV de carteira + parceria + RPCs + cron.
-- Depende de FOR-69 (partes/incidentes/processos) e FOR-72 (fase/macrofase).
-- Re-executável.
-- =============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------------
-- Materialized view: carteira por advogado (chave OAB; fallback nome)
-- -------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS mv_advogado_carteira;
CREATE MATERIALIZED VIEW mv_advogado_carteira AS
WITH adv AS (
  SELECT
    COALESCE(pa.oab_normalizada, 'NOME:' || upper(pa.advogado_nome)) AS adv_key,
    pa.oab_normalizada, pa.advogado_nome, (pa.oab_normalizada IS NULL) AS sem_oab,
    i.id AS incidente_id, i.processo_id, i.tipo_previsto, i.macrofase, i.fase,
    i.valor_acao, i.elegivel, i.possivelmente_pago, p.ente_esfera
  FROM partes pa
  JOIN incidentes i ON i.id = pa.incidente_id
  JOIN processos  p ON p.id = i.processo_id
  WHERE pa.papel = 'ativa' AND pa.advogado_nome IS NOT NULL AND p.flag_sp
)
SELECT
  adv_key,
  max(oab_normalizada) AS oab_normalizada,
  max(advogado_nome)   AS advogado_nome,
  bool_and(sem_oab)    AS sem_oab,
  count(DISTINCT processo_id)  AS n_processos,
  count(DISTINCT incidente_id) AS n_incidentes,
  count(DISTINCT incidente_id) FILTER (WHERE tipo_previsto='Precatorio') AS n_prec,
  count(DISTINCT incidente_id) FILTER (WHERE tipo_previsto='RPV')        AS n_rpv,
  count(DISTINCT incidente_id) FILTER (WHERE tipo_previsto='Indefinido') AS n_indef,
  count(DISTINCT incidente_id) FILTER (WHERE ente_esfera='Estadual')  AS n_estadual,
  count(DISTINCT incidente_id) FILTER (WHERE ente_esfera='Municipal') AS n_municipal,
  COALESCE(sum(valor_acao),0) AS valor_total,
  count(DISTINCT incidente_id) FILTER (WHERE macrofase IN ('precatorio_efetivo','rpv_efetivo')) AS n_efetivo,
  count(DISTINCT incidente_id) FILTER (WHERE macrofase='direito_creditorio') AS n_em_formacao,
  count(DISTINCT incidente_id) FILTER (WHERE elegivel)           AS n_eleg,
  count(DISTINCT incidente_id) FILTER (WHERE possivelmente_pago) AS n_pago,
  count(DISTINCT incidente_id) FILTER (WHERE fase='calculo')   AS f_calculo,
  count(DISTINCT incidente_id) FILTER (WHERE fase='incidente') AS f_incidente,
  count(DISTINCT incidente_id) FILTER (WHERE fase='termo')     AS f_termo,
  count(DISTINCT incidente_id) FILTER (WHERE fase='depre')     AS f_depre,
  count(DISTINCT incidente_id) FILTER (WHERE fase='oficio')    AS f_oficio,
  count(DISTINCT incidente_id) FILTER (WHERE fase='oc')        AS f_oc,
  CASE WHEN count(*) FILTER (WHERE ente_esfera='Estadual') >= count(*) FILTER (WHERE ente_esfera='Municipal')
       THEN 'Estadual' ELSE 'Municipal' END AS esfera_predominante
FROM adv
GROUP BY adv_key;

CREATE UNIQUE INDEX IF NOT EXISTS uq_mv_advogado_carteira ON mv_advogado_carteira (adv_key);
GRANT SELECT ON mv_advogado_carteira TO authenticated;

CREATE OR REPLACE FUNCTION refresh_mv_advogados()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  REFRESH MATERIALIZED VIEW CONCURRENTLY mv_advogado_carteira;
END; $$;
GRANT EXECUTE ON FUNCTION refresh_mv_advogados() TO service_role;

-- -------------------------------------------------------------
-- Parceria (espelha leads.status_crm + lead_status_history)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS advogado_parceria (
  adv_key        TEXT PRIMARY KEY,
  oab_normalizada TEXT,
  advogado_nome  TEXT,
  status         TEXT NOT NULL DEFAULT 'novo_alvo' CHECK (status IN ('novo_alvo','em_conversa','parceria','descartado')),
  responsavel    TEXT,
  notas          TEXT DEFAULT '',
  created_at     TIMESTAMPTZ DEFAULT NOW(),
  updated_at     TIMESTAMPTZ DEFAULT NOW()
);
CREATE TABLE IF NOT EXISTS advogado_parceria_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  adv_key         TEXT NOT NULL,
  status_anterior TEXT,
  status_novo     TEXT NOT NULL,
  changed_by      TEXT,
  changed_at      TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_adv_parceria_status ON advogado_parceria (status);

ALTER TABLE advogado_parceria         ENABLE ROW LEVEL SECURITY;
ALTER TABLE advogado_parceria_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_all_adv_parceria" ON advogado_parceria;
DROP POLICY IF EXISTS "admin_all_adv_parceria_hist" ON advogado_parceria_history;
CREATE POLICY "admin_all_adv_parceria"      ON advogado_parceria         FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_adv_parceria_hist" ON advogado_parceria_history FOR ALL TO authenticated USING (true);

DROP TRIGGER IF EXISTS adv_parceria_updated_at ON advogado_parceria;
CREATE TRIGGER adv_parceria_updated_at BEFORE UPDATE ON advogado_parceria FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE OR REPLACE FUNCTION set_parceria_status(p_adv_key TEXT, p_status TEXT, p_responsavel TEXT DEFAULT NULL, p_notas TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_old TEXT; v_nome TEXT; v_oab TEXT;
BEGIN
  SELECT status INTO v_old FROM advogado_parceria WHERE adv_key = p_adv_key;
  SELECT advogado_nome, oab_normalizada INTO v_nome, v_oab FROM mv_advogado_carteira WHERE adv_key = p_adv_key;
  INSERT INTO advogado_parceria (adv_key, oab_normalizada, advogado_nome, status, responsavel, notas)
  VALUES (p_adv_key, v_oab, v_nome, p_status, p_responsavel, COALESCE(p_notas,''))
  ON CONFLICT (adv_key) DO UPDATE SET status=EXCLUDED.status,
    responsavel=COALESCE(EXCLUDED.responsavel, advogado_parceria.responsavel),
    notas=COALESCE(NULLIF(EXCLUDED.notas,''), advogado_parceria.notas), updated_at=NOW();
  INSERT INTO advogado_parceria_history (adv_key, status_anterior, status_novo, changed_by)
  VALUES (p_adv_key, v_old, p_status, p_responsavel);
END; $$;
GRANT EXECUTE ON FUNCTION set_parceria_status(TEXT,TEXT,TEXT,TEXT) TO authenticated, service_role;

-- -------------------------------------------------------------
-- buscar_advogados: lista/ranking (valor|volume) + filtros + parceria
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION buscar_advogados(
  p_q TEXT DEFAULT NULL, p_esfera TEXT DEFAULT NULL, p_oab TEXT DEFAULT NULL,
  p_ordenar TEXT DEFAULT 'valor',  -- 'valor' | 'volume'
  p_limit INT DEFAULT 50, p_offset INT DEFAULT 0
)
RETURNS TABLE (
  adv_key TEXT, oab_normalizada TEXT, advogado_nome TEXT, sem_oab BOOLEAN,
  n_processos BIGINT, n_incidentes BIGINT, n_prec BIGINT, n_rpv BIGINT, n_indef BIGINT,
  n_estadual BIGINT, n_municipal BIGINT, esfera_predominante TEXT, valor_total BIGINT,
  n_efetivo BIGINT, n_em_formacao BIGINT, n_eleg BIGINT, n_pago BIGINT,
  f_calculo BIGINT, f_incidente BIGINT, f_termo BIGINT, f_depre BIGINT, f_oficio BIGINT, f_oc BIGINT,
  parceria_status TEXT, total_count BIGINT
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT m.adv_key, m.oab_normalizada, m.advogado_nome, m.sem_oab,
         m.n_processos, m.n_incidentes, m.n_prec, m.n_rpv, m.n_indef,
         m.n_estadual, m.n_municipal, m.esfera_predominante, m.valor_total,
         m.n_efetivo, m.n_em_formacao, m.n_eleg, m.n_pago,
         m.f_calculo, m.f_incidente, m.f_termo, m.f_depre, m.f_oficio, m.f_oc,
         COALESCE(ap.status, '') AS parceria_status,
         count(*) OVER() AS total_count
    FROM mv_advogado_carteira m
    LEFT JOIN advogado_parceria ap ON ap.adv_key = m.adv_key
   WHERE (p_q IS NULL OR m.advogado_nome ILIKE '%'||p_q||'%' OR m.oab_normalizada ILIKE '%'||upper(p_q)||'%')
     AND (p_esfera IS NULL OR m.esfera_predominante = p_esfera)
     AND (p_oab IS NULL OR m.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g')))
   ORDER BY CASE WHEN p_ordenar='volume' THEN m.n_processos ELSE m.valor_total END DESC
   LIMIT GREATEST(p_limit,1) OFFSET GREATEST(p_offset,0);
$$;
GRANT EXECUTE ON FUNCTION buscar_advogados(TEXT,TEXT,TEXT,TEXT,INT,INT) TO authenticated, service_role;

-- -------------------------------------------------------------
-- Cron: refresh da MV (hourly)
-- -------------------------------------------------------------
DO $$
BEGIN PERFORM cron.unschedule('refresh-mv-advogados'); EXCEPTION WHEN OTHERS THEN NULL; END $$;
SELECT cron.schedule('refresh-mv-advogados', '15 * * * *', $$ SELECT public.refresh_mv_advogados(); $$);

-- =============================================================
-- FIM — FOR-76. Export CSV = frontend a partir de buscar_advogados.
-- =============================================================
