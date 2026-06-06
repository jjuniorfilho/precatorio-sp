DROP VIEW IF EXISTS public.precatorios_publico;

CREATE VIEW public.precatorios_publico
WITH (security_invoker = true) AS
SELECT
  id,
  processo_depre,
  autos,
  autos_antigos,
  devedora,
  saldo_depre,
  natureza,
  status,
  suspenso,
  data_protocolo,
  autor,
  advogados,
  ordem_pagamento,
  es_ep,
  ordem_orcamentaria,
  num_protocolo_geral,
  condicao_superpreferencia,
  valor_pago,
  num_ordem,
  dt_ensejo_ordem,
  updated_at
FROM public.precatorios;

GRANT SELECT ON public.precatorios_publico TO anon, authenticated, service_role;