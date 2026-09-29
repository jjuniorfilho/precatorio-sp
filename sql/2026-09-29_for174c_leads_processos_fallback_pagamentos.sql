-- FOR-174 (achado em produção, continuação do fix de RLS de 2026-09-29) — `leads_processos`
-- (sql/2026-09-25_for169_2_view_leads_processos.sql) lê `valor_pago`/`pagamentos_consultado_em`
-- SÓ de `public.precatorios` (LEFT JOIN LATERAL), tabela que só existe pro schema LEGADO/import
-- de PDF. Um `.0500` que só existe no schema novo (`incidentes`) nunca tem linha em
-- `precatorios` — mesmo depois de gravar pagamentos de verdade em `precatorios_pagamentos`
-- (fix de RLS de hoje cedo), a grade/modal de /admin/leads continua mostrando "Não verificado"
-- pra sempre, porque a view nunca olha pra `precatorios_pagamentos`.
--
-- NÃO É POSSÍVEL simplesmente gravar o agregado em `precatorios.valor_pago` (proposta descartada
-- nesta mesma sessão): essa coluna já tem dono — o import mensal do PDF (FOR-143,
-- `precatorios_insert_lote`) é a fonte de verdade dela; escrever ali também pelo scraper ao vivo
-- criaria uma corrida de escrita entre os dois processos (qual rodou por último "ganha",
-- silenciosamente).
--
-- Fix: fallback de LEITURA em 2 níveis, sem nenhuma escrita nova.
--   Nível 1 (autoritativo, quando existe): precatorios.valor_pago/pagamentos_consultado_em —
--     inalterado, nunca mexido pelo scraper ao vivo.
--   Nível 2 (preenche o que falta): quando não há linha em precatorios OU valor_pago é NULL,
--     soma precatorios_pagamentos (scraper ao vivo, RLS corrigida hoje) + o resultado mais
--     recente de pagamentos_consultas_log (FOR-171) pro mesmo processo_depre. As duas são
--     origem-agnósticas (não têm FK pra precatorios nem pra incidentes) — funcionam pra
--     QUALQUER .0500, legado ou schema novo, avulso ou site público ou crawler de rotina.
--     `pagamentos_consultas_log` só é lida aqui por dentro da view SECURITY INVOKER, chamada só
--     por service_role (supabaseAdmin) — o REVOKE FROM anon/authenticated do FOR-171 continua
--     valendo, não abre acesso novo a ninguém.
--
-- Sem mudança nas colunas de saldo_depre/acordo_homologado/cessao_credito (saldo ao vivo
-- realmente não existe pro schema novo ainda — mesma limitação que buscar-precatorio/index.ts
-- já tem; acordo/cessão já eram origem-agnósticas desde o FOR-169).
--
-- Aplicar no SQL Editor. Re-executável.

CREATE OR REPLACE VIEW public.leads_processos
WITH (security_invoker = true) AS
SELECT
  lp.id,
  lp.nome,
  lp.email,
  lp.telefone,
  lp.relacao,
  lp.processo_depre,
  lp.saldo_consultado,
  lp.devedora,
  lp.status_crm,
  lp.notas,
  lp.token_email_validado,
  lp.token_telefone_validado,
  lp.relatorio_enviado_at,
  lp.session_id,
  lp.intent,
  lp.created_at,
  lp.updated_at,
  lp.verified_at,
  lp.nivel_funil,
  lp.etapa1_busca,
  lp.etapa2_cadastro,
  lp.etapa3_token_email,
  lp.etapa4_email_validado,
  lp.etapa5_whatsapp_validado,
  lp.etapa6_relatorio,
  p.processo,
  dj.valor_causa,
  pr.saldo_depre,
  -- Nível 1 (precatorios/PDF) vence quando existe; nível 2 (scraper ao vivo) só preenche o
  -- que o nível 1 deixou em branco.
  COALESCE(pr.valor_pago, vivo.valor_pago_vivo) AS valor_pago,
  COALESCE(pr.pagamentos_consultado_em, vivo.consultado_em_vivo) AS pagamentos_consultado_em,
  dj.acordo_homologado,
  inc.cessao_credito
FROM public.leads_com_progresso lp
LEFT JOIN LATERAL (
  SELECT DISTINCT btrim(x) AS processo
  FROM regexp_split_to_table(coalesce(lp.processo_depre, ''), ',') AS x
  WHERE btrim(x) <> ''
) p ON true
LEFT JOIN LATERAL (
  SELECT r.saldo_depre, r.valor_pago, r.pagamentos_consultado_em
  FROM public.precatorios r
  WHERE r.processo_depre = p.processo
  ORDER BY r.updated_at DESC NULLS LAST
  LIMIT 1
) pr ON true
LEFT JOIN LATERAL (
  -- Só roda a agregação quando o nível 1 não resolveu (economiza trabalho no caso comum, DEPRE
  -- legado com o PDF já importado).
  SELECT
    CASE
      WHEN soma.total > 0 THEN soma.total
      WHEN log.finalizada_em IS NOT NULL THEN 0 -- consultado, portal respondeu, sem pagamento
      ELSE NULL -- nunca consultado com sucesso (ou só falhas) — "Não verificado", nunca "Não"
    END AS valor_pago_vivo,
    log.finalizada_em AS consultado_em_vivo
  FROM (
    SELECT COALESCE(SUM(valor), 0) AS total
    FROM public.precatorios_pagamentos
    WHERE processo_depre = p.processo
  ) soma
  LEFT JOIN LATERAL (
    SELECT finalizada_em
    FROM public.pagamentos_consultas_log
    WHERE processo_depre = p.processo AND resultado IN ('encontrado', 'nao_consta')
    ORDER BY finalizada_em DESC NULLS LAST
    LIMIT 1
  ) log ON true
) vivo ON pr.valor_pago IS NULL
LEFT JOIN LATERAL (
  SELECT
    bool_or(d.acordo_homologado) AS acordo_homologado,
    max(d.valor_acao) FILTER (WHERE d.ficha_crawled_at IS NOT NULL) AS valor_causa
  FROM public.djen_depre d
  WHERE d.cnj_normalizado = regexp_replace(p.processo, '\D', '', 'g')
) dj ON true
LEFT JOIN LATERAL (
  SELECT bool_or(i.cessao_credito) AS cessao_credito
  FROM public.incidentes i
  WHERE i.numero_depre = p.processo
) inc ON true;

REVOKE ALL ON public.leads_processos FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_processos TO service_role;

NOTIFY pgrst, 'reload schema';
