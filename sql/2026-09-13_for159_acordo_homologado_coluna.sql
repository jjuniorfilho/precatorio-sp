-- FOR-159 — Coluna consultável pra "acordo homologado" no requisitório .0500.
--
-- Causa raiz: a ficha do .0500 no e-SAJ tem duas tabelas de andamento —
-- "Movimentação" (#tabelaTodasMovimentacoes, já extraída) e "Petições diversas"
-- (sem id, só identificável pelo <h2> que a antecede), onde vive o tipo
-- "Comunicado de Acordo de Requisitório". O crawler nunca lia a segunda tabela —
-- corrigido no commit 2f36e91 (worker-crawler/src/parse.ts:extractPeticoesDiversas
-- + crawl.ts:crawlRequisitorio), já deployado na VPS. Esta migration expõe o
-- resultado como coluna, em vez de exigir jsonb_array_elements toda consulta.
--
-- Nullable de propósito (SEM "default false"): null = ainda não verificado com o
-- parser novo; true/false = resultado real pós re-crawl. Sem essa distinção, todo
-- .0500 ainda não recrawleado apareceria como "false" por falta de dado, não
-- porque de fato não teve acordo — o mesmo tipo de falso-negativo que motivou essa
-- issue (ver sql/2026-09-13_diag_acordo_depre.sql, a versão anterior que sempre
-- retornava false por ler a tabela errada).
--
-- Aplicar no SQL Editor.

alter table djen_depre
  add column if not exists acordo_homologado boolean;

comment on column djen_depre.acordo_homologado is
  'true/false = verificado (tem ou não o andamento "Comunicado de Acordo de '
  'Requisitório" na tabela Petições diversas do e-SAJ); null = ainda não '
  'recrawleado com o parser que le essa tabela (ver FOR-159).';

-- Backfill imediato: só cobre quem JÁ foi (re)crawleado com o parser novo hoje
-- (ficha_crawled_at >= o dia do deploy) — não precisa de novo crawl pra esses.
-- O resto da base fica null até sql/2026-09-13_for159_enfileira_backfill_restante.sql
-- rodar e a fila processar (ver FASE 3 do plano).
update djen_depre
   set acordo_homologado = exists (
         select 1
           from jsonb_array_elements(coalesce(andamentos, '[]'::jsonb)) elem
          where btrim(elem->>'descricao') ilike 'Comunicado de Acordo de Requisit%'
       )
 where ficha_crawled_at >= '2026-09-13'::date
   and acordo_homologado is null;

-- Verificação (rodar após aplicar):
-- select cnj, acordo_homologado, ficha_crawled_at from djen_depre
--  where cnj_normalizado = '01804644220218260500';
-- -- esperado: acordo_homologado = true (0180464-42.2021.8.26.0500, exemplo
-- -- confirmado pelo usuário via e-SAJ)
--
-- select acordo_homologado is null as pendente, count(*) from djen_depre group by 1;
-- -- mede quantos já foram cobertos pelo backfill imediato vs. quantos dependem
-- -- do backfill de fila (FASE 3)
