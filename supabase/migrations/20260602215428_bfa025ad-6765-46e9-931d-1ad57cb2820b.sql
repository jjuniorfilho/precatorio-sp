-- 1) Drop permissive anon SELECT policy on base table that exposed CPF/CNPJ
DROP POLICY IF EXISTS anon_read_precatorios_safe ON public.precatorios;

-- 2) Switch the public view to run with definer privileges so anon reads
--    only the safe columns (no cpf_titular / cnpj_titular) without granting
--    direct access to the base table.
ALTER VIEW public.precatorios_publico SET (security_invoker = false);

-- 3) Ensure read access to the safe view
GRANT SELECT ON public.precatorios_publico TO anon, authenticated;