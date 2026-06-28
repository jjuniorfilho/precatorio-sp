-- =============================================================
-- FOR-75 — Resposta pública: captura reusando `leads` + tipo de e-mail.
-- Relaxa NOT NULLs do lead p/ captura email-only e adiciona origem/cnj.
-- Re-executável.
-- =============================================================

ALTER TABLE leads ALTER COLUMN nome DROP NOT NULL;
ALTER TABLE leads ALTER COLUMN telefone DROP NOT NULL;
ALTER TABLE leads ALTER COLUMN processo_depre DROP NOT NULL;

ALTER TABLE leads ADD COLUMN IF NOT EXISTS origem TEXT;   -- busca_em_formacao | monitorar | antecipacao
ALTER TABLE leads ADD COLUMN IF NOT EXISTS cnj TEXT;

CREATE INDEX IF NOT EXISTS idx_leads_origem ON leads (origem);

-- comunicacoes_agendadas.tipo é TEXT livre → novo tipo 'andamentos_resumo'
-- (sem alteração de schema; o disparo existente envia o payload).

-- =============================================================
-- FIM — FOR-75
-- =============================================================
