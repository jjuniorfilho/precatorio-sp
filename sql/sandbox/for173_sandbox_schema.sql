-- SANDBOX LOCAL DESCARTÁVEL — réplica do estado VIVO de produção descrito pelo diagnóstico de 2026-09-28
-- (sql/2026-09-28_for173_0_diag_leads_ddl.sql), ANTES de aplicar qualquer SQL do FOR-173.
-- NÃO é produção e NÃO deve ser aplicado em nenhum banco real. Usado por sql/sandbox/for173_validate_local.sh.
--
-- Fidelidade: papéis do Supabase (anon/authenticated/service_role), DEFAULT PRIVILEGES do Supabase (objetos novos em
-- public nascem com ALL para os três papéis — por isso os REVOKE dos SQLs do FOR-173 são explícitos), colunas/CHECKs/
-- índices/triggers/policies/grants reais de leads, e as duas views com a definição VIVA (pg_get_viewdef colado do
-- diagnóstico). Tabelas auxiliares (funnel_events, precatorios, djen_depre, incidentes) têm só as colunas que as
-- views usam. O trigger de enfileirar crawler é um stub.

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
GRANT anon, authenticated, service_role TO CURRENT_USER;

-- Supabase: objetos novos em public nascem com ALL para anon/authenticated/service_role
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon, authenticated, service_role;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON SEQUENCES TO anon, authenticated, service_role;
CREATE SCHEMA auth;
CREATE FUNCTION auth.jwt() RETURNS jsonb LANGUAGE sql STABLE AS $$ SELECT coalesce(nullif(current_setting('request.jwt.claims', true), ''), '{}')::jsonb $$;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

CREATE FUNCTION update_updated_at() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN NEW.updated_at = now(); RETURN NEW; END $$;

CREATE TABLE public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text,
  email text NOT NULL,
  telefone text,
  relacao text NOT NULL,
  processo_depre text,
  saldo_consultado bigint NOT NULL DEFAULT 0,
  devedora text,
  status_crm text NOT NULL DEFAULT 'novo',
  notas text DEFAULT '',
  token_email_validado boolean NOT NULL DEFAULT false,
  token_telefone_validado boolean NOT NULL DEFAULT false,
  session_id text,
  utm_source text, utm_medium text, utm_campaign text,
  lgpd_consent boolean NOT NULL DEFAULT false,
  lgpd_consent_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  intent text,
  relatorio_enviado_at timestamptz,
  verified_at timestamptz,
  origem text,
  cnj text,
  CONSTRAINT leads_intent_check CHECK (intent = ANY (ARRAY['cessao','acordo','info'])),
  CONSTRAINT leads_relacao_check CHECK (relacao = ANY (ARRAY['titular','herdeiro','advogado'])),
  CONSTRAINT leads_status_crm_check CHECK (status_crm = ANY (ARRAY['novo','contatado','qualificado','interessado','proposta','negociacao','fechado','descartado']))
);
CREATE INDEX idx_leads_created_at ON public.leads (created_at DESC);
CREATE INDEX idx_leads_email ON public.leads (email);
CREATE INDEX idx_leads_intent ON public.leads (intent);
CREATE INDEX idx_leads_origem ON public.leads (origem);
CREATE INDEX idx_leads_status_crm ON public.leads (status_crm);

CREATE TABLE public.crawler_queue_stub (processo text);
CREATE FUNCTION public.trg_leads_enfileira_crawler() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN INSERT INTO crawler_queue_stub VALUES (NEW.processo_depre); RETURN NEW; END $$;
CREATE TRIGGER leads_updated_at BEFORE UPDATE ON public.leads FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER trg_leads_enfileira_crawler AFTER INSERT OR UPDATE OF processo_depre ON public.leads FOR EACH ROW EXECUTE FUNCTION public.trg_leads_enfileira_crawler();

ALTER TABLE public.leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY anon_insert_leads ON public.leads FOR INSERT TO anon WITH CHECK (lgpd_consent = true);
CREATE POLICY leads_admin_only ON public.leads FOR ALL TO authenticated
  USING (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text)
  WITH CHECK (((auth.jwt() -> 'app_metadata'::text) ->> 'role'::text) = 'admin'::text);
GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.leads TO anon;
GRANT ALL ON public.leads TO service_role;

CREATE TABLE public.funnel_events (event_type text, lead_id uuid, session_id text);
CREATE TABLE public.precatorios (processo_depre text, saldo_depre bigint, valor_pago bigint, pagamentos_consultado_em timestamptz, updated_at timestamptz);
CREATE TABLE public.djen_depre (cnj_normalizado text, acordo_homologado boolean, valor_acao bigint, ficha_crawled_at timestamptz);
CREATE TABLE public.incidentes (numero_depre text, cessao_credito boolean);

-- leads_com_progresso: definição VIVA (pg_get_viewdef do diagnóstico)
CREATE VIEW public.leads_com_progresso WITH (security_invoker = true) AS
 SELECT id, nome, email, telefone, relacao, processo_depre, saldo_consultado, devedora, status_crm, notas,
    token_email_validado, token_telefone_validado, session_id, utm_source, utm_medium, utm_campaign,
    lgpd_consent, lgpd_consent_at, created_at, updated_at, intent, relatorio_enviado_at, verified_at, origem, cnj,
        CASE
            WHEN relatorio_enviado_at IS NOT NULL THEN 6
            WHEN token_telefone_validado THEN 5
            WHEN token_email_validado THEN 4
            WHEN (EXISTS ( SELECT 1 FROM funnel_events fe WHERE fe.event_type = 'token_email_enviado'::text AND fe.lead_id = l.id)) OR (EXISTS ( SELECT 1 FROM funnel_events fe WHERE fe.event_type = 'token_email_enviado'::text AND fe.session_id = l.session_id)) THEN 3
            ELSE 2
        END AS nivel_funil,
    NULLIF(btrim(processo_depre), ''::text) IS NOT NULL OR (EXISTS ( SELECT 1 FROM funnel_events fe WHERE fe.event_type = 'busca_realizada'::text AND fe.session_id = l.session_id)) AS etapa1_busca,
    true AS etapa2_cadastro,
    COALESCE(token_email_validado, false) OR (EXISTS ( SELECT 1 FROM funnel_events fe WHERE fe.event_type = 'token_email_enviado'::text AND fe.lead_id = l.id)) OR (EXISTS ( SELECT 1 FROM funnel_events fe WHERE fe.event_type = 'token_email_enviado'::text AND fe.session_id = l.session_id)) AS etapa3_token_email,
    COALESCE(token_email_validado, false) AS etapa4_email_validado,
    COALESCE(token_telefone_validado, false) AS etapa5_whatsapp_validado,
    relatorio_enviado_at IS NOT NULL AS etapa6_relatorio
   FROM leads l;
REVOKE ALL ON public.leads_com_progresso FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_com_progresso TO service_role;

-- leads_processos: definição VIVA (pg_get_viewdef do diagnóstico, colada de scratchpad/leads_processos_live_def.txt)
CREATE VIEW public.leads_processos WITH (security_invoker = true) AS
 SELECT lp.id,
    lp.nome,
    lp.email,
    lp.telefone,
    lp.relacao,
    lp.processo_depre,
    lp.saldo_consultado,
    lp.devedora,
    lp.status_crm,
    lp.notas,
    lp.token_email_validado,
    lp.token_telefone_validado,
    lp.relatorio_enviado_at,
    lp.session_id,
    lp.intent,
    lp.created_at,
    lp.updated_at,
    lp.verified_at,
    lp.nivel_funil,
    lp.etapa1_busca,
    lp.etapa2_cadastro,
    lp.etapa3_token_email,
    lp.etapa4_email_validado,
    lp.etapa5_whatsapp_validado,
    lp.etapa6_relatorio,
    p.processo,
    dj.valor_causa,
    pr.saldo_depre,
    pr.valor_pago,
    pr.pagamentos_consultado_em,
    dj.acordo_homologado,
    inc.cessao_credito
   FROM leads_com_progresso lp
     LEFT JOIN LATERAL ( SELECT DISTINCT btrim(x.x) AS processo
           FROM regexp_split_to_table(COALESCE(lp.processo_depre, ''::text), ','::text) x(x)
          WHERE btrim(x.x) <> ''::text) p ON true
     LEFT JOIN LATERAL ( SELECT r.saldo_depre,
            r.valor_pago,
            r.pagamentos_consultado_em
           FROM precatorios r
          WHERE r.processo_depre = p.processo
          ORDER BY r.updated_at DESC NULLS LAST
         LIMIT 1) pr ON true
     LEFT JOIN LATERAL ( SELECT bool_or(d.acordo_homologado) AS acordo_homologado,
            max(d.valor_acao) FILTER (WHERE d.ficha_crawled_at IS NOT NULL) AS valor_causa
           FROM djen_depre d
          WHERE d.cnj_normalizado = regexp_replace(p.processo, '\D'::text, ''::text, 'g'::text)) dj ON true
     LEFT JOIN LATERAL ( SELECT bool_or(i.cessao_credito) AS cessao_credito
           FROM incidentes i
          WHERE i.numero_depre = p.processo) inc ON true;
REVOKE ALL ON public.leads_processos FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_processos TO service_role;
