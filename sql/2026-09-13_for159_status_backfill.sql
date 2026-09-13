-- FOR-159 — status read-only do backfill de acordo_homologado. Rodar de novo ao
-- longo dos próximos dias pra acompanhar o progresso (throughput histórico do
-- crawler ~235 jobs/h — não é anormal levar vários dias pra zerar os pendentes).

select
  acordo_homologado is null as pendente,
  count(*) as total,
  count(*) filter (where acordo_homologado = true) as com_acordo
from djen_depre
group by 1
order by 1;

-- Status da fila especificamente para os .0500 ainda pendentes (opcional, mais
-- detalhado — mostra quantos já estão 'ok'/'processando'/'erro' na fila vs.
-- quantos ainda nem foram enfileirados de fato):
select cq.status, count(*) as total
  from djen_depre d
  join crawler_queue cq on cq.processo_codigo = d.cnj
 where d.acordo_homologado is null
 group by cq.status
 order by cq.status;
