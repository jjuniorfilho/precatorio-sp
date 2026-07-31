-- FOR-102 — Corrige RLS de escrita em precatorios_pagamentos.
-- O worker-crawler autentica como `authenticated` (anon key + login admin — "Opção B" de
-- config.ts), não com a service_role key crua. A policy original só previa SELECT pra
-- anon/authenticated; faltava permitir INSERT/UPDATE pro worker gravar. Mesmo padrão já
-- usado em crawler_queue/coleta_config (admin_all_* FOR ALL TO authenticated). Aplicar no
-- SQL Editor. Re-executável.

DROP POLICY IF EXISTS "admin_write_precatorios_pagamentos" ON public.precatorios_pagamentos;
CREATE POLICY "admin_write_precatorios_pagamentos"
  ON public.precatorios_pagamentos FOR ALL TO authenticated USING (true) WITH CHECK (true);
