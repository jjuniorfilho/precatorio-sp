-- FOR-198 (2 de 2) — mesma categorização, aplicada a pagamentos_consultas_log (2º painel do
-- protótipo da issue, "Consultas ao TJSP"). A decisão de arquitetura #3 da issue cita
-- literalmente só crawler_queue; esta migration é a extensão MECÂNICA do mesmo padrão (coluna
-- nullable + parâmetro novo com DEFAULT NULL em RPC já existente, nenhuma estrutura nova) à
-- 2ª tabela que a própria issue já lista (pagamentos-tjsp.ts) e que o protótipo já mostra como
-- painel — não é uma decisão de arquitetura nova. Reportada explicitamente no PR/handback;
-- fácil de reverter isoladamente (é um arquivo de migration à parte) se o humano preferir não
-- aplicá-la agora.
--
-- Mesmo racional de nullable (não 'outro' como default) e TEXT+CHECK do arquivo 1/2 — ver
-- comentário lá. DROP FUNCTION + CREATE pelo mesmo motivo (assinatura muda de 12 p/ 13 params).
--
-- Valide em sandbox local ANTES de aplicar (sql/sandbox/for198_validate_local.sh).
-- Aplicar DEPOIS do arquivo 1/2 (independentes entre si, mas mantém a numeração). Re-executável.

ALTER TABLE public.pagamentos_consultas_log ADD COLUMN IF NOT EXISTS erro_categoria text;

ALTER TABLE public.pagamentos_consultas_log DROP CONSTRAINT IF EXISTS pagamentos_consultas_log_erro_categoria_check;
ALTER TABLE public.pagamentos_consultas_log ADD CONSTRAINT pagamentos_consultas_log_erro_categoria_check
  CHECK (erro_categoria IN (
    'captcha', 'timeout', 'rate_limit', 'site_indisponivel',
    'bloqueio_suspeito', 'cnj_nao_encontrado', 'outro'
  ));

DROP FUNCTION IF EXISTS public.registrar_consulta_pagamento(
  text, timestamptz, timestamptz, text, text, integer, text, integer, text, text, text, jsonb
);

CREATE FUNCTION public.registrar_consulta_pagamento(
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
  p_passos               jsonb,
  p_categoria            text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_processo_depre IS NULL OR p_processo_depre !~ '\.8\.26\.0500$' THEN
    RAISE EXCEPTION 'processo_depre inválido (esperado terminar em .8.26.0500)';
  END IF;

  INSERT INTO pagamentos_consultas_log (
    processo_depre, iniciada_em, finalizada_em, origem, resultado, tentativas, situacao,
    qtd_pagamentos, data_consulta_portal, erro, etapa_falha, passos, erro_categoria
  ) VALUES (
    p_processo_depre, LEAST(p_iniciada_em, now()), LEAST(p_finalizada_em, now()), p_origem, p_resultado, LEAST(GREATEST(COALESCE(p_tentativas, 0), 0), 100), left(p_situacao, 200),
    p_qtd_pagamentos, left(p_data_consulta_portal, 40), left(p_erro, 1000), left(p_etapa_falha, 40),
    CASE WHEN p_passos IS NOT NULL AND jsonb_typeof(p_passos) = 'array' AND octet_length(p_passos::text) <= 20000 THEN p_passos ELSE '[]'::jsonb END,
    p_categoria
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

REVOKE ALL ON FUNCTION public.registrar_consulta_pagamento(text, timestamptz, timestamptz, text, text, integer, text, integer, text, text, text, jsonb, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_consulta_pagamento(text, timestamptz, timestamptz, text, text, integer, text, integer, text, text, text, jsonb, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
