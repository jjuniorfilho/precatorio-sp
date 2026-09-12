-- Fix definitivo do incidente agudo do crawler_esaj (circuit-breaker travando desde 26/08).
--
-- Causa raiz confirmada via diag_enqueue_stale_processos_source(): a função
-- enqueue_stale_processos() em produção NUNCA teve a exclusão de processo_codigo LIKE
-- 'LEGADO-%' — o fix de sql/2026-08-19_for143_exclui_legado_do_refresh.sql não pegou (foi
-- escrito e o plan.md da sessão registra como "aplicado e verificado", mas a função viva no
-- banco não tinha a cláusula). Resultado: ~11.980 jobs origem='refresh' com processo_codigo
-- 'LEGADO-*' ciclando em retry infinito (nunca resolvem no e-SAJ, então nunca saem da fila),
-- competindo em prioridade igual com jobs 'manual'/'dje_diario' — inclusive os 484 jobs
-- manuais enfileirados hoje pra consulta de ordem cronológica.
--
-- Aplicar no SQL Editor. Parte 1 primeiro (limpa o que já está preso), parte 2 depois
-- (impede que volte a acontecer).

-- -------------------------------------------------------------
-- 1) Purga imediata: remove os LEGADO- presos na fila agora (alívio imediato).
--    Os processos LEGADO- de verdade continuam cobertos pela via correta (backfill, que já
--    usa o CNJ real — ver FASE 5/6 do FOR-143), então nada se perde ao tirar esses da fila.
-- -------------------------------------------------------------
delete from crawler_queue
 where processo_codigo like 'LEGADO-%';

-- -------------------------------------------------------------
-- 2) Fix de origem: enqueue_stale_processos() passa a excluir LEGADO- de verdade,
--    pra essa mesma inundação não voltar no próximo ciclo horário da rotina 'refresh'.
-- -------------------------------------------------------------
create or replace function public.enqueue_stale_processos()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE v_run UUID; n INT := 0;
BEGIN
  IF NOT COALESCE((SELECT enabled FROM coleta_config WHERE rotina='refresh'), true) THEN
    RETURN 0;  -- rotina pausada
  END IF;
  INSERT INTO coleta_runs (rotina, status) VALUES ('refresh','running') RETURNING id INTO v_run;
  WITH stale AS (
    SELECT processo_codigo FROM processos
     WHERE flag_sp AND (next_crawl_at IS NULL OR next_crawl_at <= NOW())
       AND processo_codigo NOT LIKE 'LEGADO-%'
  ), ins AS (
    INSERT INTO crawler_queue (processo_codigo, origem)
    SELECT processo_codigo, 'refresh' FROM stale
    ON CONFLICT DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO n FROM ins;
  UPDATE coleta_runs SET status='sucesso', finished_at=NOW(), itens_ok=n WHERE id=v_run;
  RETURN n;
END; $function$;

-- Verificação (rodar após aplicar):
-- select * from diag_legado_queue(); -- deve vir vazio agora
-- select public.diag_enqueue_stale_processos_source(); -- deve mostrar a cláusula NOT LIKE
