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
-- quantos ainda nem foram enfileirados de fato). LEFT JOIN LATERAL pro job MAIS
-- RECENTE (não um JOIN direto): crawler_queue guarda histórico, então um .0500
-- com jobs antigos 'ok' contaria várias vezes num join simples; status=null aqui
-- significa "nunca enfileirado", não "sem match".
select cq_ultimo.status, count(*) as total
  from djen_depre d
  left join lateral (
    select status
      from crawler_queue q
     where q.processo_codigo = d.cnj
     order by q.updated_at desc
     limit 1
  ) cq_ultimo on true
 where d.acordo_homologado is null
 group by cq_ultimo.status
 order by cq_ultimo.status nulls first;
