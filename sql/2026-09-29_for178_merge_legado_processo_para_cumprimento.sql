-- FOR-178 — reconciliação LEGADO no nível do CUMPRIMENTO (não só da raiz).
--
-- Incidentes importados pelo legado (FOR-143: cumprimento_id IS NULL, processo_codigo LEGADO-%)
-- pendem de uma linha `processos` LEGADO- cujo cnj é o do CUMPRIMENTO de sentença (única info que
-- o import tinha), não o da ação original. O crawler sobe até a raiz (normalizeToRoot) e o
-- merge_legado_processo existente casa só pelo cnj da RAIZ — nunca achava essa linha, criava a
-- hierarquia real em paralelo e deixava a legado órfã (numero_depre duplicado em incidentes).
--
-- Esta RPC é chamada pelo worker (supabase.ts: reconcileLegadoCumprimento) logo após o upsert de
-- cada cumprimento cujo cnj_normalizado bate com uma linha processos LEGADO-: reaponta
-- incidentes (processo_id + cumprimento_id) e partes pro processo raiz real + cumprimento real e
-- apaga a linha legado. O loop de incidentes do worker, em seguida, renomeia/mergeia o incidente
-- LEGADO- com o real (reconcileLegadoIncidente / merge_legado_incidente) pelo numero_depre.
--
-- Guardas (além do padrão FOR-143 `legado = real → return`):
--  * a linha "legado" TEM que ser LEGADO- — senão no-op (a RPC nunca apaga um processo real);
--  * o cumprimento TEM que pertencer ao processo real — senão erro (evita pendurar incidente
--    num cumprimento de outra árvore).
--  * cumprimentos pendurados na linha legado (o import não cria, mas o FK é ON DELETE CASCADE)
--    são reapontados antes do delete, pra não serem apagados em cascata.
--
-- Idempotente: 2ª chamada com a linha legado já apagada é no-op.
-- Aplicar no SQL Editor ANTES do deploy do worker que a chama.
create or replace function public.merge_legado_processo_para_cumprimento(
  p_legado_processo_id  uuid,
  p_real_processo_id    uuid,
  p_real_cumprimento_id uuid
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_processo_id = p_real_processo_id then return; end if;

  if not exists (
    select 1 from processos where id = p_legado_processo_id and processo_codigo like 'LEGADO-%'
  ) then
    return;
  end if;

  if not exists (
    select 1 from cumprimentos where id = p_real_cumprimento_id and processo_id = p_real_processo_id
  ) then
    raise exception 'merge_legado_processo_para_cumprimento: cumprimento % não pertence ao processo %',
      p_real_cumprimento_id, p_real_processo_id;
  end if;

  update incidentes
     set processo_id = p_real_processo_id,
         -- legado tem cumprimento_id NULL; se algum já tiver um (cumprimento pendurado na linha
         -- legado, reapontado abaixo), preserva o vínculo original.
         cumprimento_id = coalesce(cumprimento_id, p_real_cumprimento_id)
   where processo_id = p_legado_processo_id;
  update partes       set processo_id = p_real_processo_id where processo_id = p_legado_processo_id;
  update cumprimentos set processo_id = p_real_processo_id where processo_id = p_legado_processo_id;
  delete from processos where id = p_legado_processo_id;
end; $$;

-- Função nasce com EXECUTE pra PUBLIC no Postgres — revoga explicitamente (lição do FOR-174).
revoke all on function public.merge_legado_processo_para_cumprimento(uuid, uuid, uuid) from public, anon;
grant execute on function public.merge_legado_processo_para_cumprimento(uuid, uuid, uuid) to service_role, authenticated;

-- Verificação (rodar manualmente após aplicar):
-- select proname, prosecdef, proacl from pg_proc where proname = 'merge_legado_processo_para_cumprimento';
-- (esperado: prosecdef = t; proacl sem entrada "=X/" (PUBLIC) nem "anon=X/")
