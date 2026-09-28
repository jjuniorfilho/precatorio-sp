-- FOR-173 (4 de 4) — RPCs de progresso da consulta de valor pago.
--
--   registrar_progresso_consulta_pagamento(...)  ESCRITA — chamada pelo worker-crawler.
--   obter_progresso_consulta_pagamento(text)     LEITURA — chamada pelo frontend (server function,
--                                                service_role). NÃO é concedida a anon/authenticated.
--
-- Ambas SECURITY DEFINER com search_path fixo e plpgsql (language sql + security definer nunca inlina e
-- cega o planner; ver patterns/security-definer-bloqueia-inlining). Depende do SQL 3. Re-executável.
--
-- Escrita — contrato (assinatura fixada em plan.md):
--   * p_nova = true  → nova consulta: renova `iniciada_em` (o front usa a mudança de iniciada_em para
--     saber que a linha é da consulta que ele acabou de disparar, sem depender de relógio do cliente).
--   * estado inválido → exceção; etapa fora da lista → 'desconhecida'; resultado/origem inválidos → NULL;
--     textos truncados; contadores limitados. Nunca guarda mensagem crua de erro do banco.
--   * Limpeza preguiçosa: a cada escrita apaga linhas concluida|falha com atualizado_em > 7 dias.
-- Nota: o worker autentica como `authenticated` quando não usa service_role (mesmo motivo do FOR-171),
-- por isso a escrita é concedida a authenticated + service_role. Não há PII na tabela.

CREATE OR REPLACE FUNCTION public.registrar_progresso_consulta_pagamento(
  p_processo_depre  text,
  p_estado          text,
  p_etapa           text,
  p_tentativa       integer,
  p_max_tentativas  integer,
  p_detalhe         text,
  p_resultado       text,
  p_etapa_falha     text,
  p_origem          text,
  p_nova            boolean DEFAULT false
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_etapa      text;
  v_resultado  text;
  v_origem     text;
  v_tentativa  integer;
  v_max        integer;
BEGIN
  IF p_processo_depre IS NULL OR p_processo_depre !~ '\.8\.26\.0500$' THEN
    RAISE EXCEPTION 'processo_depre inválido (esperado terminar em .8.26.0500)';
  END IF;
  IF p_estado IS NULL OR p_estado NOT IN ('na_fila', 'em_andamento', 'concluida', 'falha') THEN
    RAISE EXCEPTION 'estado inválido';
  END IF;

  v_etapa := CASE
    WHEN p_etapa IN ('na_fila', 'iniciando', 'abrir_portal', 'obter_link', 'abrir_pesquisa', 'busca',
                     'resultado_carregou', 'ler_resultado', 'extrair_pagamentos', 'persistir')
      THEN p_etapa
    ELSE 'desconhecida'
  END;
  v_resultado := CASE WHEN p_resultado IN ('encontrado', 'nao_consta', 'falha') THEN p_resultado ELSE NULL END;
  v_origem    := CASE WHEN p_origem IN ('manual', 'busca_publica', 'crawler') THEN p_origem ELSE NULL END;
  v_tentativa := LEAST(GREATEST(COALESCE(p_tentativa, 0), 0), 100);
  v_max       := LEAST(GREATEST(COALESCE(p_max_tentativas, 4), 1), 100);

  INSERT INTO pagamentos_consultas_progresso AS t (
    processo_depre, estado, etapa, tentativa, max_tentativas, detalhe, resultado, etapa_falha, origem,
    iniciada_em, atualizado_em
  ) VALUES (
    p_processo_depre, p_estado, v_etapa, v_tentativa, v_max, left(p_detalhe, 200), v_resultado,
    left(p_etapa_falha, 40), v_origem, now(), now()
  )
  ON CONFLICT (processo_depre) DO UPDATE SET
    estado         = EXCLUDED.estado,
    etapa          = EXCLUDED.etapa,
    tentativa      = EXCLUDED.tentativa,
    max_tentativas = EXCLUDED.max_tentativas,
    detalhe        = EXCLUDED.detalhe,
    resultado      = EXCLUDED.resultado,
    etapa_falha    = EXCLUDED.etapa_falha,
    origem         = COALESCE(EXCLUDED.origem, t.origem),
    iniciada_em    = CASE WHEN COALESCE(p_nova, false) THEN now() ELSE t.iniciada_em END,
    atualizado_em  = now();

  -- Limpeza preguiçosa: consultas terminadas há mais de 7 dias.
  DELETE FROM pagamentos_consultas_progresso
   WHERE estado IN ('concluida', 'falha')
     AND atualizado_em < now() - interval '7 days';
END;
$$;

REVOKE ALL ON FUNCTION public.registrar_progresso_consulta_pagamento(text, text, text, integer, integer, text, text, text, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.registrar_progresso_consulta_pagamento(text, text, text, integer, integer, text, text, text, text, boolean) TO authenticated, service_role;

-- Leitura: devolve o progresso atual do DEPRE (jsonb) ou NULL se não há linha.
CREATE OR REPLACE FUNCTION public.obter_progresso_consulta_pagamento(p_processo_depre text)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN (
    SELECT to_jsonb(t)
      FROM (
        SELECT estado, etapa, tentativa, max_tentativas, detalhe, resultado, etapa_falha, origem,
               iniciada_em, atualizado_em
          FROM pagamentos_consultas_progresso
         WHERE processo_depre = p_processo_depre
      ) t
  );
END;
$$;

REVOKE ALL ON FUNCTION public.obter_progresso_consulta_pagamento(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.obter_progresso_consulta_pagamento(text) TO service_role;

NOTIFY pgrst, 'reload schema';
