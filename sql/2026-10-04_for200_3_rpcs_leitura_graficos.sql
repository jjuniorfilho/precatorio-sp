-- FOR-200 (3 de 3) — RPCs de leitura pra /admin/coleta/graficos (aba "Ao vivo"). Admin roda
-- anônimo — leitura só via RPC SECURITY DEFINER (padrão "admin-anon-rpc" já usado em
-- sql/2026-07-24_for108_observabilidade_coleta_rpcs.sql e
-- sql/2026-09-25_for171_3_rpc_listar_consultas_pagamento.sql).
--
-- Nenhuma RPC/tabela existente é alterada por este arquivo — tudo aditivo. Ver
-- .claude/sessions/for-200-graficos-coleta/architecture.md pro racional de cada uma.
--
-- Depende dos arquivos 1/3 e 2/3 (crawler_execucoes_log precisa existir e estar sendo
-- populada). Re-executável.
--
-- ACHADOS DE CODE REVIEW (2 revisões independentes, cortex-v1 + 1 revisão frontend) aplicados
-- nesta versão, versus a 1ª escrita:
--
-- M2/M5: `crawler_fila_pendente_tendencia` fazia 24 subqueries CORRELACIONADAS sobre
-- `crawler_queue` inteira, com um OR entre predicados de colunas diferentes
-- (`created_at <= h AND (status IN (...) OR updated_at > h)`) — não-sargável, mesma classe de
-- problema já documentada no projeto (FOR-189/194, OR entre dois predicados nunca vira um plano
-- bom). Reescrita abaixo como 1 CTE ("candidatos": linhas ainda abertas OU resolvidas nas
-- últimas 24h) cruzado com os 24 buckets — 1 scan da tabela em vez de 24. Os 2 índices parciais
-- novos cobrem exatamente os dois ramos do OR (cada um vira um bitmap scan barato).
--
-- M3: `crawler_execucoes_por_hora`/`erros_por_categoria_24h` contavam, do lado crawler, só
-- falhas TERMINAIS em `crawler_queue` (1 por job — uma retentativa com captcha/rate_limit que
-- depois deu certo nunca aparecia). Isso divergia do feed (`crawler_execucoes_recentes`, que é
-- por TENTATIVA) e do lado pagamentos de `erros_por_categoria_24h` (que já conta por tentativa).
-- As duas agora leem `crawler_execucoes_log` (por tentativa, igual ao feed e aos pagamentos) —
-- resolve a inconsistência E a performance (tabela pequena, já indexada por `criado_em`,
-- retenção de 3 dias cobre a janela de 24h com folga). `crawler_fila_pendente_tendencia`
-- continua lendo `crawler_queue` DIRETO: profundidade de fila é sobre o estado ATUAL da fila,
-- não dá pra derivar só do log de tentativas.
--
-- L7: `crawler_execucoes_recentes(NULL, ...)` resolvia vazio (`= NULL` nunca casa em SQL) —
-- sem impacto real (frontend sempre manda true/false), mas documentado aqui por transparência;
-- não exigido NOT NULL pra não quebrar um chamador futuro que explicitamente queira "todos".
--
-- L10 (frontend): os feeds agora retornam `id` (chave estável pro React, sobrevive a reordenação
-- durante o poll — antes a key era `${criado_em}-${indice}`, que remonta linhas a cada 5s).
--
-- MEDIUM 6 (frontend): `pagamentos_consultas_recentes` filtra `origem = 'crawler'` — o card
-- "Consulta de pagamento (TJSP)" é especificamente sobre o ROBÔ; consultas manuais/busca pública
-- não são execução do robô e não deveriam aparecer como "erro do robô".
--
-- MEDIUM 2 (frontend): nova RPC `coleta_runs_ultima_por_padrao` — substitui o filtro client-side
-- por prefixo sobre uma lista capada em 50 linhas (que podia nunca incluir uma rotina rara, ex.
-- ingest_oab). Filtra no banco com LIKE, sempre pega a execução mais recente de verdade.

-- ---- índices de suporte (M2/M5) -----------------------------------------------------------
-- Parcial = só indexa o ramo relevante de cada predicado do OR que a tendência de fila usa;
-- tabelas pequenas (só linhas "abertas" de um lado, só as last 24h resolvidas do outro).
CREATE INDEX IF NOT EXISTS idx_crawler_queue_created_ativo
  ON public.crawler_queue (created_at) WHERE status IN ('pendente', 'processando');
CREATE INDEX IF NOT EXISTS idx_crawler_queue_updated_terminal
  ON public.crawler_queue (updated_at) WHERE status IN ('ok', 'erro');
-- Suporta pagamentos_consultas_recentes (ORDER BY criado_em DESC, chamada a cada 5s) e o lado
-- pagamentos de erros_por_categoria_24h (filtro por criado_em) — tabela só tinha índice em
-- (processo_depre, iniciada_em), nenhum cobrindo criado_em (achado de code review, frontend M5).
CREATE INDEX IF NOT EXISTS idx_pagamentos_consultas_log_criado_em
  ON public.pagamentos_consultas_log (criado_em DESC);

-- 1) Feed "Crawler e-SAJ" (p_depre=false) / "Consulta DEPRE (.0500)" (p_depre=true).
-- Mesmo regex que isDepre() usa no worker (worker-crawler/src/esaj.ts:72).
CREATE OR REPLACE FUNCTION public.crawler_execucoes_recentes(p_depre boolean, p_limit integer DEFAULT 14)
RETURNS TABLE(id uuid, criado_em timestamptz, processo_codigo text, raia integer, resultado text, erro_categoria text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id, criado_em, processo_codigo, raia::integer, resultado, erro_categoria
    FROM crawler_execucoes_log
   WHERE (processo_codigo ~ '\.8\.26\.0500$') = p_depre
   ORDER BY criado_em DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 14), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.crawler_execucoes_recentes(boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crawler_execucoes_recentes(boolean, integer) TO anon, authenticated, service_role;

-- 2) Feed "Consulta de pagamento TJSP" — versão global (não por-processo) de
-- listar_consultas_pagamento (sql/2026-09-25_for171_3_...), sem mudar a tabela/RPC existente.
-- Só origem='crawler': manual/busca_publica não são execução do robô (achado de code review).
CREATE OR REPLACE FUNCTION public.pagamentos_consultas_recentes(p_limit integer DEFAULT 14)
RETURNS TABLE(id uuid, criado_em timestamptz, processo_depre text, resultado text, erro_categoria text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id, criado_em, processo_depre, resultado, erro_categoria
    FROM pagamentos_consultas_log
   WHERE origem = 'crawler'
   ORDER BY criado_em DESC
   LIMIT LEAST(GREATEST(COALESCE(p_limit, 14), 1), 50);
$$;

REVOKE ALL ON FUNCTION public.pagamentos_consultas_recentes(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pagamentos_consultas_recentes(integer) TO anon, authenticated, service_role;

-- 3) "Execuções por hora" (24 barras sucesso/erro), por TENTATIVA (crawler_execucoes_log) —
-- não por falha terminal (ver nota M3 no topo do arquivo). generate_series + LEFT JOIN garante
-- as 24 horas mesmo sem dado (hora ociosa vira 0/0 em vez de sumir do eixo — achado LOW 9).
CREATE OR REPLACE FUNCTION public.crawler_execucoes_por_hora()
RETURNS TABLE(hora timestamptz, n_ok bigint, n_erro bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH horas AS (
    SELECT h AS hora FROM generate_series(
      date_trunc('hour', now() - interval '23 hours'), date_trunc('hour', now()), interval '1 hour'
    ) AS h
  )
  SELECT horas.hora,
         COALESCE(count(l.*) FILTER (WHERE l.resultado = 'ok'), 0)   AS n_ok,
         COALESCE(count(l.*) FILTER (WHERE l.resultado = 'erro'), 0) AS n_erro
    FROM horas
    LEFT JOIN crawler_execucoes_log l
      ON date_trunc('hour', l.criado_em) = horas.hora AND l.criado_em >= now() - interval '24 hours'
   GROUP BY horas.hora
   ORDER BY horas.hora;
$$;

REVOKE ALL ON FUNCTION public.crawler_execucoes_por_hora() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crawler_execucoes_por_hora() TO anon, authenticated, service_role;

-- 4) "Fila pendente" (tendência 24h), lida DIRETO de crawler_queue (profundidade de fila é
-- sobre o estado atual, não dá pra derivar só do log de tentativas). Reconstrução SEM snapshot
-- periódico: um job está "na fila" no instante `t` se created_at <= t E (ainda não é terminal
-- agora OU só ficou terminal depois de t). Ver architecture.md pra limitações documentadas
-- (retentativas contam como "na fila" o tempo todo até a resolução final — correto, pois de
-- fato nunca saíram da fila; um job reprocessado via requeue_failed conta como pendente também
-- no período em que esteve em erro — leve superestimativa, aceitável).
--
-- Reescrita em 1 CTE (candidatos) + CROSS JOIN com os 24 buckets, em vez de 24 subqueries
-- correlacionadas sobre a tabela inteira (achado de code review M2: o WHERE original não era
-- sargável — OR entre status e updated_at — e rodava ~24 seq scans por chamada; aqui os 2
-- índices parciais acima cobrem os dois ramos do OR em candidatos, que fica pequeno — só linhas
-- ainda abertas + resolvidas nas últimas 24h — e os 24 buckets só casam contra esse recorte).
--
-- Série ancorada em NOW() (não em date_trunc('hour', now())): o último ponto tem que
-- representar o pendente REAL agora — senão um job criado nos últimos minutos da hora ficaria
-- fora da contagem do ponto "agora". 24 pontos, 1h de espaçamento.
CREATE OR REPLACE FUNCTION public.crawler_fila_pendente_tendencia()
RETURNS TABLE(hora timestamptz, pendentes bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH candidatos AS (
    SELECT created_at,
           CASE WHEN status IN ('ok', 'erro') THEN updated_at ELSE NULL END AS resolvido_em
      FROM crawler_queue
     WHERE status IN ('pendente', 'processando') OR updated_at > now() - interval '24 hours'
  ),
  horas AS (
    SELECT h AS hora FROM generate_series(now() - interval '23 hours', now(), interval '1 hour') AS h
  )
  SELECT horas.hora,
         count(*) FILTER (
           WHERE candidatos.created_at <= horas.hora
             AND (candidatos.resolvido_em IS NULL OR candidatos.resolvido_em > horas.hora)
         ) AS pendentes
    FROM horas
    CROSS JOIN candidatos
   GROUP BY horas.hora
   ORDER BY horas.hora;
$$;

REVOKE ALL ON FUNCTION public.crawler_fila_pendente_tendencia() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.crawler_fila_pendente_tendencia() TO anon, authenticated, service_role;

-- 5) "Erros por categoria (24h)" — combina crawler_execucoes_log (por tentativa, não só
-- terminal — ver nota M3 no topo) + pagamentos_consultas_log (já era por tentativa).
CREATE OR REPLACE FUNCTION public.erros_por_categoria_24h()
RETURNS TABLE(categoria text, n bigint)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH tudo AS (
    SELECT erro_categoria FROM crawler_execucoes_log
     WHERE resultado = 'erro' AND erro_categoria IS NOT NULL AND criado_em >= now() - interval '24 hours'
    UNION ALL
    SELECT erro_categoria FROM pagamentos_consultas_log
     WHERE resultado = 'falha' AND erro_categoria IS NOT NULL AND criado_em >= now() - interval '24 hours'
  )
  SELECT erro_categoria, count(*) FROM tudo GROUP BY 1 ORDER BY count(*) DESC;
$$;

REVOKE ALL ON FUNCTION public.erros_por_categoria_24h() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.erros_por_categoria_24h() TO anon, authenticated, service_role;

-- 6) Última execução por PADRÃO de rotina (robôs periódicos cuja rotina varia: Ingestão DJE
-- Federal = `caderno_djen_trf1..6`, Ingestão por OAB = `ingest_oab`/`ingest_oab_cpopg`).
-- `coleta_runs_recentes` (FOR-108) não filtra por prefixo — buscar sem filtro e cortar em
-- client-side num LIMIT fixo arriscava nunca incluir uma rotina rara (achado de code review,
-- frontend M2: Ingestão por OAB roda sob demanda, podia cair fora de uma janela de 50 linhas).
-- `p_padrao` é o padrão LIKE completo (ex. 'caderno_djen_%', 'ingest_oab%') — SECURITY DEFINER
-- + STABLE, sem concatenação de SQL dinâmico (LIKE é parametrizado normalmente, sem injeção).
CREATE OR REPLACE FUNCTION public.coleta_runs_ultima_por_padrao(p_padrao text)
RETURNS TABLE(
  id uuid, rotina text, started_at timestamptz, finished_at timestamptz,
  status text, itens_ok integer, itens_erro integer, duracao_ms integer, detalhe jsonb)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id, rotina, started_at, finished_at, status, itens_ok, itens_erro, duracao_ms, detalhe
    FROM coleta_runs
   WHERE rotina LIKE p_padrao
   ORDER BY started_at DESC
   LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.coleta_runs_ultima_por_padrao(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.coleta_runs_ultima_por_padrao(text) TO anon, authenticated, service_role;

NOTIFY pgrst, 'reload schema';
