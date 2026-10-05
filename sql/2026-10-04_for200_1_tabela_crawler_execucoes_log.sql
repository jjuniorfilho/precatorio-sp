-- FOR-200 (1 de 3) — Tabela de log append-only das execuções do crawler_queue (Crawler e-SAJ
-- + Consulta DEPRE/.0500 — mesmo pipeline, só se distinguem pelo sufixo do processo_codigo).
-- Decisão de arquitetura já resolvida pelo humano (comentário de 2026-10-04 na issue): tabela
-- de log append-only, não Supabase Realtime — mesmo padrão de `pagamentos_consultas_log`
-- (FOR-171/198). Ver .claude/sessions/for-200-graficos-coleta/architecture.md pro racional
-- completo (inclui por que "Consulta de pagamento TJSP" NÃO precisa de tabela nova — já tem a
-- sua, pagamentos_consultas_log, reaproveitada sem mudança nesta sessão).
--
-- Só é escrita via INSERT dentro de complete_crawler_job/fail_crawler_job (arquivo 2/3) —
-- nenhum UPDATE/DELETE de linha individual (DELETE em massa por retenção de tempo é o único
-- DELETE, dentro da mesma RPC de escrita).
--
-- Valide em sandbox local ANTES de aplicar (sql/sandbox/for200_validate_local.sh).
-- Aplicar no SQL Editor do banco que o worker-crawler usa, ANTES de aplicar o arquivo 2/3 e
-- ANTES de deployar/reiniciar o worker. Re-executável.

CREATE TABLE IF NOT EXISTS public.crawler_execucoes_log (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id          uuid        NOT NULL,
  processo_codigo text        NOT NULL,
  raia            smallint    NOT NULL,
  resultado       text        NOT NULL CHECK (resultado IN ('ok', 'erro')),
  erro_categoria  text        CHECK (erro_categoria IN (
                    'captcha', 'timeout', 'rate_limit', 'site_indisponivel',
                    'bloqueio_suspeito', 'cnj_nao_encontrado', 'outro'
                  )),
  terminal        boolean     NOT NULL,
  criado_em       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_crawler_execucoes_log_criado_em
  ON public.crawler_execucoes_log (criado_em DESC);

-- Admin roda anônimo (/admin) — leitura só via RPC SECURITY DEFINER (padrão "admin-anon-rpc" já
-- usado em pagamentos_consultas_log/coleta_runs). Nenhuma policy: RLS ligado fecha tudo pra
-- anon/authenticated via SELECT/INSERT direto; o worker escreve via RPC SECURITY DEFINER
-- (bypassa RLS por rodar como owner da função), e as RPCs de leitura (arquivo 3/3) também.
ALTER TABLE public.crawler_execucoes_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crawler_execucoes_log FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
