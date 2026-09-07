-- =============================================================
-- FIX — coleta_config sem policy de RLS no banco remoto
-- Descoberto 2026-09-06 durante rollout da FOR-145 (Fase 5): a tabela tem
-- RLS habilitado (ALTER TABLE ... ENABLE ROW LEVEL SECURITY, migration
-- FOR-73) mas ZERO policies aplicadas (confirmado via
-- `select * from pg_policies where tablename = 'coleta_config'` — 0 linhas).
-- Sem policy permissiva, Postgres nega tudo por padrão pra quem não é o
-- dono/superuser — o SQL Editor (roda como owner) enxerga as linhas
-- normalmente, mas o worker (client autenticado via anon+login admin,
-- role authenticated) recebe sempre 0 linhas, silenciosamente.
--
-- Mesmo padrão já documentado em docs/../patterns/errors.md pra outra
-- tabela (funnel_events): "banco remoto foi montado via migrations avulsas
-- do Lovable... trazem GRANTs mas não recriam as CREATE POLICY".
--
-- Isso mascarou o job estadual (ingest-djen.ts) por meses — ele tem
-- fallback hardcoded (PARTES_ALVO_DEFAULT, classes vazio = sem filtro) que
-- reproduz o mesmo comportamento com ou sem coleta_config legível. O
-- federal (ingest-djen-federal.ts) não tem esse fallback — por isso foi o
-- primeiro a expor o problema (capturados=0 mesmo com classes_relevantes
-- seedado corretamente, porque o worker nunca conseguia ler o config).
--
-- Rodar no SQL Editor (padrão do projeto). Re-executável.
-- =============================================================

DROP POLICY IF EXISTS "admin_all_coleta_config" ON coleta_config;
CREATE POLICY "admin_all_coleta_config" ON coleta_config FOR ALL TO authenticated USING (true);

-- Sanity check pós-fix (rodar manualmente e conferir >0 linhas):
-- select policyname, roles, cmd from pg_policies where tablename = 'coleta_config';
