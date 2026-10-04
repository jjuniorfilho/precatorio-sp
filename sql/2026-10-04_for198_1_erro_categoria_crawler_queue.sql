-- FOR-198 (1 de 2) — persiste a categoria do erro em crawler_queue, classificada no worker na
-- hora do erro (src/erro-categoria.ts). Nullable: sem erro = sem categoria (NÃO usa
-- NOT NULL DEFAULT 'outro' — 'outro' é reservado pra "erro classificado, sem categoria
-- específica", não pra "nunca foi classificado"; linhas antigas ficam NULL honestamente).
--
-- TEXT + CHECK (não enum nativo do Postgres) — decisão de arquitetura #3 da issue; mesmo
-- padrão já usado nesta mesma tabela em `status`/`origem`.
--
-- DROP FUNCTION + CREATE (não CREATE OR REPLACE): Postgres não deixa replace acrescentar
-- parâmetro à assinatura existente — mesmo padrão já usado no repo em
-- sql/2026-10-03_for195c_expoe_processo_cnj_buscar_processos_incidente.sql.
--
-- Valide em sandbox local ANTES de aplicar (sql/sandbox/for198_validate_local.sh).
-- Aplicar no SQL Editor do banco que o worker-crawler usa. Re-executável.

ALTER TABLE public.crawler_queue ADD COLUMN IF NOT EXISTS erro_categoria text;

ALTER TABLE public.crawler_queue DROP CONSTRAINT IF EXISTS crawler_queue_erro_categoria_check;
ALTER TABLE public.crawler_queue ADD CONSTRAINT crawler_queue_erro_categoria_check
  CHECK (erro_categoria IN (
    'captcha', 'timeout', 'rate_limit', 'site_indisponivel',
    'bloqueio_suspeito', 'cnj_nao_encontrado', 'outro'
  ));

DROP FUNCTION IF EXISTS public.fail_crawler_job(uuid, text);

CREATE FUNCTION public.fail_crawler_job(p_id uuid, p_erro text, p_categoria text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE crawler_queue
     SET tentativas     = tentativas + 1,
         erro           = p_erro,
         erro_categoria = p_categoria,
         updated_at     = NOW(),
         status         = CASE WHEN tentativas + 1 >= 3 THEN 'erro' ELSE 'pendente' END,
         scheduled_at   = CASE WHEN tentativas + 1 >= 3 THEN scheduled_at
                               ELSE NOW() + (ARRAY['15 minutes','1 hour'])[tentativas + 1]::interval END
   WHERE id = p_id;
END; $$;

REVOKE ALL ON FUNCTION public.fail_crawler_job(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fail_crawler_job(uuid, text, text) TO service_role;

NOTIFY pgrst, 'reload schema';
