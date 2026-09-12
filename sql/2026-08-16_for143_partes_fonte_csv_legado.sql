-- FOR-143 — Import do CSV legado de precatórios (script one-off em
-- worker-crawler/src/import-csv-legado.ts) grava linhas em `partes` sem passar pelo crawler
-- (e-SAJ) nem pela ingestão DJEN — precisa de um valor próprio em `fonte` pra distinguir esses
-- registros dos crawleados de verdade. Hoje o CHECK só aceita 'esaj'/'djen'.
--
-- Re-executável (DROP IF EXISTS antes do ADD). Aplicar no SQL Editor.

alter table public.partes drop constraint if exists partes_fonte_check;
alter table public.partes add constraint partes_fonte_check
  check (fonte in ('esaj', 'djen', 'csv_legado'));

-- Verificação (rodar manualmente após aplicar):
-- select conname, pg_get_constraintdef(oid) from pg_constraint
--  where conrelid = 'public.partes'::regclass and conname = 'partes_fonte_check';
-- -- esperado: CHECK (fonte = ANY (ARRAY['esaj'::text, 'djen'::text, 'csv_legado'::text]))
--
-- insert into partes (incidente_id, processo_id, papel, nome, fonte)
--   select id, processo_id, 'passiva', 'teste_for143', 'csv_legado' from incidentes limit 1
--   returning id; -- deve inserir sem erro
-- delete from partes where nome = 'teste_for143'; -- limpar o teste
