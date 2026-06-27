-- =============================================================
-- FOR-70 — Ingestão DJEN/Comunica + flag SP (parte passiva)
-- Tabelas de controle + seed de config + cron diário.
-- Depende de FOR-73 (coleta_config, enqueue_crawler_job, coleta_runs).
-- Edge function `ingest-djen` (deploy via Lovable/CLI). Re-executável.
-- =============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- Idempotência + monitor por dia processado
CREATE TABLE IF NOT EXISTS djen_dias (
  data          DATE PRIMARY KEY,
  status        TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','parcial','ok','erro')),
  total         INT NOT NULL DEFAULT 0,
  flagueados    INT NOT NULL DEFAULT 0,
  enfileirados  INT NOT NULL DEFAULT 0,
  eproc         INT NOT NULL DEFAULT 0,
  ultima_pagina INT NOT NULL DEFAULT 0,
  erro          TEXT,
  processado_em TIMESTAMPTZ,
  updated_at    TIMESTAMPTZ DEFAULT NOW()
);

-- Processos eproc parqueados (issue futura do crawler eproc)
CREATE TABLE IF NOT EXISTS eproc_pendentes (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cnj                  TEXT NOT NULL UNIQUE,
  numero_processo      TEXT,
  link                 TEXT,
  nome_orgao           TEXT,
  nome_classe          TEXT,
  data_disponibilizacao DATE,
  created_at           TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_eproc_pendentes_data ON eproc_pendentes (data_disponibilizacao);

ALTER TABLE djen_dias      ENABLE ROW LEVEL SECURITY;
ALTER TABLE eproc_pendentes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_all_djen_dias" ON djen_dias;
DROP POLICY IF EXISTS "admin_all_eproc_pendentes" ON eproc_pendentes;
CREATE POLICY "admin_all_djen_dias"      ON djen_dias      FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_eproc_pendentes" ON eproc_pendentes FOR ALL TO authenticated USING (true);

DROP TRIGGER IF EXISTS djen_dias_updated_at ON djen_dias;
CREATE TRIGGER djen_dias_updated_at BEFORE UPDATE ON djen_dias FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Config da rotina caderno_dje: classes relevantes + UF + cron_secret (admin seta o secret)
INSERT INTO coleta_config (rotina, enabled, params) VALUES
  ('caderno_dje', true, jsonb_build_object(
      'uf', 'TJSP',
      'itens_por_pagina', 100,
      'classes_relevantes', jsonb_build_array(
        'Cumprimento de Sentença contra a Fazenda Pública',
        'Cumprimento Provisório de Sentença contra a Fazenda Pública',
        'Execução contra a Fazenda Pública',
        'Precatório',
        'Requisição de Pequeno Valor',
        'Procedimento do Juizado Especial da Fazenda Pública'
      ),
      'cron_secret', ''   -- preencher via UPDATE (NÃO versionar o segredo)
  ))
ON CONFLICT (rotina) DO UPDATE SET params = EXCLUDED.params, updated_at = NOW();

-- -------------------------------------------------------------
-- CRON: caderno-dje-diario → edge function ingest-djen (dia anterior)
-- X-Cron-Secret lido do coleta_config (admin seta; não fica no git).
-- Ativa quando a edge function estiver deployada.
-- -------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('caderno-dje-diario');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('caderno-dje-diario', '0 5 * * *', $CRON$
  SELECT net.http_post(
    url := 'https://nxkvfcrnocdxysqsuozj.supabase.co/functions/v1/ingest-djen',
    headers := jsonb_build_object(
      'Content-Type','application/json',
      'X-Cron-Secret', COALESCE((SELECT params->>'cron_secret' FROM coleta_config WHERE rotina='caderno_dje'), '')
    ),
    body := jsonb_build_object('source','cron')  -- date default = ontem
  );
$CRON$);

-- =============================================================
-- FIM — FOR-70. Edge function em supabase/functions/ingest-djen.
-- eproc fica parqueado em eproc_pendentes (issue futura).
-- =============================================================
