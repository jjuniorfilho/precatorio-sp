-- FOR-200 (3 de 3) — RPCs de leitura pra /admin/coleta/graficos (aba "Ao vivo"). Admin roda
-- anônimo — leitura só via RPC SECURITY DEFINER (padrão "admin-anon-rpc" já usado em
-- sql/2026-07-24_for108_observabilidade_coleta_rpcs.sql e
-- sql/2026-09-25_for171_3_rpc_listar_consultas_pagamento.sql).
--
-- Nenhuma RPC/tabela existente é alterada por este arquivo — tudo aditivo. Ver
-- .claude/sessions/for-200-graficos-coleta/architecture.md pro racional de cada uma (em
-- particular por que "fila pendente" não precisa de snapshot periódico e por que "execuções
-- por hora" é uma RPC nova em vez de estender crawler_ritmo_processamento, que o /admin/coleta
-- atual já consome).
--
-- Depende dos arquivos 1/3 e 2/3 (crawler_execucoes_log precisa existir e estar sendo
-- populada). Re-executável.

-- 1) Feed "Crawler e-SAJ" (p_depre=false) / "Consulta DEPRE (.0500)" (p_depre=true).
-- Mesmo regex que isDepre() usa no worker (worker-crawler/src/esaj.ts:72).
CREATE OR REPLACE FUNCTION public.crawler_execucoes_recentes(p_depre boolean, p_limit integer DEFAULT 14)
RETURNS TABLE(criado_em timestamptz, processo_codigo text, raia integer, resultado text, erro_categoria text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT criado_em, processo_codigo, raia::integer, resultado, erro_categoria
    FROM crawler_execucoes_log
   WHERE (processo_codigo ~ '\.8\.26\.0500$') = p_depre
   ORDER BY criado_em DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 14), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.crawler_execucoes_recentes(boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crawler_execucoes_recentes(boolean, integer) TO anon, authenticated, service_role;

-- 2) Feed "Consulta de pagamento TJSP" — versão global (não por-processo) de
-- listar_consultas_pagamento (sql/2026-09-25_for171_3_...), sem mudar a tabela/RPC existente.
CREATE OR REPLACE FUNCTION public.pagamentos_consultas_recentes(p_limit integer DEFAULT 14)
RETURNS TABLE(criado_em timestamptz, processo_depre text, resultado text, erro_categoria text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT criado_em, processo_depre, resultado, erro_categoria
    FROM pagamentos_consultas_log
   ORDER BY criado_em DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 14), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.pagamentos_consultas_recentes(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pagamentos_consultas_recentes(integer) TO anon, authenticated, service_role;

-- 3) "Execuções por hora" (24 barras sucesso/erro). status IN ('ok','erro') é estado TERMINAL
-- em crawler_queue (updated_at não muda mais depois de alcançado, exceto por requeue_failed,
-- ação manual admin que tira a linha de 'erro' — correto: reprocessada manualmente, ela sai do
-- histórico de erro antigo). RPC nova — não altera crawler_ritmo_processamento (consumida hoje
-- por /admin/coleta "Visão geral").
CREATE OR REPLACE FUNCTION public.crawler_execucoes_por_hora()
RETURNS TABLE(hora timestamptz, n_ok bigint, n_erro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT date_trunc('hour', updated_at) AS hora,
         count(*) FILTER (WHERE status = 'ok')   AS n_ok,
         count(*) FILTER (WHERE status = 'erro') AS n_erro
    FROM crawler_queue
   WHERE status IN ('ok', 'erro') AND updated_at >= now() - interval '24 hours'
   GROUP BY 1
   ORDER BY 1;
$$;

REVOKE ALL ON FUNCTION public.crawler_execucoes_por_hora() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crawler_execucoes_por_hora() TO anon, authenticated, service_role;

-- 4) "Fila pendente" (tendência 24h). Reconstrução SEM snapshot periódico: um job está "na
-- fila" no instante `t` se created_at <= t E (ainda não é terminal agora OU só ficou terminal
-- depois de t). Ver architecture.md pra limitação documentada (retentativas contam como "na
-- fila" o tempo todo até a resolução final — correto, pois de fato nunca saíram da fila).
--
-- Série ancorada em NOW() (não em date_trunc('hour', now())): o último ponto tem que
-- representar o pendente REAL agora, não o pendente-como-estava-no-início-da-hora-corrente —
-- senão um job criado nos últimos minutos da hora ficaria fora da contagem do ponto "agora"
-- (`created_at <= h.hora` falharia pro próprio instante presente). 24 pontos, 1h de espaçamento,
-- do mesmo jeito que o protótipo rotula as pontas ("24h atrás"/"agora").
CREATE OR REPLACE FUNCTION public.crawler_fila_pendente_tendencia()
RETURNS TABLE(hora timestamptz, pendentes bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT h.hora,
         (SELECT count(*) FROM crawler_queue q
           WHERE q.created_at <= h.hora
             AND (q.status IN ('pendente', 'processando') OR q.updated_at > h.hora)
         ) AS pendentes
    FROM generate_series(now() - interval '23 hours', now(), interval '1 hour') AS h(hora)
   ORDER BY h.hora;
$$;

REVOKE ALL ON FUNCTION public.crawler_fila_pendente_tendencia() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crawler_fila_pendente_tendencia() TO anon, authenticated, service_role;

-- 5) "Erros por categoria (24h)" — combina as duas fontes que já têm erro_categoria (FOR-198).
CREATE OR REPLACE FUNCTION public.erros_por_categoria_24h()
RETURNS TABLE(categoria text, n bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH tudo AS (
    SELECT erro_categoria FROM crawler_queue
     WHERE status = 'erro' AND erro_categoria IS NOT NULL AND updated_at >= now() - interval '24 hours'
    UNION ALL
    SELECT erro_categoria FROM pagamentos_consultas_log
     WHERE resultado = 'falha' AND erro_categoria IS NOT NULL AND criado_em >= now() - interval '24 hours'
  )
  SELECT erro_categoria, count(*) FROM tudo GROUP BY 1 ORDER BY count(*) DESC;
$$;

REVOKE ALL ON FUNCTION public.erros_por_categoria_24h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erros_por_categoria_24h() TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
