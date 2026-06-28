-- =============================================================
-- FOR-74 — Busca admin: RPC buscar_processos (filtros + paginação)
-- Sobre o schema novo (FOR-69) classificado (FOR-72).
-- Depende de FOR-69/FOR-72 aplicados. Re-executável.
-- =============================================================

-- 1 linha por incidente; advogados da parte ativa agregados.
CREATE OR REPLACE FUNCTION buscar_processos(
  p_q          TEXT    DEFAULT NULL,   -- documento (dígitos) ou CNJ (dígitos), substring
  p_esfera     TEXT    DEFAULT NULL,   -- Estadual|Municipal|Outro
  p_tipo       TEXT    DEFAULT NULL,   -- tipo_previsto
  p_fase       TEXT    DEFAULT NULL,
  p_macrofase  TEXT    DEFAULT NULL,
  p_advogado   TEXT    DEFAULT NULL,   -- nome (ilike)
  p_oab        TEXT    DEFAULT NULL,   -- oab_normalizada
  p_valor_min  BIGINT  DEFAULT NULL,
  p_elegivel   BOOLEAN DEFAULT NULL,
  p_status     TEXT    DEFAULT NULL,
  p_limit      INT     DEFAULT 50,
  p_offset     INT     DEFAULT 0
)
RETURNS TABLE (
  incidente_id      UUID,
  processo_codigo   TEXT,
  cnj               TEXT,
  numero_incidente  TEXT,
  tipo_previsto     TEXT,
  numero_depre      TEXT,
  macrofase         TEXT,
  fase              TEXT,
  status            TEXT,
  valor_acao        BIGINT,
  data_base         DATE,
  ente_nome         TEXT,
  ente_esfera       TEXT,
  autor_nome        TEXT,
  advogados         TEXT,
  oabs              TEXT,
  elegivel          BOOLEAN,
  total_count       BIGINT
)
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  WITH base AS (
    SELECT i.id AS incidente_id, i.processo_codigo, i.cnj, i.numero_incidente, i.tipo_previsto,
           i.numero_depre, i.macrofase, i.fase, i.status, i.valor_acao, i.data_base, i.elegivel,
           p.ente_nome, p.ente_esfera, p.cnj_normalizado AS p_cnj_norm
      FROM incidentes i
      JOIN processos p ON p.id = i.processo_id
     WHERE p.flag_sp
       AND (p_esfera    IS NULL OR p.ente_esfera = p_esfera)
       AND (p_tipo      IS NULL OR i.tipo_previsto = p_tipo)
       AND (p_fase      IS NULL OR i.fase = p_fase)
       AND (p_macrofase IS NULL OR i.macrofase = p_macrofase)
       AND (p_status    IS NULL OR i.status = p_status)
       AND (p_valor_min IS NULL OR i.valor_acao >= p_valor_min)
       AND (p_elegivel  IS NULL OR i.elegivel = p_elegivel)
       AND (p_q IS NULL OR i.cnj_normalizado ILIKE '%'||regexp_replace(p_q,'\D','','g')||'%'
            OR EXISTS (SELECT 1 FROM partes d WHERE d.incidente_id = i.id
                        AND d.documento ILIKE '%'||regexp_replace(p_q,'\D','','g')||'%'))
       AND (p_advogado IS NULL OR EXISTS (SELECT 1 FROM partes a WHERE a.incidente_id = i.id
                        AND a.papel='ativa' AND a.advogado_nome ILIKE '%'||p_advogado||'%'))
       AND (p_oab IS NULL OR EXISTS (SELECT 1 FROM partes a WHERE a.incidente_id = i.id
                        AND a.papel='ativa' AND a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
  ),
  ag AS (
    SELECT b.*,
           (SELECT nome FROM partes WHERE incidente_id=b.incidente_id AND papel='ativa' AND nome IS NOT NULL LIMIT 1) AS autor_nome,
           (SELECT string_agg(DISTINCT advogado_nome, ', ') FROM partes WHERE incidente_id=b.incidente_id AND papel='ativa' AND advogado_nome IS NOT NULL) AS advogados,
           (SELECT string_agg(DISTINCT oab, ', ') FROM partes WHERE incidente_id=b.incidente_id AND papel='ativa' AND oab IS NOT NULL) AS oabs,
           count(*) OVER() AS total_count
      FROM base b
  )
  SELECT incidente_id, processo_codigo, cnj, numero_incidente, tipo_previsto, numero_depre,
         macrofase, fase, status, valor_acao, data_base, ente_nome, ente_esfera,
         autor_nome, advogados, oabs, elegivel, total_count
    FROM ag
   ORDER BY valor_acao DESC NULLS LAST
   LIMIT GREATEST(p_limit,1) OFFSET GREATEST(p_offset,0);
$$;

GRANT EXECUTE ON FUNCTION buscar_processos(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,BIGINT,BOOLEAN,TEXT,INT,INT)
  TO authenticated, service_role;

-- =============================================================
-- FIM — FOR-74. Busca pública = edge function buscar-precatorio.
-- =============================================================
