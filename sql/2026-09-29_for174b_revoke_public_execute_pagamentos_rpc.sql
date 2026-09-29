-- FOR-174 (achado ao validar o deploy do fix anterior) — fecha uma fresta de segurança na RPC
-- `upsert_precatorios_pagamentos` (sql/2026-09-29_for174_fix_upsert_pagamentos_rls.sql).
--
-- O Postgres concede EXECUTE a PUBLIC em toda função nova por padrão, a menos que seja
-- explicitamente revogado. A migration anterior fez só `GRANT EXECUTE ... TO authenticated,
-- service_role`, sem `REVOKE ... FROM PUBLIC` antes — confirmado em produção: a chave `anon`
-- (sem autenticação nenhuma) conseguia chamar a função e gravar "pagamentos" (curl com a
-- publishable key devolveu 204). O mesmo padrão (GRANT sem REVOKE FROM PUBLIC antes) já existia
-- em `marcar_pagamentos_consultado` (sql/2026-07-22) — não é regressão desta correção, mas não
-- deve ser copiado adiante.
--
-- Efeito prático de deixar como estava: qualquer visitante anônimo do site (sem precisar de
-- token nem login) poderia inserir registros de pagamento FALSOS pra qualquer processo_depre,
-- poluindo o valor pago mostrado no site público e no admin. A tabela em si só é lida
-- publicamente (policy de SELECT), então isso não vazava dado novo — mas permitia ESCREVER dado
-- falso sem autenticação nenhuma.
--
-- Aplicar no SQL Editor. Re-executável.

REVOKE EXECUTE ON FUNCTION public.upsert_precatorios_pagamentos(TEXT, JSONB) FROM PUBLIC;
-- Reafirma o grant pretendido (idempotente, já existia desde o SQL anterior).
GRANT EXECUTE ON FUNCTION public.upsert_precatorios_pagamentos(TEXT, JSONB) TO authenticated, service_role;
