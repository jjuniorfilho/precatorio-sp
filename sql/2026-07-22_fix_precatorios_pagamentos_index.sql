-- FOR-102 — Corrige o índice único de precatorios_pagamentos.
-- A v1 (2026-07-21_pagamentos_tjsp.sql) criou o índice sobre COALESCE(tipo, '') — uma
-- expressão. O Supabase (.upsert com onConflict) só aceita nomes de coluna simples no
-- ON CONFLICT, então nunca batia com esse índice ("no unique or exclusion constraint
-- matching the ON CONFLICT specification"). Corrige tornando tipo/data_pagamento NOT NULL
-- (o parser do crawler nunca gera pagamento sem data; tipo vira '' em vez de NULL) e troca
-- por um índice único simples, direto nas colunas. Aplicar no SQL Editor. Re-executável.

ALTER TABLE public.precatorios_pagamentos ALTER COLUMN data_pagamento SET NOT NULL;
ALTER TABLE public.precatorios_pagamentos ALTER COLUMN tipo SET DEFAULT '';
UPDATE public.precatorios_pagamentos SET tipo = '' WHERE tipo IS NULL;
ALTER TABLE public.precatorios_pagamentos ALTER COLUMN tipo SET NOT NULL;

DROP INDEX IF EXISTS public.uq_precatorios_pagamentos_registro;
CREATE UNIQUE INDEX IF NOT EXISTS uq_precatorios_pagamentos_registro
  ON public.precatorios_pagamentos (processo_depre, data_pagamento, valor, tipo);
