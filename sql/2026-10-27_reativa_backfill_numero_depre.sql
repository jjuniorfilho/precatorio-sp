-- Reativa o backfill de numero_depre (cron jobid 17, backfill_numero_depre_tick) para uma 2ª passada.
-- Motivo: a 1ª passada (20/10) gravou ~337k números, mas cada recrawl de incidente sobrescrevia
-- numero_depre com null (upsert em persistTree enviava a coluna mesmo sem valor) — hoje só ~171k
-- incidentes têm o número. Aplicar SOMENTE depois do deploy do fix no worker (senão o próximo
-- recrawl apaga de novo). Idempotente: o tick só preenche onde numero_depre is null e há match único.
update backfill_numero_depre_estado
   set ativo = true, cursor_atual = null, updated_at = now()
 where id = true;

-- Acompanhar (rodar de tempos em tempos):
--   select ativo, cursor_atual, total_lotes, total_seguros from backfill_numero_depre_estado;
--   select count(*) filter (where numero_depre is null) sem, count(*) filter (where numero_depre is not null) com from incidentes;
