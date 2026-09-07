-- FOR-104 — Índices faltantes por trás de buscar_processos (admin/processos).
-- Diagnóstico: a RPC estourava statement timeout (57014) mesmo com p_limit=1 e sem
-- nenhum filtro do usuário — praticamente não havia índice de suporte em
-- incidentes/processos/partes (só idx_andamentos_inc_data já existia). Aplicar no
-- SQL Editor. Sem CONCURRENTLY de propósito — o SQL Editor do Lovable roda dentro de
-- transação implícita, e CREATE INDEX CONCURRENTLY não pode rodar em transação. Trava
-- escrita nas tabelas por alguns segundos durante a criação (aceitável, tabelas pequenas
-- o suficiente pra não incomodar).

-- Filtro sempre ativo (where p.flag_sp) em toda chamada, mesmo sem filtro nenhum.
CREATE INDEX IF NOT EXISTS idx_processos_flag_sp
  ON public.processos (flag_sp) WHERE flag_sp;

-- Chave do JOIN incidentes → processos.
CREATE INDEX IF NOT EXISTS idx_incidentes_processo_id
  ON public.incidentes (processo_id);

-- ORDER BY valor_acao desc nulls last em toda consulta.
CREATE INDEX IF NOT EXISTS idx_incidentes_valor_acao
  ON public.incidentes (valor_acao DESC NULLS LAST);

-- Subqueries correlacionadas de autor/advogados/OAB (papel='ativa') por incidente,
-- repetidas por linha da página + no filtro de advogado/OAB.
CREATE INDEX IF NOT EXISTS idx_partes_incidente_papel
  ON public.partes (incidente_id, papel);

-- Filtro por OAB (p_oab) — igualdade exata, index simples já resolve.
CREATE INDEX IF NOT EXISTS idx_partes_oab_normalizada
  ON public.partes (oab_normalizada) WHERE oab_normalizada IS NOT NULL;

-- NOTA: os filtros de texto (p_q, p_advogado) usam ILIKE '%...%' sobre
-- regexp_replace(...)/btrim(regexp_replace(...)) — wildcard à esquerda não usa índice
-- comum. Não coberto aqui de propósito (precisaria de índice trigram via extensão
-- pg_trgm, decisão separada se esses filtros continuarem lentos mesmo com os índices
-- acima).
