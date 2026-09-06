-- FOR-146 — Restaura o volume de "cumprimento de sentença" genérico após o fix do
-- match bidirecional de classes (worker-crawler/src/ingest-djen.ts, função classeOk).
--
-- Contexto: o match de classeOk era bidirecional (alvo.includes(c) || c.includes(alvo)).
-- O ramo c.includes(alvo) deixava passar nomeClasse curtos/genéricos só por serem
-- substring de uma config mais longa — ex.: "CUMPRIMENTO DE SENTENÇA" batia contra
-- "Cumprimento de Sentença contra a Fazenda Pública" sem nenhuma relação semântica real.
-- O fix (unidirecional: só alvo.includes(c)) elimina esse falso-positivo, MAS também
-- removeria ~10,8% do volume diário atual (1.524 de 14.123 CNJ, amostra de 4 dias reais
-- 2026-09-01..04 — ver .claude/sessions/for-146-bug-match-bidirecional-classes-relevantes/
-- context.md §5) — 100% desses casos JÁ passam no filtro passivoPublico (são execução/
-- cumprimento de sentença contra ente público de fato, só rotulados de forma genérica
-- pelo TJSP, sem o sufixo "contra a Fazenda Pública").
--
-- Decisão do Gate 1 (humano, 2026-09-06, ver architecture.md): aplicar o fix E adicionar
-- as 2 entradas genéricas abaixo em coleta_config.params.classes_relevantes, para que o
-- volume observável em produção não caia — sem reabrir o bug do match bidirecional.
--
-- IMPORTANTE — ORDEM DE APLICAÇÃO: este UPDATE deve ser aplicado ANTES (ou, na pior
-- hipótese, no mesmo instante) do deploy do fix de código na VPS. Como o UPDATE é
-- aditivo, aplicá-lo primeiro é seguro: não muda nenhum comportamento observável
-- enquanto o código antigo (bidirecional) ainda está no ar (ver plan.md, Fase 2,
-- comentário sobre ordem crítica).
--
-- Antes de aplicar: confirmar que nenhuma migration/UPDATE manual entre
-- supabase/migrations/20260627205511_for70_ingest_djen.sql e hoje já alterou este array
-- em produção (rodar o SELECT de conferência no final deste arquivo ANTES do UPDATE).
--
-- Aplicar manualmente no SQL Editor do Supabase. NÃO faz parte do pipeline de deploy
-- automático do worker (é dado, não schema/migration).

-- 1) Conferir o estado atual ANTES de aplicar (evita sobrescrever ajuste manual feito
--    depois do seed original de FOR-70):
-- select params->'classes_relevantes' from coleta_config where rotina = 'caderno_dje';

update coleta_config
set params = jsonb_set(
  params,
  '{classes_relevantes}',
  '[
    "Cumprimento de Sentença",
    "Cumprimento de Sentença contra a Fazenda Pública",
    "Cumprimento Provisório de Sentença",
    "Cumprimento Provisório de Sentença contra a Fazenda Pública",
    "Execução contra a Fazenda Pública",
    "Precatório",
    "Requisição de Pequeno Valor",
    "Procedimento do Juizado Especial da Fazenda Pública"
  ]'::jsonb
),
updated_at = now()
where rotina = 'caderno_dje';

-- 2) Conferir o resultado (esperado: array com as 8 entradas acima):
-- select params->'classes_relevantes' from coleta_config where rotina = 'caderno_dje';
