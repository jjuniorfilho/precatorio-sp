-- FOR-195 — sobe o último nível que falta: a AÇÃO PRINCIPAL REAL acima do cumprimento, pros
-- ~24.292 incidentes legado que a FOR-178 já reconciliou até o nível do cumprimento de sentença.
--
-- Contexto: a FOR-178 reconciliou incidentes legado (FOR-143) até o CUMPRIMENTO — mas o
-- `processos` row que hoje representa a "raiz" desses casos tem, na verdade, o CNJ do
-- CUMPRIMENTO (não da ação principal real). Isso acontece porque o seed que originou aquela
-- reconciliação foi o próprio CNJ do cumprimento (único dado que o import tinha) e o climb via
-- `a.processoPrinc` nunca foi tentado a partir da página do PRÓPRIO cumprimento nesse fluxo —
-- `reconcileLegadoCumprimento` (supabase.ts) só casa por `cnj_normalizado` contra uma linha já
-- existente, não dispara crawl novo.
--
-- Esta RPC assume que o worker (`fetchProcessoPrincipal` em crawl.ts, chamado pelo script
-- one-off `backfill-legado-cumprimento-principal.ts`) já confirmou, buscando a página do
-- cumprimento no e-SAJ de verdade, que existe um `a.processoPrinc` apontando pra uma ação
-- principal acima — e que o caller já fez upsert dessa ação principal em `processos`
-- (p_processo_principal_id, via upsertReturningId(..., "processo_codigo") — mesmo padrão de
-- persistTree, seguro sob concorrência porque processo_codigo já é UNIQUE). Aqui só reorganiza
-- o que já existe no banco:
--   1. Move `cumprimentos`/`incidentes`/`partes` que hoje apontam pro `processos` row ERRADO
--      (p_processo_atual_id, que na verdade É um cumprimento) pro `processos` row CERTO
--      (p_processo_principal_id).
--   2. Insere uma linha `cumprimentos` representando o antigo "processo" como o que ele
--      realmente é: um cumprimento do novo root (reaproveita o `processo_codigo`/`cnj` que já
--      tinha — nenhum dado é perdido, só reclassificado).
--   3. Apaga o `processos` row antigo (agora redundante — virou uma linha `cumprimentos`).
--
-- Diferença de `merge_legado_processo_para_cumprimento` (FOR-178): lá o objeto fundido era uma
-- linha placeholder `LEGADO-%` (nunca existiu no e-SAJ, guarda de segurança por LIKE — a RPC
-- nunca apaga um processo real). Aqui o objeto movido É um processo real (tem um
-- `processo_codigo` genuíno do e-SAJ, só que no nível hierárquico errado) — por isso não há
-- guarda `LIKE 'LEGADO-%'` equivalente. A defesa é a mesma das demais RPCs `merge_legado_*`:
-- nenhum acesso de `anon` (REVOKE explícito abaixo, lição do FOR-179), só
-- `service_role`/`authenticated` (o worker) pode chamar — e o caller só chama depois de
-- confirmar o link via e-SAJ real, nunca por suposição.
--
-- Idempotente: 2ª chamada com p_processo_atual_id já apagado é no-op.
-- Aplicar no SQL Editor ANTES do deploy do worker/script que a chama.
create or replace function public.merge_legado_cumprimento_para_principal(
  p_processo_atual_id     uuid,
  p_processo_principal_id uuid
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_processo_atual_id = p_processo_principal_id then return; end if;

  if not exists (select 1 from processos where id = p_processo_atual_id) then
    return; -- já reconciliado (idempotência) ou id inválido — no-op, nunca erro
  end if;

  if not exists (select 1 from processos where id = p_processo_principal_id) then
    raise exception 'merge_legado_cumprimento_para_principal: processo principal % não existe',
      p_processo_principal_id;
  end if;

  update cumprimentos set processo_id = p_processo_principal_id where processo_id = p_processo_atual_id;
  update incidentes   set processo_id = p_processo_principal_id where processo_id = p_processo_atual_id;
  update partes       set processo_id = p_processo_principal_id where processo_id = p_processo_atual_id;

  -- o antigo "processo" vira cumprimento de verdade do novo root. on conflict por
  -- processo_codigo (UNIQUE em cumprimentos): no-op funcional se esta RPC for chamada 2x antes
  -- do delete abaixo completar em alguma corrida improvável — mantém o mesmo processo_id.
  insert into cumprimentos (processo_id, processo_codigo, cnj, cnj_normalizado)
  select p_processo_principal_id, processo_codigo, cnj, cnj_normalizado
    from processos where id = p_processo_atual_id
  on conflict (processo_codigo) do update set processo_id = excluded.processo_id;

  delete from processos where id = p_processo_atual_id;
end; $$;

revoke all on function public.merge_legado_cumprimento_para_principal(uuid, uuid) from public, anon;
grant execute on function public.merge_legado_cumprimento_para_principal(uuid, uuid) to service_role, authenticated;

-- Verificação (rodar manualmente após aplicar):
-- select proname, prosecdef, proacl from pg_proc where proname = 'merge_legado_cumprimento_para_principal';
-- (esperado: prosecdef = t; proacl sem entrada "=X/" (PUBLIC) nem "anon=X/")
