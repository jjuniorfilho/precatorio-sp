-- FOR-143/coleta — foro 0000 (processo sem distribuição/vara própria) nunca tem ficha no
-- cpopg — confirmado (ver sql/2026-09-03_diag_erros_categoria_hora.sql, amostra do log de
-- 2026-09-04: 12/15 falhas de "não retornou página de detalhe" eram foro .0000). A partir
-- desta versão do ingest-djen.ts/ingest-oab.ts esses CNJs nem entram mais em crawler_queue
-- (ver naoDistribuido() em esaj.ts). Isso aqui limpa o que já estava na fila ANTES do fix —
-- só afeta esses CNJs específicos, não muda nada do resto da fila.
-- Rodar no SQL Editor.

-- 1) Conferir volume antes de mexer
select status, count(*) as n
from crawler_queue
where processo_codigo ~ '\.8\.26\.0000$'
group by 1
order by 2 desc;

-- 2) Remove da fila (pendente/processando/erro) — não tem "estado bom" possível pra esses,
-- então DELETE em vez de só marcar como erro/ok (ficaria lixo morto na tabela pra sempre)
delete from crawler_queue
where processo_codigo ~ '\.8\.26\.0000$';

-- 3) Conferir que sumiu
select count(*) as restantes
from crawler_queue
where processo_codigo ~ '\.8\.26\.0000$';
