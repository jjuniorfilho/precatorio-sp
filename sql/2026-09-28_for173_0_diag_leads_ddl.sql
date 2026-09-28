-- FOR-173 (0 de 4) — DIAGNÓSTICO read-only do DDL real de public.leads.
--
-- Por que: o DDL de `leads` foi criado pelo Lovable e não está no repo. Antes de escrever a migration do
-- lead avulso (origem, criado_por, nome/email/telefone/relacao NULL) e de recriar as views
-- (leads_com_progresso, leads_processos) precisamos saber, do banco VIVO: colunas e NOT NULLs, CHECKs,
-- índices UNIQUE, triggers, policies, FKs, views dependentes (com a definição atual) e funções que citam leads.
--
-- NÃO altera nada (só SELECT em catálogos + um count). Rodar no SQL Editor do Supabase (projeto nxkvfc…,
-- o mesmo do worker) e colar o RESULTADO COMPLETO (a coluna `detalhe` das linhas `definicao_view` é longa:
-- use "Copy as CSV/JSON" ou expanda a célula).

WITH
cols AS (
  SELECT 'colunas'::text AS secao, lpad(ordinal_position::text, 3, '0') AS ordem, column_name::text AS item,
         format('%s | nullable=%s | default=%s', data_type, is_nullable, coalesce(column_default, '-')) AS detalhe
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name = 'leads'
),
cons AS (
  SELECT 'constraints', '', conname::text, contype::text || ' | ' || pg_get_constraintdef(oid)
  FROM pg_constraint
  WHERE conrelid = 'public.leads'::regclass
),
fks AS (
  SELECT 'fks_para_leads', '', conrelid::regclass::text, pg_get_constraintdef(oid)
  FROM pg_constraint
  WHERE confrelid = 'public.leads'::regclass
),
idx AS (
  SELECT 'indices', '', indexname::text, indexdef
  FROM pg_indexes
  WHERE schemaname = 'public' AND tablename = 'leads'
),
trg AS (
  SELECT 'triggers', '', tgname::text, pg_get_triggerdef(oid)
  FROM pg_trigger
  WHERE tgrelid = 'public.leads'::regclass AND NOT tgisinternal
),
pol AS (
  SELECT 'policies_rls', '', policyname::text,
         format('%s | roles=%s | using=%s | check=%s', cmd, roles::text, coalesce(qual, '-'), coalesce(with_check, '-'))
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'leads'
),
rls AS (
  SELECT 'rls_ligado', '', relname::text, relrowsecurity::text
  FROM pg_class
  WHERE oid = 'public.leads'::regclass
),
vdep AS (
  SELECT 'views_que_usam_leads', '', view_name::text, view_schema::text
  FROM information_schema.view_table_usage
  WHERE table_schema = 'public' AND table_name = 'leads'
),
vdef AS (
  SELECT 'definicao_view', '', c.relname::text, pg_get_viewdef(c.oid, true)
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'v'
    AND c.relname IN ('leads_com_progresso', 'leads_processos')
),
vopts AS (
  SELECT 'opcoes_view', '', c.relname::text, coalesce(array_to_string(c.reloptions, ','), '-')
  FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind = 'v'
    AND c.relname IN ('leads_com_progresso', 'leads_processos')
),
fns AS (
  SELECT 'funcoes_que_citam_leads', '', p.proname::text,
         format('(%s) | security_definer=%s', pg_get_function_identity_arguments(p.oid), p.prosecdef)
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.prokind = 'f' AND p.prosrc ~* '\mleads\M'
),
for171 AS (
  SELECT 'for171_aplicado', '', 'tabela pagamentos_consultas_log',
         coalesce(to_regclass('public.pagamentos_consultas_log')::text, 'AUSENTE')
  UNION ALL
  SELECT 'for171_aplicado', '', 'rpc registrar_consulta_pagamento',
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                           WHERE n.nspname = 'public' AND p.proname = 'registrar_consulta_pagamento')
              THEN 'presente' ELSE 'AUSENTE' END
  UNION ALL
  SELECT 'for171_aplicado', '', 'rpc listar_consultas_pagamento',
         CASE WHEN EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                           WHERE n.nspname = 'public' AND p.proname = 'listar_consultas_pagamento')
              THEN 'presente' ELSE 'AUSENTE' END
),
volume AS (
  SELECT 'volume', '', 'linhas_em_leads', count(*)::text FROM public.leads
)
SELECT * FROM cols
UNION ALL SELECT * FROM cons
UNION ALL SELECT * FROM fks
UNION ALL SELECT * FROM idx
UNION ALL SELECT * FROM trg
UNION ALL SELECT * FROM pol
UNION ALL SELECT * FROM rls
UNION ALL SELECT * FROM vdep
UNION ALL SELECT * FROM vdef
UNION ALL SELECT * FROM vopts
UNION ALL SELECT * FROM fns
UNION ALL SELECT * FROM for171
UNION ALL SELECT * FROM volume
ORDER BY 1, 2, 3;
