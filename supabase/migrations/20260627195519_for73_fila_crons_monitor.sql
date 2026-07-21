-- =============================================================
-- FOR-73 — Crons + fila (crawler_queue) + monitor de coleta
-- Módulo Precatórios SP (FOR-68). Depende do schema da FOR-69
-- (tabela `processos`) já aplicado no banco.
-- Worker externo (VPS) consome a fila via RPC (service_role).
-- Rodar no SQL Editor (padrão Lovable/Supabase). Re-executável.
-- =============================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- função updated_at (idempotente; igual FOR-69/001)
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- -------------------------------------------------------------
-- TABELAS
-- -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS crawler_queue (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','processando','ok','erro')),
  origem          TEXT CHECK (origem IN ('dje_diario','backfill','refresh','manual')),
  scheduled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  claimed_at      TIMESTAMPTZ,
  tentativas      INT NOT NULL DEFAULT 0,
  erro            TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
-- impede job duplicado EM ABERTO p/ o mesmo processo
CREATE UNIQUE INDEX IF NOT EXISTS uq_crawler_queue_aberto
  ON crawler_queue (processo_codigo) WHERE status IN ('pendente','processando');
CREATE INDEX IF NOT EXISTS idx_crawler_queue_claim ON crawler_queue (status, scheduled_at);

CREATE TABLE IF NOT EXISTS coleta_config (
  rotina     TEXT PRIMARY KEY CHECK (rotina IN ('caderno_dje','crawler_esaj','backfill','refresh')),
  enabled    BOOLEAN NOT NULL DEFAULT true,
  params     JSONB NOT NULL DEFAULT '{}',   -- chunk_size, ttl por fase, backoff
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS coleta_runs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rotina      TEXT NOT NULL,
  started_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  finished_at TIMESTAMPTZ,
  status      TEXT NOT NULL DEFAULT 'running' CHECK (status IN ('running','sucesso','erro','erro_parcial')),
  itens_ok    INT NOT NULL DEFAULT 0,
  itens_erro  INT NOT NULL DEFAULT 0,
  duracao_ms  INT,
  detalhe     JSONB,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_coleta_runs_rotina ON coleta_runs (rotina, started_at DESC);

-- triggers updated_at
DROP TRIGGER IF EXISTS crawler_queue_updated_at ON crawler_queue;
DROP TRIGGER IF EXISTS coleta_config_updated_at ON coleta_config;
CREATE TRIGGER crawler_queue_updated_at BEFORE UPDATE ON crawler_queue FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER coleta_config_updated_at BEFORE UPDATE ON coleta_config FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- -------------------------------------------------------------
-- RLS — admin-only (authenticated). Worker usa service_role (bypassa RLS).
-- -------------------------------------------------------------
ALTER TABLE crawler_queue ENABLE ROW LEVEL SECURITY;
ALTER TABLE coleta_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE coleta_runs   ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "admin_all_crawler_queue" ON crawler_queue;
DROP POLICY IF EXISTS "admin_all_coleta_config" ON coleta_config;
DROP POLICY IF EXISTS "admin_all_coleta_runs"   ON coleta_runs;
CREATE POLICY "admin_all_crawler_queue" ON crawler_queue FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_coleta_config" ON coleta_config FOR ALL TO authenticated USING (true);
CREATE POLICY "admin_all_coleta_runs"   ON coleta_runs   FOR ALL TO authenticated USING (true);

-- -------------------------------------------------------------
-- RPCs (SECURITY DEFINER) — worker externo + crons
-- -------------------------------------------------------------

-- claim atômico de lote (sem sobreposição entre workers)
CREATE OR REPLACE FUNCTION claim_crawler_jobs(p_limit INT)
RETURNS SETOF crawler_queue
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE crawler_queue q
     SET status='processando', claimed_at=NOW(), updated_at=NOW()
   WHERE q.id IN (
     SELECT id FROM crawler_queue
      WHERE status='pendente' AND scheduled_at <= NOW()
      ORDER BY scheduled_at
      FOR UPDATE SKIP LOCKED
      LIMIT p_limit
   )
  RETURNING q.*;
$$;

CREATE OR REPLACE FUNCTION complete_crawler_job(p_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE crawler_queue SET status='ok', updated_at=NOW() WHERE id = p_id;
$$;

-- falha com 3 tentativas + backoff (15min, 1h), depois 'erro'
CREATE OR REPLACE FUNCTION fail_crawler_job(p_id UUID, p_erro TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE crawler_queue
     SET tentativas   = tentativas + 1,
         erro         = p_erro,
         updated_at   = NOW(),
         status       = CASE WHEN tentativas + 1 >= 3 THEN 'erro' ELSE 'pendente' END,
         scheduled_at = CASE WHEN tentativas + 1 >= 3 THEN scheduled_at
                             ELSE NOW() + (ARRAY['15 minutes','1 hour'])[tentativas + 1]::interval END
   WHERE id = p_id;
END; $$;

-- enfileira respeitando TTL (next_crawl_at) e unique-em-aberto
CREATE OR REPLACE FUNCTION enqueue_crawler_job(p_processo_codigo TEXT, p_origem TEXT DEFAULT 'manual')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM processos
     WHERE processo_codigo = p_processo_codigo
       AND next_crawl_at IS NOT NULL AND next_crawl_at > NOW()
  ) THEN
    RETURN;  -- ainda fresco
  END IF;
  INSERT INTO crawler_queue (processo_codigo, origem)
  VALUES (p_processo_codigo, p_origem)
  ON CONFLICT DO NOTHING;  -- unique parcial em aberto
END; $$;

-- reprocessar falhas (ação do monitor); evita conflito com job já aberto
CREATE OR REPLACE FUNCTION requeue_failed(p_origem TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  UPDATE crawler_queue cq
     SET status='pendente', scheduled_at=NOW(), erro=NULL, tentativas=0, updated_at=NOW()
   WHERE cq.status='erro'
     AND (p_origem IS NULL OR cq.origem = p_origem)
     AND NOT EXISTS (
       SELECT 1 FROM crawler_queue o
        WHERE o.processo_codigo = cq.processo_codigo AND o.status IN ('pendente','processando')
     );
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END; $$;

-- refresh: enfileira processos SP com TTL vencido (cron SQL puro)
CREATE OR REPLACE FUNCTION enqueue_stale_processos()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_run UUID; n INT := 0;
BEGIN
  IF NOT COALESCE((SELECT enabled FROM coleta_config WHERE rotina='refresh'), true) THEN
    RETURN 0;  -- rotina pausada
  END IF;
  INSERT INTO coleta_runs (rotina, status) VALUES ('refresh','running') RETURNING id INTO v_run;
  WITH stale AS (
    SELECT processo_codigo FROM processos
     WHERE flag_sp AND (next_crawl_at IS NULL OR next_crawl_at <= NOW())
  ), ins AS (
    INSERT INTO crawler_queue (processo_codigo, origem)
    SELECT processo_codigo, 'refresh' FROM stale
    ON CONFLICT DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO n FROM ins;
  UPDATE coleta_runs SET status='sucesso', finished_at=NOW(), itens_ok=n WHERE id=v_run;
  RETURN n;
END; $$;

-- GRANTs de execução
GRANT EXECUTE ON FUNCTION claim_crawler_jobs(INT)            TO service_role;
GRANT EXECUTE ON FUNCTION complete_crawler_job(UUID)         TO service_role;
GRANT EXECUTE ON FUNCTION fail_crawler_job(UUID, TEXT)       TO service_role;
GRANT EXECUTE ON FUNCTION enqueue_crawler_job(TEXT, TEXT)    TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION requeue_failed(TEXT)               TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION enqueue_stale_processos()          TO service_role;

-- -------------------------------------------------------------
-- SEED de configuração das rotinas
-- -------------------------------------------------------------
INSERT INTO coleta_config (rotina, enabled, params) VALUES
  ('caderno_dje',  true,  '{}'),
  ('crawler_esaj', true,  '{"chunk_size":25}'),
  ('backfill',     false, '{}'),
  ('refresh',      true,  '{}')
ON CONFLICT (rotina) DO NOTHING;

-- -------------------------------------------------------------
-- CRON: refresh-stale (SQL puro — sem dependência de edge function)
-- (crons que disparam edge functions — caderno-dje-diario etc. —
--  entram com a FOR-70/71, via pg_net + CRON_SECRET.)
-- -------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('refresh-stale-hourly');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('refresh-stale-hourly', '0 * * * *', $$ SELECT public.enqueue_stale_processos(); $$);

-- =============================================================
-- FIM — FOR-73
-- Aplicar APÓS a migration da FOR-69 (depende da tabela `processos`).
-- Crons de edge (caderno-dje-diario → ingest-djen) ficam para FOR-70/71.
-- =============================================================
