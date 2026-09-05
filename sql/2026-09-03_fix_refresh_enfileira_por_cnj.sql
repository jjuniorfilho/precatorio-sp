-- FOR-143/coleta — bug real achado investigando os erros da fila: enqueue_stale_processos()
-- (rotina "Refresh de ativos", cron diário 06:30) enfileirava crawler_queue.processo_codigo
-- com o CÓDIGO INTERNO do e-SAJ (processos.processo_codigo, ex.: "DW002FQ0V0000" — extraído de
-- saj.env.queryString, não é CNJ), sem o foro junto (crawler_queue não tem coluna foro).
--
-- Quando o crawler pega esse job de volta, normalizeToRoot() só consegue derivar o foro se o
-- seed for um CNJ (isCnj(seed) ? parseCnj(seed)?.foro : ""). Código interno não é CNJ →
-- foroHint fica vazio → showByCodigo(codigo, foro='', ...) não acha a ficha → job cai na
-- blindagem "busca não retornou página de detalhe", mesmo o processo existindo de verdade
-- (confirmado manualmente no e-SAJ: 1012233-17.2025.8.26.0590 existe, tem agravo julgado
-- vinculado). Isso explica a maior parte dos ~3.062 erros com origem='refresh'.
--
-- Fix: enfileirar por `cnj` (não `processo_codigo`) — mesmo padrão já usado por
-- ingest-djen.ts/import-csv-legado.ts/crawl.ts (todos enfileiram CNJ). Com CNJ, o crawler
-- deriva o foro sozinho via parseCnj, sem precisar de coluna nova em crawler_queue.
--
-- Aplicar no SQL Editor.

CREATE OR REPLACE FUNCTION enqueue_stale_processos()
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_run UUID; n INT := 0;
BEGIN
  IF NOT COALESCE((SELECT enabled FROM coleta_config WHERE rotina='refresh'), true) THEN
    RETURN 0;  -- rotina pausada
  END IF;
  INSERT INTO coleta_runs (rotina, status) VALUES ('refresh','running') RETURNING id INTO v_run;
  WITH stale AS (
    SELECT cnj FROM processos
     WHERE flag_sp AND (next_crawl_at IS NULL OR next_crawl_at <= NOW())
       AND cnj IS NOT NULL  -- sem CNJ (achado à parte, ver conversa) não dá pra reenfileirar
  ), ins AS (
    INSERT INTO crawler_queue (processo_codigo, origem)
    SELECT cnj, 'refresh' FROM stale
    ON CONFLICT DO NOTHING
    RETURNING 1
  )
  SELECT count(*) INTO n FROM ins;
  UPDATE coleta_runs SET status='sucesso', finished_at=NOW(), itens_ok=n WHERE id=v_run;
  RETURN n;
END; $$;

-- Verificação (rodar após aplicar):
-- select enqueue_stale_processos();  -- roda manual, fora do cron das 06:30
-- select processo_codigo, origem from crawler_queue where origem = 'refresh' order by created_at desc limit 5;
-- deve mostrar CNJ (formato NNNNNNN-DD.AAAA.J.TR.OOOO), não código interno alfanumérico.

-- Limpa o backlog de erro órfão do bug antigo (~3.062 em 2026-09-03): linhas origem='refresh'
-- que ficaram gravadas com código interno (não CNJ) nunca vão ser reconhecidas como duplicata
-- das novas entradas em CNJ que o refresh corrigido acabou de reenfileirar — ficariam de lixo
-- permanente na fila se não apagadas. Regex é o mesmo padrão de isCnj() (esaj.ts) — só apaga o
-- que NÃO bate com formato de CNJ, preservando qualquer linha já correta.
DELETE FROM crawler_queue
 WHERE status = 'erro'
   AND origem = 'refresh'
   AND processo_codigo !~ '^\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}$';
