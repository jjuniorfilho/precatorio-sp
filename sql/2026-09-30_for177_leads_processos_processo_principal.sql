-- FOR-177 (achado ao verificar em produção) — `leads_processos` também precisa expor processo
-- principal, cumprimento de sentença e nº do incidente. A Fase 1/2 do FOR-177 só cobriu o
-- painel "Dados do DEPRE" do diálogo "Novo lead avulso" (`getDepreDados`) e o e-mail de
-- relatório — mas o modal de detalhe de um lead já existente (`LeadDetailModal`, card
-- "Processos consultados" em /admin/leads) lê de `leads_processos`/`getLeadProcessos`, um
-- TERCEIRO call-site que ficou de fora do escopo original e continuava sem os 3 campos.
--
-- Mesma resolução já usada nos outros 2 lugares (src/lib/lead-avulso.functions.ts,
-- supabase/functions/enviar-relatorio/index.ts): processo principal com prioridade schema novo
-- (`processos.cnj` via `incidentes.processo_id`) > ficha (`djen_depre.origem_cnjs[1]`, array
-- 1-indexed no Postgres) — sem fallback pro legado aqui (mesma decisão do painel avulso: quem
-- teria só `autos` sem ficha nem incidente é residual). Cumprimento de sentença
-- (`cumprimentos.cnj` via `incidentes.cumprimento_id`) e nº do incidente
-- (`incidentes.numero_incidente`) só existem no schema novo, sem fallback — ficam NULL quando
-- não há (nunca "—" fabricado na view; isso é decisão de UI).
--
-- 3 colunas NOVAS no FIM do SELECT (mesmos nomes/tipos/ordem das 33 existentes preservados —
-- ver o erro 42P16 batido no FOR-176 por não fazer isso direito da primeira vez).
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
  COALESCE(pr.valor_pago, vivo.valor_pago_vivo) AS valor_pago,
  COALESCE(pr.pagamentos_consultado_em, vivo.consultado_em_vivo) AS pagamentos_consultado_em,
  dj.acordo_homologado,
  inc.cessao_credito,
  lp.origem,
  -- FOR-177: as 3 colunas novas, sempre no FIM.
  COALESCE(hier.processo_cnj, dj.origem_cnj) AS processo_principal,
  hier.cumprimento_cnj AS cumprimento_sentenca,
  hier.numero_incidente
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
  SELECT
    CASE
      WHEN soma.total > 0 THEN soma.total
      WHEN log.finalizada_em IS NOT NULL THEN 0
      ELSE NULL
    END AS valor_pago_vivo,
    log.finalizada_em AS consultado_em_vivo
  FROM (
    SELECT COALESCE(SUM(valor), 0)::bigint AS total
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
    max(d.valor_acao) FILTER (WHERE d.ficha_crawled_at IS NOT NULL) AS valor_causa,
    -- FOR-177: processo principal via ficha do requisitório (fallback quando não há incidente
    -- ligado). cnj_normalizado é 1:1 por design (FOR-159), mas usa array_agg + [1] em vez de
    -- max() por segurança/consistência com o resto desta lateral (defesa em profundidade, sem
    -- assumir a garantia de unicidade).
    --
    -- BUG REAL EM PRODUÇÃO (corrigido): array_agg sobre uma coluna que já é ARRAY
    -- (origem_cnjs text[]) lança "cannot accumulate null arrays" assim que UMA linha tiver
    -- origem_cnjs NULL — e a maioria dos DEPRE tem linha em djen_depre (ficha crawleada) mas
    -- SEM origem_cnjs preenchido, o caso mais comum, não o raro. Isso derrubou a grade inteira
    -- de /admin/leads (0 leads carregados). Diferente de bool_or/max/sum, que toleram NULL
    -- normalmente — array_agg sobre array não tolera. Fix: FILTER descarta as linhas com
    -- origem_cnjs NULL ANTES de agregar (array_agg de um conjunto vazio dá NULL, sem erro).
    (array_agg(d.origem_cnjs ORDER BY d.ficha_crawled_at DESC NULLS LAST)
      FILTER (WHERE d.origem_cnjs IS NOT NULL))[1][1] AS origem_cnj
  FROM public.djen_depre d
  WHERE d.cnj_normalizado = regexp_replace(p.processo, '\D', '', 'g')
) dj ON true
LEFT JOIN LATERAL (
  SELECT bool_or(i.cessao_credito) AS cessao_credito
  FROM public.incidentes i
  WHERE i.numero_depre = p.processo
) inc ON true
LEFT JOIN LATERAL (
  -- FOR-177: hierarquia processo → cumprimento → incidente (schema novo). Pega a 1ª linha
  -- (credores conjuntos podem ter mais de uma, mas processo/cumprimento/incidente são os
  -- mesmos entre elas na prática — mesmo laissez-faire do resto do código desta feature).
  SELECT i2.numero_incidente, cu.cnj AS cumprimento_cnj, pc.cnj AS processo_cnj
  FROM public.incidentes i2
  JOIN public.processos pc ON pc.id = i2.processo_id
  LEFT JOIN public.cumprimentos cu ON cu.id = i2.cumprimento_id
  WHERE i2.numero_depre = p.processo
  LIMIT 1
) hier ON true;

REVOKE ALL ON public.leads_processos FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_processos TO service_role;

NOTIFY pgrst, 'reload schema';
