-- =============================================================
-- Migração 002: Permitir INSERT anônimo em leads
-- Necessário para o fluxo público de captura de lead
-- =============================================================

-- Anon pode inserir leads (o usuário não está autenticado no fluxo público)
CREATE POLICY "anon_insert_leads"
  ON leads FOR INSERT TO anon
  WITH CHECK (lgpd_consent = true);
