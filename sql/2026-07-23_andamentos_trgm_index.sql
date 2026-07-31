-- FOR-72 (revisão, fix) — 19 processos "mega" (769 a 8.513 incidentes cada, somando
-- 50.382 incidentes / ~16,5% da tabela) estouram statement timeout ao rodar
-- classify_processo, mesmo tentando um por vez. Causa: o LEFT JOIN de andamentos com
-- classificacao_regras avalia ILIKE '%padrão%' sem nenhum índice de busca textual —
-- custo escala com incidentes × andamentos × regras. Índice trigram (pg_trgm) deixa o
-- planner usar bitmap index scan pro ILIKE em vez de avaliar cada linha.
--
-- Sem CONCURRENTLY (SQL Editor do Lovable roda em transação — mesma limitação já vista
-- na migration de índices da FOR-104). Pode demorar um pouco pra criar (tabela grande) e
-- trava escrita em andamentos durante a criação — aceitável, não é o caminho crítico de
-- nenhuma busca pública. Aplicar no SQL Editor.

CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE INDEX IF NOT EXISTS idx_andamentos_descricao_trgm
  ON andamentos USING gin (descricao gin_trgm_ops);
