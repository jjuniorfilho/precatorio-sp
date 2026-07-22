-- FOR-102 — Pagamentos individuais do precatório (portal TJSP "Pagamentos Prioridades").
-- Pagamento não é um valor único: um mesmo processo_depre (.0500) pode ter várias linhas
-- de pagamento (data, valor, tipo). Vincula só por processo_depre (funciona tanto pro
-- schema legado `precatorios` quanto pro schema novo via `incidentes.numero_depre`).
-- Aplicar no SQL Editor. Re-executável.

CREATE TABLE IF NOT EXISTS public.precatorios_pagamentos (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_depre  TEXT NOT NULL,
  data_pagamento  DATE,
  valor           BIGINT NOT NULL,   -- centavos
  tipo            TEXT,              -- ex.: "Preferência"
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_precatorios_pagamentos_processo_depre
  ON public.precatorios_pagamentos (processo_depre);

-- Evita duplicar o mesmo pagamento em re-consultas (idempotência do crawler).
CREATE UNIQUE INDEX IF NOT EXISTS uq_precatorios_pagamentos_registro
  ON public.precatorios_pagamentos (processo_depre, data_pagamento, valor, COALESCE(tipo, ''));

ALTER TABLE public.precatorios_pagamentos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "public_read_precatorios_pagamentos" ON public.precatorios_pagamentos;
CREATE POLICY "public_read_precatorios_pagamentos"
  ON public.precatorios_pagamentos FOR SELECT TO anon, authenticated USING (true);
-- Escrita só via service_role (crawler) — sem policy de INSERT/UPDATE pra anon/authenticated.

-- Campo de controle: registra que a consulta foi feita mesmo sem pagamentos encontrados
-- (ausência de pagamento é resultado válido, não erro — diferencia "nunca consultado"
-- de "consultado e sem pagamentos").
ALTER TABLE public.precatorios ADD COLUMN IF NOT EXISTS pagamentos_consultado_em TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_precatorios_pagamentos_consultado_em
  ON public.precatorios (pagamentos_consultado_em);
