-- FOR-171 (2 de 3) — RPC de escrita do log (chamada pelo worker-crawler).
-- SECURITY DEFINER com search_path fixo: a tabela não tem policy nem GRANT. Grava a consulta e poda
-- para as 20 mais recentes do processo (por criado_em do servidor — não confia em data do cliente).
-- Entradas limitadas (tempo <= now(), textos truncados, passos <= 20 KB). Nota: o worker autentica como
-- `authenticated`, então a RPC precisa desse GRANT; o log é auxiliar/diagnóstico, não dado de negócio.
-- Depende do 1. Re-executável.

CREATE OR REPLACE FUNCTION public.registrar_consulta_pagamento(
  p_processo_depre       text,
  p_iniciada_em          timestamptz,
  p_finalizada_em        timestamptz,
  p_origem               text,
  p_resultado            text,
  p_tentativas           integer,
  p_situacao             text,
  p_qtd_pagamentos       integer,
  p_data_consulta_portal text,
  p_erro                 text,
  p_etapa_falha          text,
  p_passos               jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_processo_depre IS NULL OR p_processo_depre !~ '\.8\.26\.0500$' THEN
    RAISE EXCEPTION 'processo_depre inválido (esperado terminar em .8.26.0500)';
  END IF;

  INSERT INTO pagamentos_consultas_log (
    processo_depre, iniciada_em, finalizada_em, origem, resultado, tentativas, situacao,
    qtd_pagamentos, data_consulta_portal, erro, etapa_falha, passos
  ) VALUES (
    p_processo_depre, LEAST(p_iniciada_em, now()), LEAST(p_finalizada_em, now()), p_origem, p_resultado, LEAST(GREATEST(COALESCE(p_tentativas, 0), 0), 100), left(p_situacao, 200),
    p_qtd_pagamentos, left(p_data_consulta_portal, 40), left(p_erro, 1000), left(p_etapa_falha, 40),
    CASE WHEN p_passos IS NOT NULL AND jsonb_typeof(p_passos) = 'array' AND octet_length(p_passos::text) <= 20000 THEN p_passos ELSE '[]'::jsonb END
  );

  -- Retenção: mantém só as 20 consultas mais recentes do processo.
  DELETE FROM pagamentos_consultas_log
   WHERE processo_depre = p_processo_depre
     AND id NOT IN (
       SELECT id FROM pagamentos_consultas_log
        WHERE processo_depre = p_processo_depre
        ORDER BY criado_em DESC
        LIMIT 20
     );
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_consulta_pagamento(text, timestamptz, timestamptz, text, text, integer, text, integer, text, text, text, jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_consulta_pagamento(text, timestamptz, timestamptz, text, text, integer, text, integer, text, text, text, jsonb) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
