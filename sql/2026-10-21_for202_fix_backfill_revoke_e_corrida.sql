-- FOR-202 (fix pós-aplicação) — 2 achados do code-reviewer, ambos já rodando em
-- produção (sql/2026-10-21_for202_backfill_cessao_credito.sql). URGENTE: aplicar o quanto
-- antes — o item 1 é uma exposição de privilégios ativa agora mesmo.
--
-- 1) for202_backfill_cessao_credito_estado e for202_backfill_cessao_credito_tick() foram
--    criados sem REVOKE/RLS — desvio da convenção já estabelecida no repo (ver
--    sql/2026-09-25_for171_1_tabela_pagamentos_consultas_log.sql,
--    sql/2026-09-29_for174b_revoke_public_execute_pagamentos_rpc.sql, e
--    sql/2026-10-02_for200_*). Confirmado em produção: `anon`/`authenticated` têm
--    INSERT/SELECT/UPDATE/DELETE na tabela de estado e EXECUTE na função tick — qualquer
--    um com a chave pública pode pausar o backfill, pular o cursor pro fim, ou reiniciá-lo.
--
-- 2) Condição de corrida real no UPDATE da função tick, REPRODUZIDA pelo revisor num
--    Postgres local: o UPDATE original fazia o `NOT EXISTS` nas 3 fontes como parte do
--    MESMO statement que o guard `cessao_credito = false` — sob READ COMMITTED, o guard é
--    re-checado contra a versão nova da linha quando há conflito de lock (EvalPlanQual),
--    mas os `NOT EXISTS` (que leem OUTRAS tabelas — andamentos/cumprimentos/processos)
--    continuam usando o snapshot do INÍCIO do statement. Resultado: se o crawler inserir
--    um andamento novo e rodar classify_processo bem no meio da janela do tick, a linha
--    pode virar NULL mesmo já tendo sido verificada de verdade (cessao_credito=false é o
--    valor correto, não "nunca verificado"). O comentário original ("recálculo AO VIVO...
--    evita a condição de corrida") prometia mais do que a implementação entregava — a
--    afirmação foi removida/corrigida aqui.
--
--    Fix: separa em 2 statements. Passo 1 trava as linhas do lote com
--    `FOR UPDATE SKIP LOCKED` (nunca espera o crawler — pula linha que ele estiver
--    mexendo agora, ela fica certa de qualquer jeito nesse caso). Passo 2 é um statement
--    NOVO (snapshot novo sob READ COMMITTED) que só então avalia os `NOT EXISTS` — agora
--    enxerga qualquer andamento commitado entre os 2 passos. Isso fecha a janela pro
--    padrão real do crawler (INSERT andamento numa transação, depois chama
--    classify_processo noutra) — não elimina 100% de qualquer corrida concebível (nenhum
--    sistema sob READ COMMITTED elimina), mas fecha o caso que foi reproduzido.
--
--    Dano já feito (antes deste fix): linhas que foram verificadas de verdade como
--    `false` podem ter virado `NULL` incorretamente durante a janela de exposição. Efeito
--    é conservador (diz "não verificado" em vez de "não") e autocorrige no próximo crawl
--    do processo (TTL ~7 dias) — mas a query de detecção/reparo no final deste arquivo
--    permite corrigir na hora, sem esperar.

-- ===============================================================
-- 1. Fecha a exposição de privilégios.
-- ===============================================================
ALTER TABLE public.for202_backfill_cessao_credito_estado ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.for202_backfill_cessao_credito_estado FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.for202_backfill_cessao_credito_tick() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ===============================================================
-- 2. Fecha a janela de corrida — FOR UPDATE SKIP LOCKED + statement separado.
-- ===============================================================
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
  v_ids uuid[];
BEGIN
  v_lock_ok := pg_try_advisory_lock(hashtext('for202_backfill_cessao_credito'));
  IF NOT v_lock_ok THEN
    RETURN;
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
    -- Passo 1: pega o lote E trava as linhas agora — SKIP LOCKED nunca espera o
    -- crawler; se uma linha está sendo classificada neste exato instante, ela fica de
    -- fora deste lote (correta de qualquer jeito, o classify que está rodando resolve).
    -- ORDER BY id explícito dentro do array_agg: array_agg sem ORDER BY próprio não tem
    -- ordem garantida pelo padrão SQL, mesmo a subquery já vindo ordenada — não depender
    -- de comportamento implícito do planner pra algo que o cursor do backfill depende
    -- (precisamos do maior id do lote, ver v_max_id abaixo, já que uuid não tem max()).
    SELECT array_agg(id ORDER BY id) INTO v_ids
      FROM (
        SELECT id FROM incidentes
         WHERE cessao_credito = false
           AND (v_cursor IS NULL OR id > v_cursor)
         ORDER BY id
         LIMIT 3000
         FOR UPDATE SKIP LOCKED
      ) s;

    v_tamanho := COALESCE(array_length(v_ids, 1), 0);

    -- Passo 2: statement NOVO — snapshot novo sob READ COMMITTED. Os NOT EXISTS agora
    -- enxergam qualquer andamento commitado depois do passo 1 (era exatamente isso que
    -- faltava na versão anterior, que fazia tudo num statement só).
    IF v_tamanho > 0 THEN
      WITH corrigidos AS (
        UPDATE incidentes i SET cessao_credito = NULL, updated_at = now()
         WHERE i.id = ANY(v_ids)
           AND i.cessao_credito = false
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
      SELECT count(*) INTO v_corrigidos FROM corrigidos;
    ELSE
      v_corrigidos := 0;
    END IF;

    -- uuid não tem max() agregado; mas v_ids já veio de "ORDER BY id LIMIT 3000" (passo
    -- 1), então o array está em ordem crescente — o maior id é simplesmente o último.
    IF v_tamanho > 0 THEN
      v_max_id := v_ids[v_tamanho];
    END IF;

    UPDATE for202_backfill_cessao_credito_estado
       SET cursor_atual = COALESCE(v_max_id, cursor_atual),
           total_corrigidos = total_corrigidos + COALESCE(v_corrigidos, 0),
           total_lotes = total_lotes + 1,
           ativo = (v_tamanho = 3000),
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

-- ===============================================================
-- 3. Reparo do dano já feito (rodar 1x, no SQL Editor, depois de aplicar o acima).
--    Acha incidentes que viraram NULL mas na verdade TÊM andamento em alguma fonte
--    (vítimas da corrida, se houver) e reclassifica de verdade.
-- ===============================================================
-- select count(*) from incidentes i
--  where i.cessao_credito is null
--    and (
--      exists (select 1 from andamentos a where a.incidente_id = i.id)
--      or exists (select 1 from cumprimentos c where c.id = i.cumprimento_id
--                   and c.andamentos is not null and jsonb_array_length(c.andamentos) > 0)
--      or exists (select 1 from processos p where p.id = i.processo_id
--                   and p.andamentos is not null and jsonb_array_length(p.andamentos) > 0)
--    );
-- -- se > 0, reclassifica (classify_incidentes já recalcula tudo certo, inclusive
-- -- cessao_credito, a partir do estado real das 3 fontes):
-- select classify_incidentes(array_agg(i.id)) from incidentes i
--  where i.cessao_credito is null
--    and (
--      exists (select 1 from andamentos a where a.incidente_id = i.id)
--      or exists (select 1 from cumprimentos c where c.id = i.cumprimento_id
--                   and c.andamentos is not null and jsonb_array_length(c.andamentos) > 0)
--      or exists (select 1 from processos p where p.id = i.processo_id
--                   and p.andamentos is not null and jsonb_array_length(p.andamentos) > 0)
--    );

-- Validação (rodar após aplicar):
-- select grantee, privilege_type from information_schema.role_table_grants
--  where table_name = 'for202_backfill_cessao_credito_estado'; -- anon/authenticated não devem aparecer
-- select has_function_privilege('anon', 'public.for202_backfill_cessao_credito_tick()', 'execute'); -- false
