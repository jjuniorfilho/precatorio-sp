
-- 1. Flag de envio do relatório no lead
ALTER TABLE public.leads
  ADD COLUMN IF NOT EXISTS relatorio_enviado_at TIMESTAMPTZ;

-- 2. Tabela de comunicações agendadas
CREATE TABLE IF NOT EXISTS public.comunicacoes_agendadas (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID NOT NULL REFERENCES public.leads(id) ON DELETE CASCADE,
  canal TEXT NOT NULL CHECK (canal IN ('whatsapp','email')),
  tipo TEXT NOT NULL,
  agendado_para TIMESTAMPTZ NOT NULL,
  enviado_em TIMESTAMPTZ,
  status TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','enviado','falhou','cancelado')),
  tentativas INT NOT NULL DEFAULT 0,
  erro TEXT,
  payload JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT ALL ON public.comunicacoes_agendadas TO service_role;

ALTER TABLE public.comunicacoes_agendadas ENABLE ROW LEVEL SECURITY;

-- Sem políticas para anon/authenticated: apenas service_role acessa.

CREATE INDEX IF NOT EXISTS idx_comunicacoes_pendentes
  ON public.comunicacoes_agendadas (agendado_para)
  WHERE status = 'pendente';

CREATE INDEX IF NOT EXISTS idx_comunicacoes_lead
  ON public.comunicacoes_agendadas (lead_id);

CREATE TRIGGER update_comunicacoes_updated_at
  BEFORE UPDATE ON public.comunicacoes_agendadas
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at();

-- 3. pg_cron + pg_net para chamar o worker
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Job a cada 5 min chamando a edge function processar-comunicacoes
DO $$
BEGIN
  PERFORM cron.unschedule('processar-comunicacoes-5m');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule(
  'processar-comunicacoes-5m',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://nxkvfcrnocdxysqsuozj.supabase.co/functions/v1/processar-comunicacoes',
    headers := jsonb_build_object('Content-Type','application/json'),
    body := jsonb_build_object('source','cron')
  );
  $$
);
