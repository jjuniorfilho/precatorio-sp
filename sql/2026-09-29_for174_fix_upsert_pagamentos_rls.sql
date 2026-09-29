-- FOR-174 (achado em produção) — corrige a persistência de pagamentos do TJSP, que falha
-- SEMPRE que o scraper acha pagamentos de verdade (não "não consta").
--
-- Causa raiz: `upsertPagamentos` (worker-crawler/src/supabase.ts) faz um
-- `.from("precatorios_pagamentos").upsert(...)` DIRETO na tabela. O worker desta VPS não roda
-- com SUPABASE_SERVICE_ROLE_KEY — autentica como `authenticated` via login admin ("Opção B",
-- já prevista no próprio supabase.ts). A tabela `precatorios_pagamentos`
-- (sql/2026-07-21_pagamentos_tjsp.sql) foi criada com a política "escrita só via service_role —
-- sem policy de INSERT/UPDATE pra anon/authenticated": NUNCA existiu uma policy permitindo esse
-- INSERT. `marcar_pagamentos_consultado` (sql/2026-07-22) já tinha sido corrigido com o mesmo
-- problema (virou RPC SECURITY DEFINER) — só o upsert dos pagamentos em si ficou de fora.
--
-- Evidência real (log do worker em produção, 2026-09-29T02:21:01Z):
--   [pagamentos] persistência falhou (0253361-73.2018.8.26.0500):
--   Error: upsert precatorios_pagamentos: new row violates row-level security policy
--   for table "precatorios_pagamentos"
-- 17 pagamentos extraídos do portal, perdidos. A falha ocorre ANTES de `marcarPagamentosConsultado`
-- (mesma função, mesmo try/catch) — não há corrupção de dado (nada fica marcado como "consultado"
-- por engano), mas o registro do pagamento em si nunca persiste desde que essa RLS foi criada.
--
-- Fix: RPC SECURITY DEFINER, mesmo padrão de `marcar_pagamentos_consultado` — não abre uma
-- policy geral de INSERT pra `authenticated` (blast radius maior: qualquer usuário autenticado
-- do projeto passaria a poder inserir "pagamentos" arbitrários), só concede EXECUTE nesta
-- função pontual, que só aceita processo_depre+pagamentos (sem controle de outros campos).
--
-- Aplicar no SQL Editor. Re-executável.

CREATE OR REPLACE FUNCTION public.upsert_precatorios_pagamentos(
  p_processo_depre TEXT,
  p_pagamentos JSONB -- array de {"data": "YYYY-MM-DD"|null, "valor": <centavos>, "tipo": texto|null}
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO precatorios_pagamentos (processo_depre, data_pagamento, valor, tipo)
  SELECT
    p_processo_depre,
    (item->>'data')::date,
    (item->>'valor')::bigint,
    COALESCE(item->>'tipo', '')
  FROM jsonb_array_elements(p_pagamentos) AS item
  -- data_pagamento é NOT NULL na tabela (mesmo filtro que o worker já fazia em memória).
  WHERE item->>'data' IS NOT NULL
  ON CONFLICT (processo_depre, data_pagamento, valor, tipo) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_precatorios_pagamentos(TEXT, JSONB) TO authenticated, service_role;
