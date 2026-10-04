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
-- Aplicar no SQL Editor do banco que o worker-crawler usa, ANTES de deployar/reiniciar o
-- worker: o código novo já manda `p_categoria` em toda chamada — se a função ainda não aceitar
-- esse parâmetro, o PostgREST não resolve a RPC (PGRST202) e `failJob` falha por completo
-- (erro engolido pelo `.catch(() => {})` do chamador, falha SILENCIOSA: tentativas/backoff
-- parariam de avançar até a migration ser aplicada). Re-executável.

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

-- authenticated: o worker em produção roda SEM service_role (anon key + login admin — "Opção
-- B", ver supabase.ts::ensureAuth e sql/2026-07-24_reset_orfaos_crawler_queue_rpc.sql) — a
-- assinatura antiga nunca tinha REVOKE FROM PUBLIC, então `authenticated` chamava via o
-- privilégio padrão do schema public; sem este GRANT explícito aqui, o REVOKE ALL abaixo
-- fecharia esse acesso de verdade (achado em code review: 3 revisões independentes pegaram
-- isso) — mesmo padrão de GRANT já usado pra `registrar_consulta_pagamento` no arquivo 2/2.
REVOKE ALL ON FUNCTION public.fail_crawler_job(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fail_crawler_job(uuid, text, text) TO authenticated, service_role;

-- requeue_failed (RPC do monitor, sql/for73): reprocessa falhas voltando pra 'pendente' e
-- zerando erro/tentativas — precisa zerar erro_categoria junto, senão um job reprocessado com
-- sucesso ficaria com a categoria de uma falha antiga (lixo em qualquer agregação por
-- categoria). Assinatura (TEXT) não muda — CREATE OR REPLACE preserva os GRANTs existentes.
CREATE OR REPLACE FUNCTION public.requeue_failed(p_origem TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  UPDATE crawler_queue cq
     SET status='pendente', scheduled_at=NOW(), erro=NULL, erro_categoria=NULL, tentativas=0, updated_at=NOW()
   WHERE cq.status='erro'
     AND (p_origem IS NULL OR cq.origem = p_origem)
     AND NOT EXISTS (
       SELECT 1 FROM crawler_queue o
        WHERE o.processo_codigo = cq.processo_codigo AND o.status IN ('pendente','processando')
     );
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END; $$;

NOTIFY pgrst, 'reload schema';
