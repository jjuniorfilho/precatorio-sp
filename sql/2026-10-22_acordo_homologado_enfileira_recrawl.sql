-- Recrawl de TODOS os .0500 de djen_depre p/ recapturar a Movimentação completa e recalcular
-- acordo_homologado pela regra segura. SÓ APLICAR depois do deploy do worker com o parser
-- corrigido (senão o crawl volta com o mesmo buraco e desperdiça o e-SAJ).
--
-- origem='backfill': claim_crawler_jobs deixa backfill por último (FOR-143), então não fura
-- a fila de trabalho prioritário — o incidente de 2026-09-13 foi justamente 56.761 jobs
-- 'manual' parando na frente de tudo. enqueue_crawler_job_forcado ignora o guard de "fresco".
-- Em blocos por id p/ não estourar o SQL Editor; rode um por vez e confira a fila entre eles.

-- ATENÇÃO: max(id) de djen_depre é ~369.361 (ids têm lacunas; ~72% preenchidos). O bloco 1 (0–50000) já
-- foi aplicado em 2026-10-22 (36.226 jobs). Faltam os intervalos 50001–100000, … até 370000.
-- Bloco 1 (repita com os próximos intervalos até cobrir max(id))
set statement_timeout = '300s';
select count(*) as enfileirados
  from (select public.enqueue_crawler_job_forcado(cnj, 'backfill')
          from djen_depre
         where cnj is not null and id between 0 and 50000) t;

-- Descobrir o max(id) antes: select max(id) from djen_depre;
-- Acompanhar: select status, count(*) from crawler_queue where origem = 'backfill' group by 1;
