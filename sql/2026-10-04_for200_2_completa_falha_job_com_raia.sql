-- FOR-200 (2 de 3) — complete_crawler_job/fail_crawler_job passam a aceitar `p_raia` (lane do
-- worker) e, quando informado, logam 1 linha em crawler_execucoes_log (arquivo 1/3) dentro da
-- MESMA transação da UPDATE em crawler_queue. `p_raia DEFAULT NULL`: se vier NULL (worker ainda
-- não atualizado, chamada manual/teste), a função só PULA o log — nunca falha a chamada por
-- causa de telemetria (mesmo espírito defensivo do `.catch(() => {})` já usado em index.ts ao
-- redor de failJob).
--
-- DROP FUNCTION + CREATE (não CREATE OR REPLACE): Postgres não deixa replace acrescentar
-- parâmetro à assinatura existente — mesmo padrão já usado no repo (sql/2026-10-03_for195c_...,
-- sql/2026-10-04_for198_1_...).
--
-- GRANT explícito pras duas (endurece complete_crawler_job também: a assinatura original em
-- supabase/migrations/20260627195519_for73_... NUNCA teve REVOKE ALL FROM PUBLIC — vazava
-- EXECUTE pra anon via privilégio padrão do schema public, mesmo achado de code review que o
-- FOR-198 corrigiu em fail_crawler_job; corrigido aqui também, agora nos dois).
--
-- Valide em sandbox local ANTES de aplicar (sql/sandbox/for200_validate_local.sh).
-- Aplicar DEPOIS do arquivo 1/3 e ANTES de deployar/reiniciar o worker: o código novo já manda
-- `p_raia` em toda chamada de completeJob/failJob — se a função ainda não aceitar esse
-- parâmetro, o PostgREST não resolve a RPC (PGRST202) e a chamada falha por completo (mesmo
-- risco documentado no FOR-198 pro p_categoria). Re-executável.

DROP FUNCTION IF EXISTS public.complete_crawler_job(uuid);

CREATE FUNCTION public.complete_crawler_job(p_id uuid, p_raia integer DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_processo text;
BEGIN
  UPDATE crawler_queue SET status = 'ok', updated_at = NOW()
   WHERE id = p_id
   RETURNING processo_codigo INTO v_processo;

  IF v_processo IS NOT NULL AND p_raia IS NOT NULL THEN
    INSERT INTO crawler_execucoes_log (job_id, processo_codigo, raia, resultado, terminal)
    VALUES (p_id, v_processo, p_raia, 'ok', true);
    DELETE FROM crawler_execucoes_log WHERE criado_em < now() - interval '3 days';
  END IF;
END; $$;

REVOKE ALL ON FUNCTION public.complete_crawler_job(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_crawler_job(uuid, integer) TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.fail_crawler_job(uuid, text, text);

CREATE FUNCTION public.fail_crawler_job(
  p_id uuid, p_erro text, p_categoria text DEFAULT NULL, p_raia integer DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_processo text; v_tentativas int;
BEGIN
  UPDATE crawler_queue
     SET tentativas     = tentativas + 1,
         erro           = p_erro,
         erro_categoria = p_categoria,
         updated_at     = NOW(),
         status         = CASE WHEN tentativas + 1 >= 3 THEN 'erro' ELSE 'pendente' END,
         scheduled_at   = CASE WHEN tentativas + 1 >= 3 THEN scheduled_at
                               ELSE NOW() + (ARRAY['15 minutes','1 hour'])[tentativas + 1]::interval END
   WHERE id = p_id
   RETURNING processo_codigo, tentativas INTO v_processo, v_tentativas;
   -- RETURNING devolve o valor JÁ incrementado (tentativas = tentativas + 1 no SET acima) —
   -- v_tentativas >= 3 é equivalente a "essa foi a última tentativa" (mesma condição do CASE acima).

  IF v_processo IS NOT NULL AND p_raia IS NOT NULL THEN
    INSERT INTO crawler_execucoes_log (job_id, processo_codigo, raia, resultado, erro_categoria, terminal)
    VALUES (p_id, v_processo, p_raia, 'erro', p_categoria, v_tentativas >= 3);
    DELETE FROM crawler_execucoes_log WHERE criado_em < now() - interval '3 days';
  END IF;
END; $$;

REVOKE ALL ON FUNCTION public.fail_crawler_job(uuid, text, text, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fail_crawler_job(uuid, text, text, integer) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
