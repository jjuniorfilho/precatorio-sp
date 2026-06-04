ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS intent TEXT
    CHECK (intent IN ('cessao', 'acordo', 'info'));

COMMENT ON COLUMN public.leads.intent IS
  'Caminho escolhido pelo lead na tela de resultado: cessao (antecipação), acordo (negociação com o ente público) ou info (apenas relatório).';

CREATE INDEX IF NOT EXISTS idx_leads_intent ON public.leads (intent);