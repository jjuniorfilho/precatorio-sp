-- FOR-196: backfill do CNJ em branco nos "cumprimentos sintéticos" (execução correndo direto
-- no próprio processo, sem CNJ de cumprimento separado — worker-crawler/src/crawl.ts linhas
-- 137-160). O crawler gravava `cnj: null` nesses casos em vez do CNJ da própria raiz, deixando
-- o campo "Cumprimento de Sentença" em branco em 347.482 incidentes (quase metade da base de
-- ~761k). Confirmado seguro (read-only, antes de aplicar):
--
--   select
--     (select count(*) from cumprimentos) as total_cumprimentos,              -- 298.691
--     (select count(*) from cumprimentos where cnj is null) as sinteticos,    -- 126.388
--     (select count(*) from incidentes i join cumprimentos c on c.id = i.cumprimento_id
--        where c.cnj is null) as incidentes_afetados;                        -- 347.482
--
-- 0 desses 126.388 cumprimentos sintéticos pertence a um processo LEGADO- (processo_codigo
-- like 'LEGADO-%') — ou seja, `processos.cnj` é sempre o CNJ confiável de uma raiz já
-- crawleada normalmente (resolvida por normalizeToRoot). Não precisa de recrawl nenhum.
--
-- Validado localmente (Postgres descartável, schema sintético réplica mínima de processos/
-- cumprimentos/incidentes) em sql/sandbox/for196_validate_local.sh — confirma que o UPDATE
-- preenche só os NULL (idempotente: rodar 2x não altera nada na 2ª rodada) e não toca
-- cumprimentos que já têm cnj preenchido.
--
-- Aplicar no SQL Editor. Complementa (não substitui) o fix de código em crawl.ts (linhas 141 e
-- 148-149: `cnj: null` → `cnj: capa.cnj`), que evita que novos crawls nasçam com o mesmo bug.

update cumprimentos c
   set cnj = p.cnj
  from incidentes i
  join processos p on p.id = i.processo_id
 where i.cumprimento_id = c.id
   and c.cnj is null;
