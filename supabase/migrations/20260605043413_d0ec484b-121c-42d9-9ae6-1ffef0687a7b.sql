ALTER TABLE public.precatorios
  ALTER COLUMN devedora DROP NOT NULL,
  ALTER COLUMN saldo_depre DROP NOT NULL,
  ALTER COLUMN natureza DROP NOT NULL,
  ALTER COLUMN status DROP NOT NULL,
  ALTER COLUMN suspenso DROP NOT NULL;

ALTER TABLE public.precatorios
  ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'planilha_oficial'
    CHECK (origem IN ('planilha_oficial', 'descoberto_tjsp'));

DROP VIEW IF EXISTS public.precatorios_publico;

CREATE VIEW public.precatorios_publico AS
SELECT id, processo_depre, autos, autos_antigos, devedora, saldo_depre, natureza,
       status, suspenso, data_protocolo, autor, advogados, ordem_pagamento, es_ep,
       ordem_orcamentaria, num_protocolo_geral, condicao_superpreferencia,
       valor_pago, num_ordem, dt_ensejo_ordem, origem, updated_at
FROM public.precatorios;

GRANT SELECT ON public.precatorios_publico TO anon, authenticated;