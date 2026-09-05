-- Números CNJ terminados em .8.26.0000 nunca são achados no e-SAJ (nem cpopg 1º grau, nem
-- cposg 2º grau — testado manualmente, ver conversa FOR-143/coleta). Por ora, fora do escopo
-- de precatórios: em vez de deixar essas ~13.654 tentativas se acumularem indefinidamente em
-- crawler_queue (erro sempre, nunca resolve), bloqueia o enfileiramento na origem.
--
-- enqueue_crawler_job é o único ponto de entrada usado por ingest-djen.ts, pelo enfileiramento
-- de origem de requisitório (crawl.ts:90) e pelo backfill — cobre todos os enfileiramentos
-- "novos". enqueue_stale_processos() (rotina "Refresh de ativos") não precisa do mesmo guard:
-- ela só reenfileira processos que já existem em `processos`, e um .0000 nunca chega lá porque
-- nunca completa um crawl com sucesso.
--
-- Aplicar no SQL Editor.

CREATE OR REPLACE FUNCTION enqueue_crawler_job(p_processo_codigo TEXT, p_origem TEXT DEFAULT 'manual')
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_processo_codigo LIKE '%.8.26.0000' THEN
    RETURN;  -- nunca existe no e-SAJ (1º ou 2º grau) — fora de escopo por ora
  END IF;
  IF EXISTS (
    SELECT 1 FROM processos
     WHERE processo_codigo = p_processo_codigo
       AND next_crawl_at IS NOT NULL AND next_crawl_at > NOW()
  ) THEN
    RETURN;  -- ainda fresco
  END IF;
  INSERT INTO crawler_queue (processo_codigo, origem)
  VALUES (p_processo_codigo, p_origem)
  ON CONFLICT DO NOTHING;  -- unique parcial em aberto
END; $$;

-- Limpa o backlog de erro já acumulado pra esse padrão (~13.654 em 2026-09-03) — sem valor de
-- auditoria manter linha de fila de processo que sabidamente nunca vai ser buscado, e assim o
-- painel de erro volta a refletir problema real.
DELETE FROM crawler_queue
 WHERE status = 'erro'
   AND processo_codigo LIKE '%.8.26.0000';

-- Verificação (rodar após aplicar):
-- select enqueue_crawler_job('0020613-89.2026.8.26.0000');
-- select count(*) from crawler_queue where processo_codigo = '0020613-89.2026.8.26.0000';  -- 0 (não insere)
