-- 'manual' empata em prioridade com 'refresh'/'dje_diario' (só 'backfill' é rebaixado em
-- claim_crawler_jobs) — com ~80k pendentes nesses dois juntos, jobs 'manual' recém-criados
-- ficam no fim da fila se o desempate for scheduled_at mais antigo primeiro. Mesmo padrão já
-- documentado no projeto pra priorizar um advogado: empurrar scheduled_at pra uma data antiga
-- joga o job pra frente da fila dentro do próprio grupo de prioridade, sem mexer em nada mais.
--
-- Aplicar no SQL Editor.

create or replace function public.priorizar_jobs_manual(p_numeros text[])
returns integer
language sql security definer set search_path = public
as $$
  with upd as (
    update crawler_queue
       set scheduled_at = '2000-01-01T00:00:00Z'
     where processo_codigo = any(p_numeros)
       and status = 'pendente'
     returning 1
  )
  select count(*) from upd;
$$;

grant execute on function public.priorizar_jobs_manual(text[]) to anon, authenticated;
