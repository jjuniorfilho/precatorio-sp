-- FOR-107 — RPC pro self-heal de jobs órfãos em crawler_queue. O worker roda sem
-- SUPABASE_SERVICE_ROLE_KEY na VPS (usa anon key + login admin, "Opção B" já documentada em
-- supabase.ts) — RLS bloqueia UPDATE direto na crawler_queue (só claim_crawler_jobs/
-- complete_crawler_job/fail_crawler_job/enqueue_crawler_job têm grant de escrita, mesmo
-- padrão de todas as mutações dessa tabela). Confirmado: o self-heal client-side (.update()
-- direto) rodou sem erro mas afetou 0 linhas — RLS silenciosamente não deixou.
--
-- Aplicar no SQL Editor.

create or replace function public.reset_orfaos_crawler_queue(p_limite_minutos integer default 60)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_count integer;
begin
  update crawler_queue
     set status = 'pendente'
   where status = 'processando'
     and claimed_at is not null
     and claimed_at < now() - (p_limite_minutos || ' minutes')::interval;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

grant execute on function public.reset_orfaos_crawler_queue(integer) to anon, authenticated;

-- FOR-107 — leitura paginada pro refresh-ativos.ts: mesmo motivo acima (RLS bloqueia SELECT
-- direto em incidentes/processos pro role anon+admin) — via RPC security definer, roda com
-- privilégio do dono da function, sem depender de qual role está autenticado chamando.
create or replace function public.listar_incidentes_para_refresh(
  p_cursor uuid default '00000000-0000-0000-0000-000000000000', p_limit integer default 500)
returns table(incidente_id uuid, cnj text, next_crawl_at timestamptz)
language sql stable security definer set search_path = public
as $function$
  select i.id, p.cnj, p.next_crawl_at
    from incidentes i
    join processos p on p.id = i.processo_id
   where p.flag_sp
     and i.fase <> 'inicial'
     and i.status = 'ativo'
     and i.id > p_cursor
   order by i.id
   limit greatest(p_limit, 1);
$function$;

grant execute on function public.listar_incidentes_para_refresh(uuid, integer) to anon, authenticated;
