-- =============================================================
-- FIX — índice único órfão em djen_dias bloqueia dados federais
-- Descoberto 2026-09-06 durante o backfill da FOR-145 (Fase 5): a migration
-- do schema federal (sql/2026-09-06_for145_schema_federal.sql) trocou a
-- PRIMARY KEY de djen_dias de (data) para (data, tribunal) — mas um índice
-- único SEPARADO e pré-existente, `djen_dias_data_uidx` (não era a PK,
-- criado independentemente em algum momento anterior, fora do controle
-- desta migration), continuou vigente e ainda impõe unicidade só por
-- `data`. Resultado: qualquer dia federal (TRF1-6) cuja data já tenha uma
-- linha do TJSP colide com esse índice órfão e falha com
-- "duplicate key value violates unique constraint djen_dias_data_uidx"
-- — silenciosamente, porque o upsert não checava erro (corrigido em
-- ingest-djen-federal.ts na mesma sessão).
--
-- Rodar no SQL Editor (padrão do projeto). Re-executável.
-- =============================================================

DROP INDEX IF EXISTS djen_dias_data_uidx;

-- Sanity check pós-fix (rodar manualmente e conferir que só a PK composta
-- aparece, sem nenhum índice único extra em "data" isolado):
-- select indexname, indexdef from pg_indexes where tablename = 'djen_dias';
