-- Import mensal do PDF "Consulta do Total da Dívida Anual - Detalhado" (TJSP), duas fontes:
-- Estado de SP (FE001) e Prefeitura de SP (PM576). Mesmo layout tabular nos dois PDFs, só o
-- devedor/cabeçalho muda. Tabela `precatorios` já tinha as colunas de dado (dt_ensejo_ordem,
-- condicao_superpreferencia, valor_pago, saldo_depre) preparadas antes (fora do git), mas
-- faltava uma forma de distinguir a fonte pra permitir substituição mensal seletiva (sem
-- apagar uma fonte ao reimportar a outra) e RPCs pra escrever (RLS bloqueia INSERT/DELETE
-- direto pro client "Opção B" do worker, mesmo padrão de crawler_queue/processos/incidentes).
--
-- Re-executável. Aplicar no SQL Editor.

ALTER TABLE public.precatorios
  ADD COLUMN IF NOT EXISTS fonte_relatorio TEXT CHECK (fonte_relatorio IN ('estado', 'municipio'));

CREATE INDEX IF NOT EXISTS idx_precatorios_fonte_relatorio ON public.precatorios (fonte_relatorio);

-- processo_depre (.0500) é emitido globalmente pelo TJSP — nunca deveria repetir na tabela,
-- nem entre fontes diferentes. Faltava essa garantia (só havia índice não-único antes,
-- idx_precatorios_processo_depre em djen_depre_e_saldo.sql). Necessário também pro ON CONFLICT
-- do precatorios_insert_lote abaixo. Tabela está vazia hoje, então este ALTER é seguro.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'precatorios_processo_depre_key'
  ) THEN
    ALTER TABLE public.precatorios ADD CONSTRAINT precatorios_processo_depre_key UNIQUE (processo_depre);
  END IF;
END $$;

-- Apaga tudo de uma fonte (passo 1 da substituição mensal). SECURITY DEFINER pra bypassar RLS
-- (mesmo padrão de enqueue_crawler_job/merge_legado_* etc.).
CREATE OR REPLACE FUNCTION public.precatorios_delete_fonte(p_fonte TEXT)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  DELETE FROM precatorios WHERE fonte_relatorio = p_fonte;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END; $$;

-- Insere um lote (chamado várias vezes pelo script, em chunks — evita payload gigante numa
-- RPC só pros ~150k+50k registros). Cada linha do jsonb já vem com fonte_relatorio setado.
-- Upsert por processo_depre (não INSERT puro): dentro do MESMO arquivo PDF, um processo_depre
-- nunca deveria repetir, mas se algum lote for reenviado por retry após falha de rede, isso
-- evita erro de unique violation e mantém o script idempotente por lote também.
CREATE OR REPLACE FUNCTION public.precatorios_insert_lote(p_rows JSONB)
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  INSERT INTO precatorios (
    processo_depre, natureza, dt_ensejo_ordem, condicao_superpreferencia,
    valor_pago, saldo_depre, data_protocolo, fonte_relatorio, updated_at
  )
  SELECT
    r->>'processo_depre', r->>'natureza', (r->>'dt_ensejo_ordem')::date,
    r->>'condicao_superpreferencia', (r->>'valor_pago')::bigint, (r->>'saldo_depre')::bigint,
    (r->>'data_protocolo')::date, r->>'fonte_relatorio', now()
  FROM jsonb_array_elements(p_rows) AS r
  ON CONFLICT (processo_depre) DO UPDATE SET
    natureza = EXCLUDED.natureza, dt_ensejo_ordem = EXCLUDED.dt_ensejo_ordem,
    condicao_superpreferencia = EXCLUDED.condicao_superpreferencia,
    valor_pago = EXCLUDED.valor_pago, saldo_depre = EXCLUDED.saldo_depre,
    data_protocolo = EXCLUDED.data_protocolo, fonte_relatorio = EXCLUDED.fonte_relatorio,
    updated_at = now();
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END; $$;

GRANT EXECUTE ON FUNCTION public.precatorios_delete_fonte(TEXT)  TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.precatorios_insert_lote(JSONB)  TO service_role, authenticated;

-- Verificação (rodar após aplicar):
-- select precatorios_insert_lote('[{"processo_depre":"TESTE-0001","natureza":"Alimentar","dt_ensejo_ordem":"2020-01-01","condicao_superpreferencia":"teste","valor_pago":0,"saldo_depre":12345,"data_protocolo":"2020-01-01","fonte_relatorio":"estado"}]'::jsonb);
-- select * from precatorios where processo_depre = 'TESTE-0001';
-- select precatorios_delete_fonte('estado'); -- deve remover a linha de teste (fonte='estado')
-- select count(*) from precatorios; -- deve voltar a 0
