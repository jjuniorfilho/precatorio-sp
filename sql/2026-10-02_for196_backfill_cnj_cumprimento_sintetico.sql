-- FOR-196: backfill do CNJ em branco nos "cumprimentos sintéticos" (execução correndo direto
-- no próprio processo, sem CNJ de cumprimento separado — worker-crawler/src/crawl.ts, função
-- `crawlSeed`, ramificações que criam `processo_codigo: "{root}#cumprimento"`). O crawler
-- gravava `cnj: null` nesses casos em vez do CNJ da própria raiz, deixando o campo
-- "Cumprimento de Sentença" em branco em ~347k incidentes (quase metade da base de ~761k).
--
-- IMPORTANTE — ordem de deploy: aplicar DEPOIS do deploy do worker com o fix de crawl.ts (pm2
-- restart na VPS). Enquanto o worker antigo ainda roda, cada recrawl de uma dessas árvores
-- sobrescreve `cumprimentos.cnj` de volta pra null (o upsert não faz COALESCE) — rodar o
-- backfill antes do deploy do worker deixaria o valor alternando a cada recrawl.
--
-- Achado em produção (read-only, antes de aplicar):
--
--   select
--     (select count(*) from cumprimentos) as total_cumprimentos,              -- 298.691
--     (select count(*) from cumprimentos where cnj is null) as nulos,         -- 126.388
--     (select count(*) from incidentes i join cumprimentos c on c.id = i.cumprimento_id
--        where c.cnj is null) as incidentes_afetados;                        -- 347.482
--
-- Achado do code review (pre-pr): nem todo `cumprimentos.cnj is null` é um sintético — um
-- cumprimento "de verdade" (`processo_codigo` SEM o sufixo `#cumprimento`) também pode ter
-- `cnj` null quando `extractCnj(c.texto)` não acha o número no texto do link (crawl.ts:134).
-- Pra esse caso o CNJ da raiz estaria ERRADO (é um cumprimento diferente, só sem CNJ
-- reconhecido). Por isso o WHERE abaixo restringe ao sufixo `#cumprimento`, que só existe nas
-- 2 ramificações do bug (nunca em cumprimento "de verdade" nem em `#requisitorio`). Rodar antes,
-- só leitura, pra conferir que a restrição não deixa nada sintético de fora:
--
--   select count(*) from cumprimentos
--    where cnj is null and processo_codigo not like '%#cumprimento';          -- deve ser > 0
--                                                                             -- (os "de verdade")
--
-- 0 desses cumprimentos sintéticos pertence a um processo LEGADO- (`processos.processo_codigo
-- like 'LEGADO-%'`) — ou seja, `processos.cnj`/`cnj_normalizado` são sempre o valor confiável de
-- uma raiz já crawleada normalmente (resolvida por `normalizeToRoot`). Não precisa de recrawl.
--
-- Grava `cnj_normalizado` junto com `cnj` (mesmo par que o worker grava, supabase.ts:240-241 —
-- sem isso 126k linhas ficariam com `cnj` preenchido mas `cnj_normalizado` null até o próximo
-- recrawl, inconsistente com o resto da tabela). Usa `c.processo_id` (FK direta) em vez de
-- passar por `incidentes`: evita múltiplas linhas candidatas por cumprimento num `UPDATE ...
-- FROM` (um cumprimento sintético pode ter vários incidentes pendurados) e cobre também o caso
-- raro de cumprimento sintético sem nenhum incidente (raiz sem nada, placeholder).
--
-- Validado localmente (Postgres descartável, schema sintético réplica mínima de processos/
-- cumprimentos/incidentes) em sql/sandbox/for196_validate_local.sh — confirma que o UPDATE
-- preenche só os sintéticos com cnj null, preserva cumprimento "de verdade" com cnj null
-- intocado, preserva cnj já preenchido, e é idempotente (rodar 2x não altera nada na 2ª vez).
--
-- Complementa (não substitui) o fix de código em crawl.ts (`cnj: null` → `cnj: capa.cnj` nas 2
-- ramificações que criam o cumprimento sintético), que evita que novos crawls nasçam com o
-- mesmo bug.
--
-- Aplicar no SQL Editor.

update cumprimentos c
   set cnj = p.cnj,
       cnj_normalizado = p.cnj_normalizado
  from processos p
 where p.id = c.processo_id
   and c.cnj is null
   and c.processo_codigo like '%#cumprimento';
