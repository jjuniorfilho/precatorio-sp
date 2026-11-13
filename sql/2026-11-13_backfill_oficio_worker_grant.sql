-- Permite rodar o backfill de oficio (sql/2026-11-12_oficio_expedido_rejeitado.sql) a partir do Mac usando o
-- login admin do worker (role `authenticated`), sem service_role. A função de lote em si continua revogada
-- (sem teto de p_limit); este wrapper SECURITY DEFINER limita o lote a 3000 incidentes por chamada.
-- Idempotente: só recalcula colunas derivadas de andamentos que já existem. Re-executável.

CREATE OR REPLACE FUNCTION public.backfill_oficio_incidentes_lote_worker(p_after uuid DEFAULT NULL, p_limit int DEFAULT 500)
RETURNS uuid LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT public.backfill_oficio_incidentes_lote(p_after, least(greatest(coalesce(p_limit, 500), 1), 3000));
$$;

REVOKE ALL ON FUNCTION public.backfill_oficio_incidentes_lote_worker(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backfill_oficio_incidentes_lote_worker(uuid, int) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- Rollback: drop function public.backfill_oficio_incidentes_lote_worker(uuid, int);
