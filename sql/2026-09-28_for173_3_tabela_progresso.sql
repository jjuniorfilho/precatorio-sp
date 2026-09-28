-- FOR-173 (3 de 4) — Tabela de PROGRESSO da consulta de valor pago ao portal TJSP.
--
-- Por que uma tabela própria (e não o log do FOR-171): `pagamentos_consultas_log` tem CHECK em `resultado`
-- (encontrado|nao_consta|falha), `finalizada_em` e retenção de 20 linhas por processo — uma linha "em
-- andamento" quebraria o CHECK e o `listar_consultas_pagamento`. Esta tabela é efêmera: UMA linha por
-- `processo_depre`, sobrescrita a cada consulta (o histórico continua sendo o log do FOR-171).
--
-- Quem escreve: o worker (RPC registrar_progresso_consulta_pagamento, SQL 4), só nas consultas de origem
-- 'manual'. Quem lê: o frontend, por server function com service_role (RPC obter_progresso_consulta_pagamento).
-- Acesso: RLS ligado, sem policy, sem GRANT de tabela para anon/authenticated (a /admin roda anônima;
-- padrão do FOR-171). Sem PII: só DEPRE, etapa e contadores.
--
-- Semântica de `etapa` = a etapa EM ANDAMENTO (os passos do coletor são registrados depois de concluídos;
-- o worker converte "concluí X" em "agora está em Y"). `estado` na_fila = esperando a fila do Playwright
-- (concorrência 1); em_andamento = a vez chegou; concluida | falha = terminou.
-- Linha órfã (worker morto no meio) fica em_andamento: o front trata atualizado_em parado > 150s como timeout.
--
-- Re-executável. Aplicar DEPOIS do SQL 1 (a ordem não importa para esta tabela, mas o SQL 4 depende dela).

CREATE TABLE IF NOT EXISTS public.pagamentos_consultas_progresso (
  processo_depre  text        PRIMARY KEY,
  estado          text        NOT NULL CHECK (estado IN ('na_fila', 'em_andamento', 'concluida', 'falha')),
  etapa           text,
  tentativa       integer     NOT NULL DEFAULT 0,
  max_tentativas  integer     NOT NULL DEFAULT 4,
  detalhe         text,
  resultado       text        CHECK (resultado IN ('encontrado', 'nao_consta', 'falha')),
  etapa_falha     text,
  origem          text        CHECK (origem IN ('manual', 'busca_publica', 'crawler')),
  iniciada_em     timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now()
);

-- Limpeza preguiçosa da RPC de escrita (SQL 4) filtra por atualizado_em.
CREATE INDEX IF NOT EXISTS idx_pagamentos_consultas_progresso_atualizado
  ON public.pagamentos_consultas_progresso (atualizado_em);

ALTER TABLE public.pagamentos_consultas_progresso ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.pagamentos_consultas_progresso FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
