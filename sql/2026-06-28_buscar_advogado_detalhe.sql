-- FOR-76 — Detalhe do advogado via RPC (SECURITY DEFINER), espelhando buscar_advogados.
-- Motivo: a área /admin é anônima (sem login). O detalhe fazia SELECT direto em
-- mv_advogado_carteira, mas materialized view NÃO honra RLS e não tinha GRANT →
-- "permission denied for materialized view" (42501) → a página mostrava
-- "Advogado não encontrado". A lista já contorna isso via RPC buscar_advogados.
-- Esta função faz o mesmo p/ o detalhe e mescla o status de parceria.
-- Aplicar no SQL Editor do Supabase.

create or replace function public.buscar_advogado_detalhe(p_adv_key text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select to_jsonb(mv) || jsonb_build_object(
    'parceria_status', coalesce((select ap.status from public.advogado_parceria ap
                                  where ap.adv_key = mv.adv_key), null)
  )
  from public.mv_advogado_carteira mv
  where mv.adv_key = p_adv_key;
$$;

grant execute on function public.buscar_advogado_detalhe(text) to anon, authenticated;
