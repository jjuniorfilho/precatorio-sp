-- FOR-102 — RPC pra marcar precatorios.pagamentos_consultado_em.
-- precatorios só permite escrita via service_role (dado público DEPRE, não deve ser aberto
-- a UPDATE geral pra authenticated). O worker-crawler autentica como authenticated (não
-- service_role cru), então precisa de uma RPC SECURITY DEFINER com essa única
-- responsabilidade (mesmo padrão de claim_crawler_jobs/classify_processo). Aplicar no
-- SQL Editor. Re-executável.

CREATE OR REPLACE FUNCTION public.marcar_pagamentos_consultado(p_processo_depre TEXT)
RETURNS VOID
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE precatorios
     SET pagamentos_consultado_em = NOW()
   WHERE processo_depre = p_processo_depre;
$$;

GRANT EXECUTE ON FUNCTION public.marcar_pagamentos_consultado(TEXT) TO authenticated, service_role;
