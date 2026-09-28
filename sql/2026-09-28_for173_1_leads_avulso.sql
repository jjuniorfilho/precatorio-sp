-- FOR-173 (1 de 4) — `leads` passa a aceitar o lead AVULSO (cadastrado pelo operador no admin).
--
-- Contexto (diagnóstico do DDL vivo, 2026-09-28, ver .claude/sessions/for-173-*/architecture.md §0):
--   * `leads.origem` JÁ EXISTE (text, nullable, sem CHECK): guarda a origem do fluxo público
--     (busca_em_formacao | monitorar | antecipacao). O lead avulso usa o novo valor 'avulso'.
--     NÃO criar coluna nem CHECK em `origem`.
--   * Só `email` e `relacao` eram NOT NULL (nome, telefone, processo_depre, cnj já são nullable).
--     O CHECK de `relacao` aceita NULL nativamente (CHECK com NULL passa): só DROP NOT NULL.
--
-- O que faz:
--   1. `criado_por uuid`  — auth.users.id do admin que cadastrou (sem FK; é só auditoria).
--   2. `documento text`   — CPF (11) ou CNPJ (14) pesquisado pelo operador, SÓ DÍGITOS. PII: nunca
--                           em log, nunca exposto a anon (RLS leads_admin_only já protege a tabela).
--   3. `email` e `relacao` passam a aceitar NULL.
--   4. Índice único parcial: no máximo UM lead avulso por DEPRE (corrida de duplo clique).
--
-- ATENÇÃO — efeito colateral BENÉFICO no FOR-175: a edge `capturar-lead-publico` insere sem `relacao`
-- (NOT NULL até aqui) e por isso nunca gravou nenhum lead. Com o DROP NOT NULL ela passa a gravar,
-- com origem = busca_em_formacao | monitorar | antecipacao, só e-mail, sem nome/telefone/relação.
-- Esses leads aparecerão no grid de /admin/leads.
--
-- Não mexe nas views (leads_com_progresso já expõe `origem`; ver o SQL 2). `criado_por` e `documento`
-- ficam FORA das views de propósito: como leads_com_progresso é `l.*`, coluna nova cairia no meio e
-- exigiria DROP VIEW; o modal lê essas colunas direto de `leads`.
--
-- Re-executável. Aplicar no SQL Editor do projeto Supabase que o worker usa (nxkvfc…), ANTES dos SQLs
-- 2, 3 e 4. Fora do horário de pico não é necessário (sem DROP, sem lock longo).

ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS criado_por uuid;
ALTER TABLE public.leads ADD COLUMN IF NOT EXISTS documento text;

ALTER TABLE public.leads ALTER COLUMN email   DROP NOT NULL;
ALTER TABLE public.leads ALTER COLUMN relacao DROP NOT NULL;

COMMENT ON COLUMN public.leads.origem IS
  'Origem do lead: busca_em_formacao | monitorar | antecipacao (fluxo público) | avulso (cadastrado pelo operador no admin, sem 2 canais validados e com lgpd_consent = false).';
COMMENT ON COLUMN public.leads.criado_por IS
  'auth.users.id do admin que cadastrou o lead avulso (null nos leads do site).';
COMMENT ON COLUMN public.leads.documento IS
  'CPF (11) ou CNPJ (14) pesquisado pelo operador ao cadastrar o lead avulso, só dígitos. PII: nunca em log, nunca exposto a anon; null nos leads do site.';

-- documento: null ou 11/14 dígitos (a server function normaliza antes de gravar).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.leads'::regclass AND conname = 'leads_documento_check'
  ) THEN
    ALTER TABLE public.leads
      ADD CONSTRAINT leads_documento_check
      CHECK (documento IS NULL OR documento ~ '^\d{11}(\d{3})?$');
  END IF;
END $$;

-- No máximo um lead avulso por DEPRE (o avulso sempre tem um único .0500 em processo_depre).
CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_avulso_processo_depre
  ON public.leads (processo_depre)
  WHERE origem = 'avulso';

NOTIFY pgrst, 'reload schema';
