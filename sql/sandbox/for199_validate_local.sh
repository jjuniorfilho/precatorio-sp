#!/usr/bin/env bash
#
# FOR-199 — valida as 2 RPCs de leitura de erro_categoria (crawler_queue_erro_categoria_counts
# + pagamentos_consultas_resumo) num Postgres local efêmero, ANTES de pedir aplicação manual no
# SQL Editor de produção. Schema criado já no estado PÓS-FOR-198 (coluna + CHECK presentes),
# porque é o estado real do banco em produção hoje.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for199_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54350}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
[[ -x "$PGBIN/initdb" ]] || { echo "ERRO: initdb não encontrado em $PGBIN (defina PGBIN)"; exit 2; }

cleanup() { "$PGBIN/pg_ctl" -D "$TMP/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

psql_() { "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -q -v ON_ERROR_STOP=1 "$@"; }
val() { psql_ -d sandbox -At -c "$1"; }
falha() { echo "✘ $*" >&2; exit 1; }
ok() { echo "✔ $*"; }
eq() { [[ "$1" == "$2" ]] && ok "$3 ($1)" || falha "$3: esperado '$2', veio '$1'"; }

"$PGBIN/initdb" -D "$TMP/data" --auth=trust -U postgres >/dev/null
"$PGBIN/pg_ctl" -D "$TMP/data" -o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" -l "$TMP/pg.log" -w start >/dev/null
psql_ -c "CREATE DATABASE sandbox" postgres

# Schema PÓS-FOR-198: crawler_queue e pagamentos_consultas_log já com erro_categoria + CHECK
# (é o estado real de produção hoje — as migrations do FOR-198 já foram aplicadas).
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;

CREATE TABLE crawler_queue (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo TEXT NOT NULL,
  status          TEXT NOT NULL DEFAULT 'pendente' CHECK (status IN ('pendente','processando','ok','erro')),
  origem          TEXT CHECK (origem IN ('dje_diario','backfill','refresh','manual')),
  scheduled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  claimed_at      TIMESTAMPTZ,
  tentativas      INT NOT NULL DEFAULT 0,
  erro            TEXT,
  erro_categoria  TEXT CHECK (erro_categoria IN (
    'captcha', 'timeout', 'rate_limit', 'site_indisponivel',
    'bloqueio_suspeito', 'cnj_nao_encontrado', 'outro'
  )),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE pagamentos_consultas_log (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_depre       text        NOT NULL,
  iniciada_em          timestamptz NOT NULL,
  finalizada_em        timestamptz,
  origem               text        NOT NULL CHECK (origem IN ('manual', 'busca_publica', 'crawler')),
  resultado            text        NOT NULL CHECK (resultado IN ('encontrado', 'nao_consta', 'falha')),
  tentativas           integer     NOT NULL DEFAULT 0,
  situacao             text,
  qtd_pagamentos       integer,
  data_consulta_portal text,
  erro                 text,
  etapa_falha          text,
  erro_categoria       text CHECK (erro_categoria IN (
    'captcha', 'timeout', 'rate_limit', 'site_indisponivel',
    'bloqueio_suspeito', 'cnj_nao_encontrado', 'outro'
  )),
  passos               jsonb       NOT NULL DEFAULT '[]'::jsonb,
  criado_em            timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE pagamentos_consultas_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON pagamentos_consultas_log FROM anon, authenticated;
EOF
ok "schema PÓS-FOR-198 criado (crawler_queue + pagamentos_consultas_log já com erro_categoria)"

psql_ -d sandbox -f "$ROOT/sql/2026-10-04_for199_rpc_erro_categoria.sql" >/dev/null
ok "migration FOR-199 aplicada"

# ---- crawler_queue_erro_categoria_counts ---------------------------------------------------
psql_ -d sandbox -c "
  INSERT INTO crawler_queue (processo_codigo, status, erro_categoria) VALUES
    ('A', 'erro', 'rate_limit'),
    ('B', 'erro', 'rate_limit'),
    ('C', 'erro', 'bloqueio_suspeito'),
    ('D', 'erro', NULL),
    ('E', 'ok',   NULL),
    ('F', 'pendente', NULL)
" >/dev/null

eq "$(val "select count(*) from crawler_queue_erro_categoria_counts()")" "3" \
  "3 grupos distintos (rate_limit, bloqueio_suspeito, NULL) — só status='erro', ignora ok/pendente"
eq "$(val "select n from crawler_queue_erro_categoria_counts() where erro_categoria='rate_limit'")" "2" \
  "rate_limit conta 2"
eq "$(val "select n from crawler_queue_erro_categoria_counts() where erro_categoria is null")" "1" \
  "NULL (não classificado) sai como categoria própria, não é descartado"
eq "$(val "select coalesce(sum(n),0) from crawler_queue_erro_categoria_counts()")" "4" \
  "soma total bate com os 4 jobs em status='erro' (A,B,C,D) — E/F (ok/pendente) não entram"

eq "$(val "select has_function_privilege('anon', 'crawler_queue_erro_categoria_counts()', 'execute')")" "t" \
  "anon tem EXECUTE (admin roda anônimo)"
eq "$(val "select has_function_privilege('authenticated', 'crawler_queue_erro_categoria_counts()', 'execute')")" "t" \
  "authenticated tem EXECUTE"

# ---- pagamentos_consultas_resumo ------------------------------------------------------------
psql_ -d sandbox -c "
  INSERT INTO pagamentos_consultas_log (processo_depre, iniciada_em, origem, resultado, erro_categoria) VALUES
    ('P1', now() - interval '1 hour',  'crawler', 'encontrado', NULL),
    ('P2', now() - interval '2 hours', 'crawler', 'nao_consta', NULL),
    ('P3', now() - interval '3 hours', 'crawler', 'falha', 'captcha'),
    ('P4', now() - interval '4 hours', 'crawler', 'falha', 'captcha'),
    ('P5', now() - interval '5 hours', 'crawler', 'falha', 'timeout'),
    ('P6', now() - interval '30 hours', 'crawler', 'falha', 'outro')
" >/dev/null

eq "$(val "select (pagamentos_consultas_resumo()->>'total')")" "5" \
  "total das últimas 24h = 5 (P1..P5; P6 está fora da janela, há 30h)"
eq "$(val "select (pagamentos_consultas_resumo()->>'sucesso')")" "2" \
  "sucesso = encontrado + nao_consta (P1, P2) — resultado <> 'falha'"
eq "$(val "select (pagamentos_consultas_resumo()->>'falhas')")" "3" \
  "falhas = P3, P4, P5 (P6 fora da janela não conta)"
eq "$(val "select jsonb_array_length(pagamentos_consultas_resumo()->'falhas_por_categoria')")" "2" \
  "2 categorias de falha na janela (captcha, timeout) — 'outro' (P6) está fora da janela"
eq "$(val "select (elem->>'n') from jsonb_array_elements(pagamentos_consultas_resumo()->'falhas_por_categoria') elem where elem->>'erro_categoria'='captcha'")" "2" \
  "captcha conta 2 na janela de 24h"

eq "$(val "select has_function_privilege('anon', 'pagamentos_consultas_resumo()', 'execute')")" "t" \
  "anon tem EXECUTE (pagamentos_consultas_log só é lido via RPC, mesmo padrão de listar_consultas_pagamento)"
eq "$(val "select has_function_privilege('authenticated', 'pagamentos_consultas_resumo()', 'execute')")" "t" \
  "authenticated tem EXECUTE"
eq "$(val "select has_function_privilege('service_role', 'pagamentos_consultas_resumo()', 'execute')")" "t" \
  "service_role tem EXECUTE"

echo
echo "FOR-199 sandbox: TODOS OS CENÁRIOS OK"
