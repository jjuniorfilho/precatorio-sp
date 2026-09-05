-- Diagnóstico pontual: status atual na crawler_queue pra uma lista de processo_codigo
-- (usado agora pra acompanhar os 484 jobs 'manual' enfileirados pra consulta de ano_oc).
-- Read-only. Aplicar no SQL Editor.

create or replace function public.diag_status_lote(p_numeros text[])
returns table(processo_codigo text, status text, origem text, created_at timestamptz, updated_at timestamptz)
language sql stable security definer set search_path = public
as $$
  select cq.processo_codigo, cq.status, cq.origem, cq.created_at, cq.updated_at
    from crawler_queue cq
   where cq.processo_codigo = any(p_numeros)
   order by cq.updated_at desc nulls last;
$$;

grant execute on function public.diag_status_lote(text[]) to anon, authenticated;
