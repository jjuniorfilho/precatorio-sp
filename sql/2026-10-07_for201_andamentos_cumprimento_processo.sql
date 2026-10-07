-- FOR-201 — Colunas novas pra parar de descartar os andamentos próprios de
-- CUMPRIMENTO e PROCESSO (raiz) quando eles têm incidentes-filho reais.
--
-- Contexto: hoje só INCIDENTE (tabela `andamentos`, FK incidente_id NOT NULL) e
-- .0500/DEPRE (`djen_depre.andamentos` jsonb) têm movimentações persistidas.
-- `crawl.ts` já busca a página do cumprimento e já tem a página raiz carregada em
-- memória (normalizeToRoot) em TODO crawl — só não chama extractAndamentos() nelas
-- quando existe incidente-filho real. O dado está na resposta HTTP, mas é descartado.
--
-- Decisão de modelagem: jsonb direto nas tabelas `processos`/`cumprimentos`, mesmo
-- idioma já usado em `djen_depre.andamentos` — não uma FK nova na tabela relacional
-- `andamentos` (21,7M linhas, incidente_id NOT NULL hoje). Motivo: zero alteração
-- estrutural numa tabela gigante já sob escrita contínua do crawler em produção; é
-- só mais 1 coluna no upsert que `persistTree` já faz pra `processos`/`cumprimentos`.
--
-- Semântica (mesmo padrão de `djen_depre.acordo_homologado`):
--   NULL  = nunca persistido por essa via (linha pré-existente, ou ainda não
--           recrawleada com o código do FOR-201).
--   '[]'  = já verificado nesse último crawl, página sem nenhum andamento.
--   array = já verificado, com andamentos.
--
-- Aplicar no SQL Editor. Só schema — não muda nenhuma função, não dispara recrawl.
-- O código que passa a popular essas colunas (worker-crawler/src/crawl.ts +
-- supabase.ts) deve ser deployado JUNTO ou DEPOIS deste script (nunca antes —
-- senão o worker tentaria gravar numa coluna que ainda não existe e o upsert falha).

alter table processos
  add column if not exists andamentos jsonb;

alter table cumprimentos
  add column if not exists andamentos jsonb;

comment on column processos.andamentos is
  'FOR-201: andamentos da própria página do processo raiz (e-SAJ). NULL = nunca '
  'persistido por essa via. Complementar a incidentes.andamentos (tabela andamentos) '
  'e djen_depre.andamentos — não duplica, cobre o nível que nenhum dos outros dois cobre.';

comment on column cumprimentos.andamentos is
  'FOR-201: andamentos da própria página do cumprimento de sentença (e-SAJ). NULL = '
  'nunca persistido por essa via. Complementar a incidentes.andamentos e '
  'djen_depre.andamentos.';

-- Validação (rodar após aplicar):
-- select count(*) from processos where andamentos is not null;    -- esperado: 0 (migration recém aplicada)
-- select count(*) from cumprimentos where andamentos is not null; -- esperado: 0 (idem)
-- Depois do deploy do worker + alguns crawls reais, as duas contagens devem subir.
