-- FOR-195 (achado validando o caso-teste real na UI, 2026-10-03) — fix em
-- merge_legado_cumprimento_para_principal: a versão original (2026-10-02) reaponta
-- incidentes.processo_id pro principal e CRIA a linha `cumprimentos` nova, mas nunca preenche
-- incidentes.cumprimento_id apontando pra ela.
--
-- Efeito real observado em /admin/leads (lead Cláudio Maurício Santos, DEPRE
-- 0436868-90.2025.8.26.0500): depois do merge, o incidente continuava com cumprimento_id NULL —
-- exatamente a heurística que a view `leads_processos` (fix FOR-177d,
-- sql/2026-09-30_for177d_fix_processo_principal_legado_swap.sql) usa pra decidir "legado ainda
-- não reconciliado, processos.cnj é o CUMPRIMENTO, processo principal fica em branco". Como o
-- incidente seguia com cumprimento_id NULL mesmo DEPOIS do FOR-195 reconciliar a ação principal
-- de verdade, a view aplicou a lógica antiga — e inverteu "processo principal" com "cumprimento
-- de sentença" na tela (achado com verificação cruzada no e-SAJ, confirmado pelo usuário: PR#34
-- resolveu a seleção de candidatos e o dado no banco está certo; o que faltava era este FK).
--
-- Fix: a RPC agora captura o id da linha `cumprimentos` que ela mesma cria/encontra (RETURNING)
-- e preenche incidentes.cumprimento_id com ele — só para quem estava NULL (coalesce, nunca
-- sobrescreve um cumprimento_id que já existisse por outro motivo). Isso faz a heurística da
-- FOR-177d (cumprimento_id IS NULL <=> legado não reconciliado) voltar a ser verdadeira depois
-- do FOR-195 rodar, sem precisar tocar na view.
--
-- Reordenação: o INSERT...cumprimentos sobe pra ANTES do UPDATE incidentes (precisa do
-- v_cumprimento_id pronto); o UPDATE incidentes passa a setar processo_id E cumprimento_id no
-- mesmo statement, filtrado por processo_id = p_processo_atual_id (valor ORIGINAL, antes da
-- reatribuição — por isso não pode rodar depois).
--
-- Mesma assinatura, mesmos grants (sem mudança de segurança). Idempotente. Aplicar no SQL
-- Editor. Depois de aplicar, rodar a correção retroativa no final deste arquivo pro único caso
-- já mergeado antes deste fix (o caso-teste validado nesta sessão).

create or replace function public.merge_legado_cumprimento_para_principal(
  p_processo_atual_id     uuid,
  p_processo_principal_id uuid
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_cumprimento_id uuid;
begin
  if p_processo_atual_id = p_processo_principal_id then return; end if;

  if not exists (select 1 from processos where id = p_processo_atual_id) then
    return; -- já reconciliado (idempotência) ou id inválido — no-op, nunca erro
  end if;

  if not exists (select 1 from processos where id = p_processo_principal_id) then
    raise exception 'merge_legado_cumprimento_para_principal: processo principal % não existe',
      p_processo_principal_id;
  end if;

  -- o antigo "processo" vira cumprimento de verdade do novo root. on conflict por
  -- processo_codigo (UNIQUE em cumprimentos): no-op funcional se esta RPC for chamada 2x antes
  -- do delete abaixo completar em alguma corrida improvável — mantém o mesmo processo_id.
  -- Roda ANTES do update de incidentes: v_cumprimento_id precisa estar pronto pro backfill de
  -- incidentes.cumprimento_id logo abaixo.
  insert into cumprimentos (processo_id, processo_codigo, cnj, cnj_normalizado)
  select p_processo_principal_id, processo_codigo, cnj, cnj_normalizado
    from processos where id = p_processo_atual_id
  on conflict (processo_codigo) do update set processo_id = excluded.processo_id
  returning id into v_cumprimento_id;

  update cumprimentos set processo_id = p_processo_principal_id where processo_id = p_processo_atual_id;

  -- coalesce: nunca sobrescreve um cumprimento_id que já existisse por outro motivo — só
  -- preenche quem estava NULL (heurística do legado, FOR-178/FOR-177d). Filtra pelo
  -- processo_id ORIGINAL (p_processo_atual_id) — por isso roda num único UPDATE, antes de
  -- qualquer outra coisa reatribuir esses incidentes.
  update incidentes
     set processo_id = p_processo_principal_id,
         cumprimento_id = coalesce(cumprimento_id, v_cumprimento_id)
   where processo_id = p_processo_atual_id;

  update partes set processo_id = p_processo_principal_id where processo_id = p_processo_atual_id;

  delete from processos where id = p_processo_atual_id;
end; $$;

revoke all on function public.merge_legado_cumprimento_para_principal(uuid, uuid) from public, anon;
grant execute on function public.merge_legado_cumprimento_para_principal(uuid, uuid) to service_role, authenticated;

-- Verificação (rodar manualmente após aplicar):
-- select proname, prosecdef, proacl from pg_proc where proname = 'merge_legado_cumprimento_para_principal';
-- (esperado: prosecdef = t; proacl sem entrada "=X/" (PUBLIC) nem "anon=X/")

-- ---------------------------------------------------------------------------------------------
-- Correção retroativa — único caso já mergeado ANTES deste fix (caso-teste validado nesta
-- sessão: DEPRE 0436868-90.2025.8.26.0500, incidente e23a479c-3897-4fb1-907c-7608214cdb9b,
-- processo principal af61846e-440a-4630-8765-090ab46a25d2, cumprimento 0018028-13.2022.8.26.0562
-- já existe em `cumprimentos` com id 13515424-0c3b-4484-948e-7ee869cbf1d2). Rodar 1x, depois de
-- aplicar a função acima. Idempotente (WHERE cumprimento_id IS NULL).
update incidentes
   set cumprimento_id = '13515424-0c3b-4484-948e-7ee869cbf1d2'
 where id = 'e23a479c-3897-4fb1-907c-7608214cdb9b'
   and cumprimento_id is null;
