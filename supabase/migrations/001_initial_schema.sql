-- =============================================================
-- Migração 001: Schema inicial — Consulta Precatório SP
-- Rodar no SQL Editor do Lovable Cloud (ou Supabase)
-- =============================================================

-- ---------------------------------------------------------------
-- TABELA: precatorios
-- Dados públicos importados do DEPRE (TJSP)
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS precatorios (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_depre  TEXT NOT NULL,
  autos           TEXT,
  devedora        TEXT NOT NULL,
  saldo_depre     BIGINT NOT NULL DEFAULT 0,  -- em centavos
  natureza        TEXT NOT NULL CHECK (natureza IN ('Alimentar', 'Outras')),
  status          TEXT NOT NULL CHECK (status IN ('Ativo', 'Sem saldo', 'Suspenso')),
  suspenso        BOOLEAN NOT NULL DEFAULT false,
  data_protocolo  DATE,
  autor           TEXT,
  cpf_titular     TEXT,   -- CPF sem máscara (11 dígitos)
  cnpj_titular    TEXT,   -- CNPJ sem máscara (14 dígitos)
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_precatorios_processo ON precatorios (processo_depre);
CREATE INDEX IF NOT EXISTS idx_precatorios_autos    ON precatorios (autos);
CREATE INDEX IF NOT EXISTS idx_precatorios_cpf      ON precatorios (cpf_titular);
CREATE INDEX IF NOT EXISTS idx_precatorios_cnpj     ON precatorios (cnpj_titular);

-- ---------------------------------------------------------------
-- TABELA: leads
-- Leads capturados com dois canais validados
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS leads (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                    TEXT NOT NULL,
  email                   TEXT NOT NULL,
  telefone                TEXT NOT NULL,
  relacao                 TEXT NOT NULL CHECK (relacao IN ('titular', 'herdeiro', 'advogado')),
  processo_depre          TEXT NOT NULL,
  saldo_consultado        BIGINT NOT NULL DEFAULT 0,  -- em centavos
  devedora                TEXT,
  status_crm              TEXT NOT NULL DEFAULT 'novo'
                            CHECK (status_crm IN ('novo','contatado','qualificado','interessado','proposta','negociacao','fechado','descartado')),
  notas                   TEXT DEFAULT '',
  token_email_validado    BOOLEAN NOT NULL DEFAULT false,
  token_telefone_validado BOOLEAN NOT NULL DEFAULT false,
  session_id              TEXT,
  utm_source              TEXT,
  utm_medium              TEXT,
  utm_campaign            TEXT,
  lgpd_consent            BOOLEAN NOT NULL DEFAULT false,
  lgpd_consent_at         TIMESTAMPTZ,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_leads_status_crm  ON leads (status_crm);
CREATE INDEX IF NOT EXISTS idx_leads_created_at  ON leads (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_email       ON leads (email);

-- ---------------------------------------------------------------
-- TABELA: tokens
-- Tokens OTP — acesso somente via service role
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id    UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  canal      TEXT NOT NULL CHECK (canal IN ('email', 'whatsapp')),
  codigo     TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  usado      BOOLEAN NOT NULL DEFAULT false,
  tentativas INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_tokens_lead_canal ON tokens (lead_id, canal);

-- ---------------------------------------------------------------
-- TABELA: funnel_events
-- Rastreamento anônimo do funil de conversão
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS funnel_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  TEXT NOT NULL,
  lead_id     UUID REFERENCES leads(id) ON DELETE SET NULL,
  event_type  TEXT NOT NULL CHECK (event_type IN (
    'busca_realizada',
    'resultado_exibido',
    'cadastro_iniciado',
    'token_email_enviado',
    'token_email_validado',
    'token_whatsapp_enviado',
    'token_whatsapp_validado',
    'lead_completo'
  )),
  context     JSONB DEFAULT '{}',
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_funnel_session    ON funnel_events (session_id);
CREATE INDEX IF NOT EXISTS idx_funnel_event_type ON funnel_events (event_type);
CREATE INDEX IF NOT EXISTS idx_funnel_created_at ON funnel_events (created_at DESC);

-- ---------------------------------------------------------------
-- TABELA: lead_status_history
-- Histórico de mudanças de status CRM
-- ---------------------------------------------------------------
CREATE TABLE IF NOT EXISTS lead_status_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id         UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  status_anterior TEXT,
  status_novo     TEXT NOT NULL,
  changed_by      TEXT,
  changed_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_status_history_lead ON lead_status_history (lead_id);

-- ---------------------------------------------------------------
-- TRIGGER: updated_at automático em leads e precatorios
-- ---------------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER leads_updated_at
  BEFORE UPDATE ON leads
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER precatorios_updated_at
  BEFORE UPDATE ON precatorios
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ---------------------------------------------------------------
-- RLS: Row Level Security
-- ---------------------------------------------------------------

-- precatorios: leitura pública, escrita service role
ALTER TABLE precatorios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_precatorios"
  ON precatorios FOR SELECT TO anon, authenticated USING (true);

-- leads: somente admin autenticado
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_all_leads"
  ON leads FOR ALL TO authenticated USING (true);

-- tokens: sem acesso via anon ou authenticated — somente service role
ALTER TABLE tokens ENABLE ROW LEVEL SECURITY;
-- (nenhuma policy pública criada intencionalmente)

-- funnel_events: INSERT anônimo, SELECT admin
ALTER TABLE funnel_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_insert_funnel"
  ON funnel_events FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "admin_read_funnel"
  ON funnel_events FOR SELECT TO authenticated USING (true);

-- lead_status_history: somente admin
ALTER TABLE lead_status_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_all_status_history"
  ON lead_status_history FOR ALL TO authenticated USING (true);

-- ---------------------------------------------------------------
-- FIM DA MIGRAÇÃO 001
-- ---------------------------------------------------------------
