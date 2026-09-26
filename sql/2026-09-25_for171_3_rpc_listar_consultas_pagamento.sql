-- FOR-171 (3 de 3) — RPC de leitura do log para o admin (/admin roda anônimo → leitura só via RPC
-- SECURITY DEFINER; padrão admin-anon-rpc). Devolve um jsonb (array) das últimas consultas do
-- processo, mais recente primeiro, só com os campos que a tela precisa (sem id/criado_em; erro
-- truncado). Depende do 1. Re-executável.

CREATE OR REPLACE FUNCTION public.listar_consultas_pagamento(p_processo_depre text, p_limit integer DEFAULT 20)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(t) ORDER BY t.iniciada_em DESC)
      FROM (
        SELECT iniciada_em, finalizada_em, origem, resultado, tentativas, situacao,
               qtd_pagamentos, data_consulta_portal, left(erro, 300) AS erro, etapa_falha, passos
          FROM pagamentos_consultas_log
         WHERE processo_depre = p_processo_depre
         ORDER BY iniciada_em DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50)
      ) t
  ), '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.listar_consultas_pagamento(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.listar_consultas_pagamento(text, integer) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
