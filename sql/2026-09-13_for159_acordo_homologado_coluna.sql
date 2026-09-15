-- FOR-159 — Coluna consultável pra "acordo homologado" no requisitório .0500.
--
-- Causa raiz: a ficha do .0500 no e-SAJ tem duas tabelas de andamento —
-- "Movimentação" (#tabelaTodasMovimentacoes, já extraída) e "Petições diversas"
-- (sem id, só identificável pelo <h2> que a antecede), onde vive o tipo
-- "Comunicado de Acordo de Requisitório". O crawler nunca lia a segunda tabela —
-- corrigido no commit 2f36e91 (worker-crawler/src/parse.ts:extractPeticoesDiversas
-- + crawl.ts:crawlRequisitorio). Esta migration expõe o resultado como coluna, em
-- vez de exigir jsonb_array_elements toda consulta.
--
-- Nullable de propósito (SEM "default false"): null = ainda não verificado com o
-- parser novo; true/false = resultado real pós re-crawl. Sem essa distinção, todo
-- .0500 ainda não recrawleado apareceria como "false" por falta de dado, não
-- porque de fato não teve acordo — o mesmo tipo de falso-negativo que motivou essa
-- issue.
--
-- Aplicar no SQL Editor.

alter table djen_depre
  add column if not exists acordo_homologado boolean;

comment on column djen_depre.acordo_homologado is
  'true/false = verificado (tem ou não o andamento "Comunicado de Acordo de Requisitório" na tabela Petições diversas do e-SAJ); null = ainda não recrawleado com o parser que lê essa tabela (ver FOR-159).';

-- Backfill / correção: o deploy do parser novo na VPS (pm2 precatorio-crawler)
-- terminou às 2026-09-13T17:09:48.860Z (confirmado via `pm2 jlist` -> pm_uptime,
-- restart_time=1). Fichas com `ficha_crawled_at` ANTES desse instante — mesmo que
-- no mesmo dia — foram lidas com o parser ANTIGO e não podem ser tratadas como
-- "verificadas": ficam explicitamente `null`. Fichas a partir desse instante
-- refletem o parser novo e são recalculadas de verdade.
--
-- Reexecutável mesmo já tendo rodado antes com um corte por DATA (meia-noite UTC,
-- não a hora real do deploy): este UPDATE cobre tanto quem ficou null quanto quem
-- foi marcado errado por engano naquela primeira versão (sem o "and
-- acordo_homologado is null" do rascunho anterior) — reprocessa todo mundo
-- crawleado hoje, o que é barato (poucas linhas) e sempre idempotente.
--
-- CASE sequencial (não AND dentro do mesmo WHEN): jsonb_array_elements() roda no
-- FROM da subquery, então precisa ser alcançado só depois de confirmado que
-- `andamentos` é array de fato — senão quebra o UPDATE inteiro num registro legado
-- com formato inesperado, mesmo com o guard escrito (Postgres não filtra o FROM
-- pelo WHERE antes de avaliar a função). CASE WHEN é curto-circuitado de verdade:
-- só a branch que casar é avaliada.
update djen_depre
   set acordo_homologado = case
         when ficha_crawled_at < timestamptz '2026-09-13T17:09:48.860Z' then null
         when jsonb_typeof(andamentos) is distinct from 'array' then false
         else exists (
           select 1
             from jsonb_array_elements(andamentos) elem
            where elem->>'descricao' ilike '%Comunicado de Acordo de Requisit%'
         )
       end
 where ficha_crawled_at >= '2026-09-13'::date;

-- Verificação (rodar após aplicar):
-- select cnj, acordo_homologado, ficha_crawled_at from djen_depre
--  where cnj_normalizado = '01804644220218260500';
-- -- esperado: acordo_homologado = true (0180464-42.2021.8.26.0500, exemplo
-- -- confirmado pelo usuário via e-SAJ)
--
-- select acordo_homologado is null as pendente, count(*) from djen_depre group by 1;
-- -- mede quantos já foram cobertos pelo backfill imediato vs. quantos dependem
-- -- do backfill de fila (FASE 3) — deve ser MAIOR que antes da correção, já que
-- -- fichas crawleadas hoje antes de 17:09:48 UTC voltam pra null.
