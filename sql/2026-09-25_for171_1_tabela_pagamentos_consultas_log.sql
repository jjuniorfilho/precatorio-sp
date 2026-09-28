-- FOR-171 (1 de 3) — Tabela de log das consultas ao portal TJSP "Pagamentos Precatórios".
-- Uma linha por consulta (manual, busca pública ou ciclo do crawler), com resultado final e os
-- passos (jsonb) com horário/status/etapa. Retenção: últimas 20 por processo (poda na RPC de escrita).
-- Acesso SÓ via RPC SECURITY DEFINER (registrar_consulta_pagamento / listar_consultas_pagamento):
-- RLS ligado, sem policy, sem GRANT de tabela para anon/authenticated (o /admin roda anônimo).
-- Re-executável. Aplicar ANTES do 2 e do 3, no SQL Editor do banco que o worker-crawler usa.
-- (CONFIRMAR ANTES: `grep SUPABASE_URL /opt/precatorio-worker/.env | cut -c1-40` → nxkvfc…)

CREATE TABLE IF NOT EXISTS public.pagamentos_consultas_log (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_depre       text        NOT NULL,
  iniciada_em          timestamptz NOT NULL,
  finalizada_em        timestamptz,
  origem               text        NOT NULL CHECK (origem IN ('manual', 'busca_publica', 'crawler')),
  resultado            text        NOT NULL CHECK (resultado IN ('encontrado', 'nao_consta', 'falha')),
  tentativas           integer     NOT NULL DEFAULT 0,
  situacao             text,
  qtd_pagamentos       integer,
  data_consulta_portal text,
  erro                 text,
  etapa_falha          text,
  passos               jsonb       NOT NULL DEFAULT '[]'::jsonb,
  criado_em            timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pagamentos_consultas_log_processo
  ON public.pagamentos_consultas_log (processo_depre, iniciada_em DESC);

ALTER TABLE public.pagamentos_consultas_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pagamentos_consultas_log FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
