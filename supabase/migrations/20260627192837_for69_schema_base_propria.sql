-- =============================================================
-- FOR-69 — Schema da base própria (normalizado) + idempotência
-- Módulo Precatórios SP (FOR-68). Escopo: processos contra
-- Estado/Municípios de SP (flag_sp). Convive com `precatorios` legada.
-- Rodar no SQL Editor (padrão Lovable/Supabase).
-- Convenções: centavos BIGINT · UUID gen_random_uuid() · TIMESTAMPTZ
--             snake_case plural · idx_{tabela}_{coluna} · update_updated_at()
-- =============================================================

-- -------------------------------------------------------------
-- TABELA: processos (raiz da árvore e-SAJ)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS processos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo TEXT NOT NULL UNIQUE,          -- id interno e-SAJ (dedupe)
  cnj             TEXT,
  cnj_normalizado TEXT,                           -- só dígitos
  foro            TEXT,
  classe          TEXT,
  assunto         TEXT,
  distribuicao    DATE,
  valor_acao      BIGINT,                         -- em CENTAVOS
  data_base       DATE,
  ente_nome       TEXT,
  ente_esfera     TEXT CHECK (ente_esfera IN ('Estadual','Municipal','Outro')),
  flag_sp         BOOLEAN NOT NULL DEFAULT false,
  status          TEXT CHECK (status IN ('ativo','suspenso','extinto','arquivado')),
  last_crawled_at TIMESTAMPTZ,
  next_crawl_at   TIMESTAMPTZ,
  content_hash    TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_processos_cnj_normalizado ON processos (cnj_normalizado);
CREATE INDEX IF NOT EXISTS idx_processos_next_crawl_at   ON processos (next_crawl_at) WHERE flag_sp;
CREATE INDEX IF NOT EXISTS idx_processos_flag_esfera     ON processos (flag_sp, ente_esfera);

-- -------------------------------------------------------------
-- TABELA: cumprimentos (execução/cumprimento de sentença)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS cumprimentos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id     UUID NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  processo_codigo TEXT NOT NULL UNIQUE,
  cnj             TEXT,
  cnj_normalizado TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cumprimentos_processo_id ON cumprimentos (processo_id);

-- -------------------------------------------------------------
-- TABELA: incidentes (precatório/RPV; flags e fase derivadas em FOR-72)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS incidentes (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cumprimento_id         UUID REFERENCES cumprimentos(id) ON DELETE CASCADE,
  processo_id            UUID NOT NULL REFERENCES processos(id) ON DELETE CASCADE,  -- raiz (conveniência)
  processo_codigo        TEXT NOT NULL UNIQUE,
  numero_incidente       TEXT,                    -- 00001, 00002...
  tipo_previsto          TEXT CHECK (tipo_previsto IN ('Precatorio','RPV','Indefinido')),
  numero_depre           TEXT,                    -- .8.26.0500 (nullable)
  cnj                    TEXT,
  cnj_normalizado        TEXT,
  macrofase              TEXT CHECK (macrofase IN ('direito_creditorio','precatorio_efetivo','rpv_efetivo')),
  fase                   TEXT CHECK (fase IN ('calculo','incidente','termo','depre','oficio','oc')),
  calculo_homologado     BOOLEAN NOT NULL DEFAULT false,
  termo_declaracao       BOOLEAN NOT NULL DEFAULT false,
  oficio_expedido        BOOLEAN NOT NULL DEFAULT false,
  ordem_cronologica      BOOLEAN NOT NULL DEFAULT false,
  tramitacao_prioritaria BOOLEAN NOT NULL DEFAULT false,
  ano_oc                 INT,
  elegivel               BOOLEAN NOT NULL DEFAULT false,  -- derivado (>= termo), FOR-72
  possivelmente_pago     BOOLEAN NOT NULL DEFAULT false,  -- derivado (arquivado+pgto), FOR-72
  valor_acao             BIGINT,                  -- em CENTAVOS
  data_base              DATE,
  status                 TEXT CHECK (status IN ('ativo','suspenso','extinto','arquivado')),
  created_at             TIMESTAMPTZ DEFAULT NOW(),
  updated_at             TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_incidentes_processo_id    ON incidentes (processo_id);
CREATE INDEX IF NOT EXISTS idx_incidentes_numero_depre   ON incidentes (numero_depre);
CREATE INDEX IF NOT EXISTS idx_incidentes_macrofase_fase ON incidentes (macrofase, fase);

-- -------------------------------------------------------------
-- TABELA: partes (do incidente; multi-advogado da parte ATIVA = múltiplas linhas)
-- documento sem máscara: usado só p/ matching, NUNCA exposto cru (critical-rules §1)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS partes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id    UUID NOT NULL REFERENCES incidentes(id) ON DELETE CASCADE,
  processo_id     UUID NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  papel           TEXT NOT NULL CHECK (papel IN ('ativa','passiva')),
  nome            TEXT,
  documento       TEXT,                           -- CPF/CNPJ só dígitos
  advogado_nome   TEXT,
  oab             TEXT,
  oab_normalizada TEXT,                           -- UF+número
  sem_oab         BOOLEAN NOT NULL DEFAULT false,
  fonte           TEXT NOT NULL DEFAULT 'esaj' CHECK (fonte IN ('esaj','djen')),  -- e-SAJ prevalece
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_partes_documento       ON partes (documento);
CREATE INDEX IF NOT EXISTS idx_partes_oab_normalizada ON partes (oab_normalizada);
CREATE INDEX IF NOT EXISTS idx_partes_incidente_id    ON partes (incidente_id);

-- -------------------------------------------------------------
-- TABELA: andamentos (idempotentes — nunca sobrepõe)
-- hash = md5(data | descricao | arquivo_url)
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS andamentos (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id UUID NOT NULL REFERENCES incidentes(id) ON DELETE CASCADE,
  data         DATE,
  descricao    TEXT,
  arquivo_url  TEXT,
  hash         TEXT NOT NULL,
  created_at   TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE (incidente_id, hash)
);

CREATE INDEX IF NOT EXISTS idx_andamentos_incidente_id ON andamentos (incidente_id);

-- -------------------------------------------------------------
-- TRIGGERS updated_at
-- Função definida com CREATE OR REPLACE para tornar a migration
-- auto-suficiente (idempotente; idêntica à da migração 001).
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS processos_updated_at    ON processos;
DROP TRIGGER IF EXISTS cumprimentos_updated_at ON cumprimentos;
DROP TRIGGER IF EXISTS incidentes_updated_at   ON incidentes;
DROP TRIGGER IF EXISTS partes_updated_at       ON partes;
CREATE TRIGGER processos_updated_at    BEFORE UPDATE ON processos    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER cumprimentos_updated_at BEFORE UPDATE ON cumprimentos FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER incidentes_updated_at   BEFORE UPDATE ON incidentes   FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER partes_updated_at       BEFORE UPDATE ON partes       FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- -------------------------------------------------------------
-- RLS — admin-only (authenticated read/all); escrita via service_role.
-- SEM policy anon: resposta pública sai por edge function com CPF mascarado.
-- -------------------------------------------------------------
ALTER TABLE processos    ENABLE ROW LEVEL SECURITY;
ALTER TABLE cumprimentos ENABLE ROW LEVEL SECURITY;
ALTER TABLE incidentes   ENABLE ROW LEVEL SECURITY;
ALTER TABLE partes       ENABLE ROW LEVEL SECURITY;
ALTER TABLE andamentos   ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_all_processos"    ON processos;
DROP POLICY IF EXISTS "admin_all_cumprimentos" ON cumprimentos;
DROP POLICY IF EXISTS "admin_all_incidentes"   ON incidentes;
DROP POLICY IF EXISTS "admin_all_partes"       ON partes;
DROP POLICY IF EXISTS "admin_all_andamentos"   ON andamentos;
CREATE POLICY "admin_all_processos"    ON processos    FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_cumprimentos" ON cumprimentos FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_incidentes"   ON incidentes   FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_partes"       ON partes       FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_andamentos"   ON andamentos   FOR ALL TO authenticated USING (true);

-- =============================================================
-- FIM — FOR-69
-- Link ao legado: incidentes.numero_depre = precatorios.processo_depre (sem FK).
-- Derivados (macrofase/fase/flags/elegivel/possivelmente_pago) preenchidos por FOR-72.
-- Frescor (last_crawled_at/next_crawl_at/content_hash) usados por FOR-73.
-- =============================================================
