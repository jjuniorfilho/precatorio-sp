-- 1. Tabela de histórico lead ↔ processo
CREATE TABLE public.lead_precatorios (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id uuid NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
  processo_depre text NOT NULL,
  intent text,
  saldo_consultado bigint,
  devedora text,
  consultado_em timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_lead_precatorios_lead ON public.lead_precatorios(lead_id);
CREATE INDEX idx_lead_precatorios_processo ON public.lead_precatorios(processo_depre);

GRANT SELECT, INSERT ON public.lead_precatorios TO authenticated;
GRANT ALL ON public.lead_precatorios TO service_role;

ALTER TABLE public.lead_precatorios ENABLE ROW LEVEL SECURITY;

-- Sem acesso anônimo. Apenas service_role (edge functions) e admin via auth.
CREATE POLICY "service_role full access lead_precatorios"
  ON public.lead_precatorios FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 2. Carimbar quando o lead foi totalmente verificado (email + whatsapp)
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS verified_at timestamptz;