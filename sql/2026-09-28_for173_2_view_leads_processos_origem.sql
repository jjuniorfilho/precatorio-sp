-- FOR-173 (2 de 4) — `leads_processos` passa a expor `origem` (o grid do FOR-174 precisa do selo
-- "Avulso" e do filtro por origem).
--
-- Como: CREATE OR REPLACE VIEW acrescentando `lp.origem` como a ÚLTIMA coluna. O Postgres aceita colunas
-- novas no FIM do SELECT (mesmos nomes, tipos e ordem das existentes) — por isso NÃO há DROP VIEW e o grid
-- nunca fica sem view. `leads_com_progresso` NÃO é tocada (já expõe `origem`, pois é `l.*` e foi recriada
-- depois de a coluna existir).
--
-- A definição abaixo é a VIVA no banco em 2026-09-28 (pg_get_viewdef colado do diagnóstico
-- sql/2026-09-28_for173_0_diag_leads_ddl.sql), reescrita com aliases legíveis. Se alguém alterar a view
-- antes de aplicar este SQL, refaça o diagnóstico e reconcilie.
--
-- SEGURANÇA (igual à FOR-169): leads tem PII e RLS admin-only; security_invoker = true e acesso só a
-- service_role (usado por supabaseAdmin em listLeads).
--
-- Re-executável. Aplicar DEPOIS do SQL 1.

CREATE OR REPLACE VIEW public.leads_processos
WITH (security_invoker = true) AS
SELECT
  lp.id,
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
  inc.cessao_credito,
  lp.origem
FROM public.leads_com_progresso lp
LEFT JOIN LATERAL (
  SELECT DISTINCT btrim(x) AS processo
  FROM regexp_split_to_table(COALESCE(lp.processo_depre, ''), ',') AS x
  WHERE btrim(x) <> ''
) p ON true
LEFT JOIN LATERAL (
  SELECT r.saldo_depre, r.valor_pago, r.pagamentos_consultado_em
  FROM public.precatorios r
  WHERE r.processo_depre = p.processo
  ORDER BY r.updated_at DESC NULLS LAST
  LIMIT 1
) pr ON true
LEFT JOIN LATERAL (
  SELECT bool_or(d.acordo_homologado) AS acordo_homologado,
         max(d.valor_acao) FILTER (WHERE d.ficha_crawled_at IS NOT NULL) AS valor_causa
  FROM public.djen_depre d
  WHERE d.cnj_normalizado = regexp_replace(p.processo, '\D', '', 'g')
) dj ON true
LEFT JOIN LATERAL (
  SELECT bool_or(i.cessao_credito) AS cessao_credito
  FROM public.incidentes i
  WHERE i.numero_depre = p.processo
) inc ON true;

REVOKE ALL ON public.leads_processos FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_processos TO service_role;

NOTIFY pgrst, 'reload schema';
