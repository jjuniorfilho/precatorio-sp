-- 1. Remover policies abertas em precatorios
DROP POLICY IF EXISTS public_read_precatorios ON public.precatorios;
DROP POLICY IF EXISTS temp_import_precatorios ON public.precatorios;
DROP POLICY IF EXISTS temp_update_precatorios ON public.precatorios;

-- Garantir que anon não tenha mais nenhum acesso direto à tabela
REVOKE ALL ON public.precatorios FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.precatorios TO authenticated;
GRANT ALL ON public.precatorios TO service_role;

-- Permitir leitura pelo admin (mesmo padrão das outras tabelas)
CREATE POLICY admin_all_precatorios ON public.precatorios
  FOR ALL TO authenticated
  USING (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin')
  WITH CHECK (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin');

-- 2. Recriar view pública sem CPF/CNPJ e com security_invoker
DROP VIEW IF EXISTS public.precatorios_publico;

CREATE VIEW public.precatorios_publico
WITH (security_invoker = true) AS
SELECT
  id,
  processo_depre,
  autos,
  devedora,
  saldo_depre,
  natureza,
  status,
  suspenso,
  data_protocolo,
  advogados,
  autor,
  ordem_pagamento,
  es_ep,
  ordem_orcamentaria,
  num_protocolo_geral,
  autos_antigos,
  condicao_superpreferencia,
  valor_pago,
  num_ordem,
  dt_ensejo_ordem,
  updated_at
FROM public.precatorios;

-- A view precisa de acesso público de leitura para a consulta gratuita do site funcionar.
-- Como ela NÃO expõe CPF/CNPJ, isso é seguro.
GRANT SELECT ON public.precatorios_publico TO anon, authenticated;

-- Mas para o anon ler a view, ele precisa de SELECT na tabela base
-- (security_invoker = a view roda com perms do caller).
-- Restringimos via GRANT em colunas específicas:
GRANT SELECT (
  id, processo_depre, autos, devedora, saldo_depre, natureza, status, suspenso,
  data_protocolo, advogados, autor, ordem_pagamento, es_ep, ordem_orcamentaria,
  num_protocolo_geral, autos_antigos, condicao_superpreferencia, valor_pago,
  num_ordem, dt_ensejo_ordem, updated_at
) ON public.precatorios TO anon;

-- E recriamos uma policy de SELECT pública (RLS) que NÃO bloqueia,
-- já que a proteção real é o GRANT por coluna acima.
CREATE POLICY anon_read_precatorios_safe ON public.precatorios
  FOR SELECT TO anon
  USING (true);

-- 3. Renomear policy de leads para nome mais explícito (mesma lógica)
DROP POLICY IF EXISTS admin_all_leads ON public.leads;
CREATE POLICY leads_admin_only ON public.leads
  FOR ALL TO authenticated
  USING (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin')
  WITH CHECK (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin');

-- 4. Fixar search_path da função update_updated_at
ALTER FUNCTION public.update_updated_at() SET search_path = public;