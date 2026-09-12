-- =============================================================
-- FOR-145 — Schema pra suportar precatórios federais (TRF1-6)
-- Módulo Precatório Federal. Depende do schema base do FOR-68/69/70/73
-- já aplicado (processos/cumprimentos/incidentes, djen_dias, coleta_config).
-- Rodar no SQL Editor (padrão Lovable/Supabase). Re-executável.
--
-- Não mexe em dados/linhas do fluxo estadual (TJSP) — só adiciona
-- colunas com DEFAULT retrocompatível e amplia CHECKs existentes.
-- =============================================================

-- -------------------------------------------------------------
-- processos / cumprimentos: tribunal + sistema de origem
-- (denormalizado em cumprimentos, mesmo padrão de conveniência já
-- usado em incidentes.processo_id — evita join só pra filtrar)
-- -------------------------------------------------------------
ALTER TABLE processos    ADD COLUMN IF NOT EXISTS tribunal TEXT;
ALTER TABLE cumprimentos ADD COLUMN IF NOT EXISTS tribunal TEXT;

ALTER TABLE processos    ADD COLUMN IF NOT EXISTS sistema TEXT;
ALTER TABLE cumprimentos ADD COLUMN IF NOT EXISTS sistema TEXT;

ALTER TABLE processos    DROP CONSTRAINT IF EXISTS processos_sistema_check;
ALTER TABLE processos    ADD  CONSTRAINT processos_sistema_check    CHECK (sistema IS NULL OR sistema IN ('pje','eproc','outro'));
ALTER TABLE cumprimentos DROP CONSTRAINT IF EXISTS cumprimentos_sistema_check;
ALTER TABLE cumprimentos ADD  CONSTRAINT cumprimentos_sistema_check CHECK (sistema IS NULL OR sistema IN ('pje','eproc','outro'));

CREATE INDEX IF NOT EXISTS idx_processos_tribunal    ON processos (tribunal);
CREATE INDEX IF NOT EXISTS idx_cumprimentos_tribunal ON cumprimentos (tribunal);

-- ente_esfera hoje só cobre Estadual/Municipal/Outro (devedor de SP) —
-- precatório federal tem devedor federal (União/INSS/CEF etc.), então
-- ganha valor próprio em vez de cair em "Outro" (perderia informação).
ALTER TABLE processos DROP CONSTRAINT IF EXISTS processos_ente_esfera_check;
ALTER TABLE processos ADD  CONSTRAINT processos_ente_esfera_check
  CHECK (ente_esfera IN ('Estadual','Municipal','Outro','Federal'));

-- -------------------------------------------------------------
-- djen_dias: hoje 1 linha/dia (implícito TJSP). Precisa suportar
-- 6 tribunais federais em paralelo, cada um com seu próprio status
-- por dia — troca a PK de (data) pra (data, tribunal).
-- DEFAULT 'TJSP' preserva as linhas já existentes sem precisar de
-- backfill manual (ficam implicitamente TJSP, como sempre foram).
-- -------------------------------------------------------------
ALTER TABLE djen_dias ADD COLUMN IF NOT EXISTS tribunal TEXT NOT NULL DEFAULT 'TJSP';

ALTER TABLE djen_dias DROP CONSTRAINT IF EXISTS djen_dias_pkey;
ALTER TABLE djen_dias ADD  CONSTRAINT djen_dias_pkey PRIMARY KEY (data, tribunal);

-- -------------------------------------------------------------
-- coleta_config: amplia o CHECK de `rotina` pra aceitar uma linha
-- por TRF (liga/desliga independente — rollout faseado PJe→eproc).
-- -------------------------------------------------------------
ALTER TABLE coleta_config DROP CONSTRAINT IF EXISTS coleta_config_rotina_check;
ALTER TABLE coleta_config ADD  CONSTRAINT coleta_config_rotina_check
  CHECK (rotina IN (
    'caderno_dje','crawler_esaj','backfill','refresh',
    'caderno_djen_trf1','caderno_djen_trf2','caderno_djen_trf3',
    'caderno_djen_trf4','caderno_djen_trf5','caderno_djen_trf6'
  ));

-- Seed das 6 rotinas federais. `enabled=false` em todas — liga-se
-- manualmente por tribunal conforme o rollout faseado avança
-- (Fase A: TRF1/TRF3/TRF5 primeiro; Fase B: TRF2/TRF4/TRF6 depois).
-- `classes_relevantes` replica a lista já validada em produção pro
-- `caderno_dje` estadual (nomenclatura padronizada nacionalmente
-- pelo CNJ — ver docs/business-context/brainstorm/
-- precatorio-federal-classificacao-djen-2026-09-05.md).
INSERT INTO coleta_config (rotina, enabled, params)
SELECT
  'caderno_djen_trf' || trf,
  false,
  jsonb_build_object(
    'tribunal', 'TRF' || trf,
    'itens_por_pagina', 100,
    'classes_relevantes', jsonb_build_array(
      'Cumprimento de Sentença contra a Fazenda Pública',
      'Cumprimento Provisório de Sentença contra a Fazenda Pública',
      'Execução contra a Fazenda Pública',
      'Precatório',
      'Requisição de Pequeno Valor',
      'Procedimento do Juizado Especial da Fazenda Pública'
    )
  )
FROM generate_series(1, 6) AS trf
ON CONFLICT (rotina) DO NOTHING;

-- =============================================================
-- FIM — FOR-145
-- Próximo passo (Fase 2 do plan.md): worker-crawler/src/ingest-djen-federal.ts
-- lê `coleta_config` (rotina caderno_djen_trfN) pra saber classes_relevantes
-- e se está habilitado, e grava em djen_dias(data, tribunal).
-- =============================================================
