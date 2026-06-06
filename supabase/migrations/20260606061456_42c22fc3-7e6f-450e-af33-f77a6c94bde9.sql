GRANT SELECT, INSERT, UPDATE, DELETE ON public.comunicacoes_agendadas TO authenticated;
GRANT ALL ON public.comunicacoes_agendadas TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.funnel_events TO authenticated;
GRANT SELECT, INSERT ON public.funnel_events TO anon;
GRANT ALL ON public.funnel_events TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_precatorios TO authenticated;
GRANT ALL ON public.lead_precatorios TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_status_history TO authenticated;
GRANT ALL ON public.lead_status_history TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.tokens TO authenticated;
GRANT ALL ON public.tokens TO service_role;

GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.leads TO anon;
GRANT ALL ON public.leads TO service_role;

GRANT SELECT ON public.precatorios TO authenticated, anon;
GRANT ALL ON public.precatorios TO service_role;

GRANT SELECT ON public.blog_posts TO authenticated, anon;
GRANT ALL ON public.blog_posts TO service_role;