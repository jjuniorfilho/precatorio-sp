-- FOR-173 (5) — VERIFICAÇÃO read-only de que os SQLs 1 a 4 estão aplicados COMO ESTÃO NO REPO.
--
-- Não altera nada (só SELECT em catálogos e uma chamada de leitura). Rode no SQL Editor do projeto Supabase
-- do worker (nxkvfc…) DEPOIS de aplicar 1, 2, 3 e 4 (re-execute 1 e 4 se você os aplicou antes da revisão
-- pré-PR: ambos são re-executáveis). Cada linha traz `esperado`, `atual` e `ok`; TUDO deve vir ok = true.
-- Cole o resultado completo (ou só as linhas com ok = false).

WITH
leads_col AS (
  SELECT column_name::text AS nome, is_nullable
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'leads'
),
checks AS (
  SELECT 'leads'::text AS secao, 'email aceita NULL'::text AS item, 'YES'::text AS esperado,
         coalesce((SELECT is_nullable FROM leads_col WHERE nome = 'email'), 'AUSENTE') AS atual
  UNION ALL SELECT 'leads', 'relacao aceita NULL', 'YES',
         coalesce((SELECT is_nullable FROM leads_col WHERE nome = 'relacao'), 'AUSENTE')
  UNION ALL SELECT 'leads', 'coluna criado_por existe', 'sim',
         CASE WHEN EXISTS (SELECT 1 FROM leads_col WHERE nome = 'criado_por') THEN 'sim' ELSE 'NAO' END
  UNION ALL SELECT 'leads', 'coluna documento existe', 'sim',
         CASE WHEN EXISTS (SELECT 1 FROM leads_col WHERE nome = 'documento') THEN 'sim' ELSE 'NAO' END
  UNION ALL SELECT 'leads', 'nome/telefone continuam nullable', 'YES/YES',
         coalesce((SELECT is_nullable FROM leads_col WHERE nome = 'nome'), '?') || '/' ||
         coalesce((SELECT is_nullable FROM leads_col WHERE nome = 'telefone'), '?')
  UNION ALL SELECT 'leads', 'CHECK leads_documento_check', 'presente',
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.leads'::regclass AND conname = 'leads_documento_check') THEN 'presente' ELSE 'AUSENTE' END
  UNION ALL SELECT 'leads', 'CHECK leads_avulso_sem_consent_check', 'presente',
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.leads'::regclass AND conname = 'leads_avulso_sem_consent_check') THEN 'presente' ELSE 'AUSENTE' END
  UNION ALL SELECT 'leads', 'CHECK leads_avulso_um_depre_check', 'presente',
         CASE WHEN EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.leads'::regclass AND conname = 'leads_avulso_um_depre_check') THEN 'presente' ELSE 'AUSENTE' END
  UNION ALL SELECT 'leads', 'índice único parcial uq_leads_avulso_processo_depre', 'presente',
         CASE WHEN EXISTS (SELECT 1 FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'leads' AND indexname = 'uq_leads_avulso_processo_depre') THEN 'presente' ELSE 'AUSENTE' END
  UNION ALL SELECT 'leads', 'policy anon_insert_leads bloqueia avulso/criado_por/documento', 'sim',
         CASE WHEN EXISTS (
           SELECT 1 FROM pg_policies
            WHERE schemaname = 'public' AND tablename = 'leads' AND policyname = 'anon_insert_leads'
              AND with_check LIKE '%avulso%' AND with_check LIKE '%criado_por%' AND with_check LIKE '%documento%'
         ) THEN 'sim' ELSE 'NAO (rode o SQL 1 atualizado)' END
  UNION ALL SELECT 'leads', 'policy leads_admin_only continua presente', 'sim',
         CASE WHEN EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'leads' AND policyname = 'leads_admin_only') THEN 'sim' ELSE 'NAO' END
  UNION ALL SELECT 'leads', 'origem continua sem CHECK de valores', 'sem CHECK',
         CASE WHEN EXISTS (
           SELECT 1 FROM pg_constraint WHERE conrelid = 'public.leads'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) ~* '^CHECK \(\(?origem (= ANY|IN)'
         ) THEN 'TEM CHECK' ELSE 'sem CHECK' END

  -- view leads_processos
  UNION ALL SELECT 'view', 'leads_processos: última coluna é origem', 'origem',
         coalesce((SELECT column_name::text FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'leads_processos'
                    ORDER BY ordinal_position DESC LIMIT 1), 'AUSENTE')
  UNION ALL SELECT 'view', 'leads_processos: 33 colunas', '33',
         (SELECT count(*)::text FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'leads_processos')
  UNION ALL SELECT 'view', 'leads_processos: security_invoker=true', 'true',
         coalesce((SELECT CASE WHEN 'security_invoker=true' = ANY (c.reloptions) THEN 'true' ELSE 'false' END
                     FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE n.nspname = 'public' AND c.relname = 'leads_processos'), 'AUSENTE')
  UNION ALL SELECT 'view', 'leads_processos: anon NÃO lê (PII)', 'false',
         coalesce(has_table_privilege('anon', 'public.leads_processos', 'SELECT')::text, 'AUSENTE')
  UNION ALL SELECT 'view', 'leads_processos: authenticated NÃO lê (PII)', 'false',
         coalesce(has_table_privilege('authenticated', 'public.leads_processos', 'SELECT')::text, 'AUSENTE')
  UNION ALL SELECT 'view', 'leads_processos: service_role lê', 'true',
         coalesce(has_table_privilege('service_role', 'public.leads_processos', 'SELECT')::text, 'AUSENTE')

  -- tabela de progresso
  UNION ALL SELECT 'progresso', 'tabela existe', 'sim',
         CASE WHEN to_regclass('public.pagamentos_consultas_progresso') IS NOT NULL THEN 'sim' ELSE 'NAO' END
  UNION ALL SELECT 'progresso', 'RLS ligado', 'true',
         coalesce((SELECT relrowsecurity::text FROM pg_class WHERE oid = to_regclass('public.pagamentos_consultas_progresso')), 'AUSENTE')
  UNION ALL SELECT 'progresso', 'anon NÃO lê nem escreve a tabela', 'false',
         coalesce((has_table_privilege('anon', 'public.pagamentos_consultas_progresso', 'SELECT')
                   OR has_table_privilege('anon', 'public.pagamentos_consultas_progresso', 'INSERT'))::text, 'AUSENTE')
  UNION ALL SELECT 'progresso', 'authenticated NÃO lê nem escreve a tabela', 'false',
         coalesce((has_table_privilege('authenticated', 'public.pagamentos_consultas_progresso', 'SELECT')
                   OR has_table_privilege('authenticated', 'public.pagamentos_consultas_progresso', 'INSERT'))::text, 'AUSENTE')

  -- RPC de escrita
  UNION ALL SELECT 'rpc escrita', 'existe com a assinatura do contrato', 'sim',
         CASE WHEN to_regprocedure('public.registrar_progresso_consulta_pagamento(text,text,text,integer,integer,text,text,text,text,boolean)') IS NOT NULL THEN 'sim' ELSE 'NAO' END
  UNION ALL SELECT 'rpc escrita', 'SECURITY DEFINER', 'true',
         coalesce((SELECT prosecdef::text FROM pg_proc WHERE oid = to_regprocedure('public.registrar_progresso_consulta_pagamento(text,text,text,integer,integer,text,text,text,text,boolean)')), 'AUSENTE')
  UNION ALL SELECT 'rpc escrita', 'anon NÃO executa', 'false',
         coalesce(has_function_privilege('anon', to_regprocedure('public.registrar_progresso_consulta_pagamento(text,text,text,integer,integer,text,text,text,text,boolean)'), 'EXECUTE')::text, 'AUSENTE')
  UNION ALL SELECT 'rpc escrita', 'authenticated executa (worker)', 'true',
         coalesce(has_function_privilege('authenticated', to_regprocedure('public.registrar_progresso_consulta_pagamento(text,text,text,integer,integer,text,text,text,text,boolean)'), 'EXECUTE')::text, 'AUSENTE')
  UNION ALL SELECT 'rpc escrita', 'service_role executa', 'true',
         coalesce(has_function_privilege('service_role', to_regprocedure('public.registrar_progresso_consulta_pagamento(text,text,text,integer,integer,text,text,text,text,boolean)'), 'EXECUTE')::text, 'AUSENTE')
  UNION ALL SELECT 'rpc escrita', 'valida DEPRE completo (regex atualizada)', 'sim',
         -- strpos, não LIKE: em LIKE a barra invertida é o caractere de escape.
         CASE WHEN strpos(coalesce((SELECT prosrc FROM pg_proc WHERE oid = to_regprocedure('public.registrar_progresso_consulta_pagamento(text,text,text,integer,integer,text,text,text,text,boolean)')), ''), '\d{7}-\d{2}') > 0
              THEN 'sim' ELSE 'NAO (rode o SQL 4 atualizado)' END

  -- RPC de leitura
  UNION ALL SELECT 'rpc leitura', 'existe', 'sim',
         CASE WHEN to_regprocedure('public.obter_progresso_consulta_pagamento(text)') IS NOT NULL THEN 'sim' ELSE 'NAO' END
  UNION ALL SELECT 'rpc leitura', 'SECURITY DEFINER', 'true',
         coalesce((SELECT prosecdef::text FROM pg_proc WHERE oid = to_regprocedure('public.obter_progresso_consulta_pagamento(text)')), 'AUSENTE')
  UNION ALL SELECT 'rpc leitura', 'anon NÃO executa', 'false',
         coalesce(has_function_privilege('anon', to_regprocedure('public.obter_progresso_consulta_pagamento(text)'), 'EXECUTE')::text, 'AUSENTE')
  UNION ALL SELECT 'rpc leitura', 'authenticated NÃO executa', 'false',
         coalesce(has_function_privilege('authenticated', to_regprocedure('public.obter_progresso_consulta_pagamento(text)'), 'EXECUTE')::text, 'AUSENTE')
  UNION ALL SELECT 'rpc leitura', 'service_role executa', 'true',
         coalesce(has_function_privilege('service_role', to_regprocedure('public.obter_progresso_consulta_pagamento(text)'), 'EXECUTE')::text, 'AUSENTE')
)
SELECT secao, item, esperado, atual, (esperado = atual) AS ok
FROM checks
ORDER BY (esperado = atual), secao, item;
