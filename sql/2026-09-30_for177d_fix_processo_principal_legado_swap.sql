-- FOR-177 (achado com verificação cruzada no e-SAJ do TJSP) — `leads_processos` estava
-- exibindo o CUMPRIMENTO DE SENTENÇA sob o rótulo "processo principal" pra todo incidente
-- importado pelo legado, e deixando "cumprimento de sentença" em branco pra esses mesmos casos.
--
-- Achado (produção, DEPRE 0088499-12.2023.8.26.0500): o e-SAJ mostra que a ação original é
-- 0023830-02.2001.8.26.0053, com o incidente "Cumprimento de Sentença... (0016525-
-- 29.2022.8.26.0053)". No nosso banco, `incidentes.processo_id` desse incidente aponta pra
-- uma linha de `processos` cujo `cnj` é 0016525 — o CUMPRIMENTO, não a ação original — e
-- `cumprimento_id` é NULL (não existe uma linha de `cumprimentos` separada). A view antiga
-- lia `processos.cnj` sempre como "processo principal", então mostrava 0016525 com esse
-- rótulo errado e "cumprimento de sentença" ficava em branco (a informação certa, sob o
-- rótulo errado).
--
-- Causa raiz: import legado (heurística confirmada em produção, sem exceção nos 757.526
-- incidentes: `processo_codigo LIKE 'LEGADO-%' <=> cumprimento_id IS NULL`, 24.292 linhas
-- afetadas) só tinha disponível o CNJ citado na ficha do requisitório — que pra um cumprimento
-- de sentença é o CNJ do próprio cumprimento, não da ação de conhecimento original — e criou a
-- linha de `processos` com esse valor por falta de melhor fonte. A ação original (0023830) não
-- está armazenada em lugar nenhum do banco pra esses casos; não dá pra fabricá-la aqui.
-- (`dj.origem_cnjs`, o fallback da ficha, também aponta pro mesmo CNJ do cumprimento nesse
-- caso — confirmado consultando djen_depre — então não ajuda a recuperar a ação original.)
--
-- Fix: quando `cumprimento_id IS NULL` (linha do legado), o `processos.cnj` que temos é
-- classificado como CUMPRIMENTO (é isso que ele de fato contém), e "processo principal" fica
-- NULL — nunca mostra a mesma informação duas vezes sob rótulos diferentes. Quando existe um
-- `cumprimento_id` de verdade (import via crawler, hierarquia completa), nada muda: continua
-- `processos.cnj` = processo principal, `cumprimentos.cnj` = cumprimento.
--
-- Mesma correção replicada nos outros 2 call-sites que fazem esse mesmo cálculo
-- (src/lib/lead-avulso.functions.ts, supabase/functions/enviar-relatorio/index.ts).
--
-- Sem mudança de colunas/tipos (mesmas 36, mesma ordem — só a LÓGICA de 2 delas muda).
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
  -- FOR-177d: fallback da ficha só entra se for DIFERENTE do que já foi classificado como
  -- cumprimento — senão repetiria o mesmo CNJ sob os dois rótulos (caso real do 0088499-12).
  COALESCE(hier.processo_cnj, NULLIF(dj.origem_cnj, hier.cumprimento_cnj)) AS processo_principal,
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
    -- array_agg com FILTER (bug real do FOR-177/PR#25 — ver histórico da migration anterior):
    -- origem_cnjs é array, array_agg sobre NULL quebra a view inteira sem o FILTER.
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
  -- FOR-177d: import legado (cumprimento_id IS NULL) guarda o CNJ do CUMPRIMENTO em
  -- processos.cnj (única fonte que existia na hora do import) — não é a ação original.
  -- Classifica corretamente pra não misturar as duas coisas sob o rótulo errado.
  SELECT
    i2.numero_incidente,
    CASE WHEN i2.cumprimento_id IS NOT NULL THEN cu.cnj ELSE pc.cnj END AS cumprimento_cnj,
    CASE WHEN i2.cumprimento_id IS NOT NULL THEN pc.cnj ELSE NULL END AS processo_cnj
  FROM public.incidentes i2
  JOIN public.processos pc ON pc.id = i2.processo_id
  LEFT JOIN public.cumprimentos cu ON cu.id = i2.cumprimento_id
  WHERE i2.numero_depre = p.processo
  LIMIT 1
) hier ON true;

REVOKE ALL ON public.leads_processos FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_processos TO service_role;

NOTIFY pgrst, 'reload schema';
