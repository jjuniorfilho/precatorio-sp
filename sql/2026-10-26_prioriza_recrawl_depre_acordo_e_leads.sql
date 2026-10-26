-- Recrawl PRIORITÁRIO de um subconjunto pequeno de .0500 (≈680), sem esperar a fila inteira
-- (92k 'manual' + 55k 'backfill' pendentes em 2026-10-26; o recrawl completo leva semanas):
--   (a) DEPREs que já têm "Comunicado de Acordo de Requisitório" nos andamentos e ainda não foram
--       recrawleados pelo worker novo (≈671) — são os candidatos reais a acordo homologado;
--   (b) DEPREs de leads/lead_precatorios ainda não recrawleados (≈9).
--
-- Por que não só priorizar_jobs_manual: ele só adianta scheduled_at DENTRO do grupo de prioridade, e
-- 'backfill' é sempre o último grupo (FOR-143); além disso enqueue_crawler_job_forcado faz
-- ON CONFLICT DO NOTHING — se já há job aberto (ex.: o 'backfill' do bloco 1) ele não muda a origem.
-- Então: (1) promove a 'manual' os jobs 'backfill' pendentes do subconjunto; (2) cria job 'manual' p/ os
-- que não têm; (3) joga todos p/ a frente do grupo.
-- Volume pequeno de propósito (o incidente de 2026-09-13 foi 56k 'manual' furando a fila).
-- SÓ APLICAR com o worker novo (PR #48) no ar. Rode cada bloco separado.

-- 0) Conferir o tamanho (esperado ≈ 680):
-- with alvo as (...bloco abaixo...) select count(*) from alvo;

-- 1) Promove os 'backfill' pendentes do subconjunto
with alvo as (
  select d.cnj from djen_depre d
   where d.cnj is not null
     and (d.ficha_crawled_at is null or d.ficha_crawled_at <= timestamptz '2026-10-22 02:30:00+00')
     and ( exists (select 1 from jsonb_array_elements(d.andamentos) a where a->>'descricao' ilike 'Comunicado de Acordo de Requisit%')
        or d.cnj in (select processo_depre from leads where processo_depre is not null
                     union select processo_depre from lead_precatorios where processo_depre is not null) )
)
update crawler_queue q
   set origem = 'manual', scheduled_at = timestamptz '2000-01-01T00:00:00Z'
  from alvo
 where q.processo_codigo = alvo.cnj and q.status = 'pendente' and q.origem = 'backfill';

-- 2) Cria job 'manual' p/ quem não tem job aberto (idempotente: ON CONFLICT DO NOTHING) e adianta na fila
with alvo as (
  select d.cnj from djen_depre d
   where d.cnj is not null
     and (d.ficha_crawled_at is null or d.ficha_crawled_at <= timestamptz '2026-10-22 02:30:00+00')
     and ( exists (select 1 from jsonb_array_elements(d.andamentos) a where a->>'descricao' ilike 'Comunicado de Acordo de Requisit%')
        or d.cnj in (select processo_depre from leads where processo_depre is not null
                     union select processo_depre from lead_precatorios where processo_depre is not null) )
), criados as (
  select public.enqueue_crawler_job_forcado(cnj, 'manual') from alvo
)
select count(*) as total_alvo, public.priorizar_jobs_manual((select array_agg(cnj) from alvo)) as priorizados
  from criados;

-- Acompanhar (separado): quantos do subconjunto já foram recrawleados e viraram true/false
-- select acordo_homologado, count(*) from djen_depre
--  where ficha_crawled_at > timestamptz '2026-10-22 02:30:00+00'
--    and exists (select 1 from jsonb_array_elements(andamentos) a where a->>'descricao' ilike 'Comunicado de Acordo de Requisit%')
--  group by 1;
