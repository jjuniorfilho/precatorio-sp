-- FOR-202 — backfill de correção: dos incidentes hoje com cessao_credito=false, os que
-- NUNCA tiveram nenhum andamento em nenhuma das 3 fontes (incidente/cumprimento/processo)
-- viram NULL (nunca verificado). Estimativa por amostra (2026-10-21,
-- TABLESAMPLE SYSTEM(5)): ~200.800 de 871.127.
--
-- Pré-requisito: sql/2026-10-21_for202_cessao_credito_nullable.sql já aplicada (coluna
-- nullable + classify_processo/classify_incidentes já corrigidos — sem isso, o próprio
-- crawler reverteria o backfill no próximo ciclo de qualquer forma, já que a função
-- antiga reescreve `false` sempre).
--
-- Desenho: mesmo padrão já em produção pro backfill de numero_depre (jobid 17,
-- backfill_numero_depre_tick — ver pg_get_functiondef capturado nesta sessão). Função
-- "tick" chamada a cada minuto via pg_cron, cursor persistido por id, lock de advisory
-- (nunca sobrepõe), autodesligamento quando um lote vem menor que o tamanho pedido
-- (sinal de que acabou). Preferido a um loop/DO block único porque:
--   1. Não trava o SQL Editor por horas nem arrisca timeout do lado do cliente.
--   2. Resumível — se o cron for pausado/a sessão cair, o cursor persiste.
--   3. Observável — progresso visível em coleta_runs e no estado, sem precisar
--      acompanhar uma sessão aberta.
--   4. Já é o padrão deste projeto pra esse tipo de operação (mesma forma mental de
--      quem for operar depois).
--
-- Recálculo AO VIVO por lote (recomendação do revisor especialista): cada tick decide
-- "sem andamento" na hora, contra o estado atual das 3 fontes — nunca contra uma lista
-- pré-materializada da estimativa. Isso evita a condição de corrida onde o crawler
-- classifica um incidente de verdade entre a medição e a escrita do backfill.
--
-- Guard: só toca linhas com cessao_credito = false (nunca mexe em true nem em NULL já
-- setado por classify_processo rodando em paralelo).
--
-- Pausa/retomada manual: UPDATE for202_backfill_cessao_credito_estado SET ativo = false;
-- (e true de novo pra retomar) — mesmo controle que o numero_depre já tem.

CREATE TABLE IF NOT EXISTS for202_backfill_cessao_credito_estado (
  id boolean PRIMARY KEY DEFAULT true CHECK (id),
  cursor_atual uuid,
  ativo boolean NOT NULL DEFAULT true,
  total_corrigidos bigint NOT NULL DEFAULT 0,
  total_lotes bigint NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now()
);
INSERT INTO for202_backfill_cessao_credito_estado (id) VALUES (true) ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION public.for202_backfill_cessao_credito_tick()
RETURNS void
LANGUAGE plpgsql AS $$
DECLARE
  v_cursor uuid;
  v_ativo boolean;
  v_tamanho int;
  v_corrigidos int;
  v_max_id uuid;
  v_run_id uuid;
  v_lock_ok boolean;
BEGIN
  v_lock_ok := pg_try_advisory_lock(hashtext('for202_backfill_cessao_credito'));
  IF NOT v_lock_ok THEN
    RETURN; -- tick anterior ainda rodando, pula essa chamada (nunca sobrepõe)
  END IF;

  SELECT cursor_atual, ativo INTO v_cursor, v_ativo
    FROM for202_backfill_cessao_credito_estado WHERE id = true;
  IF NOT v_ativo THEN
    PERFORM pg_advisory_unlock(hashtext('for202_backfill_cessao_credito'));
    RETURN;
  END IF;

  INSERT INTO coleta_runs (rotina, status) VALUES ('backfill_cessao_credito', 'running')
    RETURNING id INTO v_run_id;

  BEGIN
    WITH lote AS MATERIALIZED (
      SELECT id FROM incidentes
       WHERE cessao_credito = false
         AND (v_cursor IS NULL OR id > v_cursor)
       ORDER BY id
       LIMIT 3000
    ),
    corrigidos AS (
      UPDATE incidentes i SET cessao_credito = NULL, updated_at = now()
        FROM lote l
       WHERE l.id = i.id
         AND i.cessao_credito = false
         -- recálculo AO VIVO, não contra lista pré-materializada da estimativa:
         AND NOT EXISTS (SELECT 1 FROM andamentos a WHERE a.incidente_id = i.id)
         AND NOT EXISTS (
           SELECT 1 FROM cumprimentos c
            WHERE c.id = i.cumprimento_id AND c.andamentos IS NOT NULL
              AND jsonb_array_length(c.andamentos) > 0
         )
         AND NOT EXISTS (
           SELECT 1 FROM processos p
            WHERE p.id = i.processo_id AND p.andamentos IS NOT NULL
              AND jsonb_array_length(p.andamentos) > 0
         )
      RETURNING i.id
    )
    SELECT
      (SELECT count(*) FROM lote),
      (SELECT count(*) FROM corrigidos),
      (SELECT id FROM lote ORDER BY id DESC LIMIT 1)
    INTO v_tamanho, v_corrigidos, v_max_id;

    UPDATE for202_backfill_cessao_credito_estado
       SET cursor_atual = COALESCE(v_max_id, cursor_atual),
           total_corrigidos = total_corrigidos + COALESCE(v_corrigidos, 0),
           total_lotes = total_lotes + 1,
           ativo = (COALESCE(v_tamanho, 0) = 3000),
           updated_at = now()
     WHERE id = true;

    UPDATE coleta_runs
       SET status = 'sucesso', finished_at = now(),
           itens_ok = COALESCE(v_corrigidos, 0),
           detalhe = jsonb_build_object('tamanho_lote', v_tamanho, 'max_id', v_max_id)
     WHERE id = v_run_id;
  EXCEPTION WHEN OTHERS THEN
    UPDATE coleta_runs SET status = 'erro', finished_at = now(),
           detalhe = jsonb_build_object('erro', sqlerrm) WHERE id = v_run_id;
    PERFORM pg_advisory_unlock(hashtext('for202_backfill_cessao_credito'));
    RAISE;
  END;

  PERFORM pg_advisory_unlock(hashtext('for202_backfill_cessao_credito'));
END;
$$;

-- Cron: a cada minuto, mesmo intervalo do backfill_numero_depre (jobid 17). Autodesliga
-- sozinho (ativo=false) quando o último lote vier menor que 3000 — não precisa de
-- intervenção manual pra parar no fim, só pra pausar antes disso se necessário.
SELECT cron.schedule(
  'backfill-cessao-credito',
  '* * * * *',
  $$SELECT public.for202_backfill_cessao_credito_tick();$$
);

-- Validação (rodar após aplicar, no SQL Editor):
--
-- 1) Confirma que o job foi criado e está ativo:
-- select jobid, jobname, schedule, active from cron.job where jobname = 'backfill-cessao-credito';
--
-- 2) Acompanhar progresso (rodar quantas vezes quiser):
-- select * from for202_backfill_cessao_credito_estado;
-- select count(*) filter (where cessao_credito is null) as nulo,
--        count(*) filter (where cessao_credito = true) as sim,
--        count(*) filter (where cessao_credito = false) as nao
--   from incidentes;
--
-- 3) Quando ativo virar false sozinho (backfill completo), desativar o cron pra não
--    ficar rodando à toa todo minuto:
-- select cron.unschedule('backfill-cessao-credito');
--
-- 4) Pausar manualmente a qualquer momento (ex.: se o crawler estiver sob estresse):
-- update for202_backfill_cessao_credito_estado set ativo = false;
-- -- retomar: update for202_backfill_cessao_credito_estado set ativo = true;
