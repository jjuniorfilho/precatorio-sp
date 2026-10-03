#!/usr/bin/env bash
#
# FOR-195c — valida que buscar_processos_incidente passa a expor processo_cnj (achado em
# produção: a coluna já era calculada internamente — só nunca saía no SELECT final/RETURNS
# TABLE). Schema mínimo o suficiente pra rodar a função de verdade (todas as tabelas que ela
# referencia, mesmo vazias nas que não importam pro teste).
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for195c_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54348}"
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

# Schema mínimo — todas as tabelas que buscar_processos_incidente/_where_processo_incidente
# referenciam (algumas ficam vazias, só precisam existir pras subqueries não quebrarem).
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text UNIQUE, cnj text, cnj_normalizado text,
  flag_sp boolean NOT NULL DEFAULT true, ente_esfera text, ente_nome text,
  last_crawled_at timestamptz
);
CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id), processo_codigo text UNIQUE, cnj text, cnj_normalizado text
);
CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cumprimento_id uuid REFERENCES cumprimentos(id), processo_id uuid NOT NULL REFERENCES processos(id),
  processo_codigo text UNIQUE, numero_incidente text, numero_depre text, valor_acao bigint,
  fase text, fase_desde date, status text, tipo_previsto text, macrofase text, elegivel boolean,
  possivelmente_pago boolean, ordem_cronologica boolean, tramitacao_prioritaria boolean,
  ano_oc integer, data_base date, cessao_credito boolean NOT NULL DEFAULT false,
  em_cumprimento_real boolean
);
CREATE TABLE partes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incidente_id uuid REFERENCES incidentes(id),
  processo_id uuid REFERENCES processos(id), papel text, nome text,
  advogado_nome text, oab_normalizada text
);
CREATE TABLE andamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incidente_id uuid REFERENCES incidentes(id), data date
);
CREATE TABLE precatorios (processo_depre text, saldo_depre bigint, updated_at timestamptz);
CREATE TABLE precatorios_pagamentos (processo_depre text, valor bigint);
CREATE TABLE djen_depre (
  cnj_normalizado text, titular_nome text, titular_documento text, acordo_homologado boolean
);
CREATE TABLE crawler_queue (processo_codigo text, status text, updated_at timestamptz);
EOF

psql_ -d sandbox -f "$ROOT/sql/2026-10-01_for189_baseline_where_processo_incidente_live.sql" >/dev/null
ok "baseline _where_processo_incidente/buscar_processos_incidente/contar_processos_incidente aplicada"
psql_ -d sandbox -f "$ROOT/sql/2026-10-03_for195c_expoe_processo_cnj_buscar_processos_incidente.sql" >/dev/null
ok "fix FOR-195c aplicado (processo_cnj no SELECT final)"

# ---- fixture: 1 processo principal, 1 cumprimento, 1 incidente ------------------------------
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj, flag_sp, ente_esfera, ente_nome) VALUES
  ('11111111-1111-1111-1111-111111111111', '1R00001EF0000', '3001797-14.2013.8.26.0063', true, 'Estadual', 'DER');
INSERT INTO cumprimentos (id, processo_id, processo_codigo, cnj) VALUES
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '1R00001EF0000#cump', '0003017-25.2018.8.26.0063');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_incidente, numero_depre, valor_acao) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
   '1R00001EF0000#inc1', '00001', '0124515-33.2021.8.26.0500', 19757356);
EOF

# ---- verifica: processo_cnj vem preenchido, demais colunas intactas -------------------------
eq "$(val "select processo_cnj from buscar_processos_incidente()")" "3001797-14.2013.8.26.0063" "processo_cnj exposto corretamente"
eq "$(val "select cumprimento_cnj from buscar_processos_incidente()")" "0003017-25.2018.8.26.0063" "cumprimento_cnj continua certo (coluna preexistente intocada)"
eq "$(val "select numero_depre from buscar_processos_incidente()")" "0124515-33.2021.8.26.0500" "numero_depre continua certo"
eq "$(val "select count(*) from buscar_processos_incidente()")" "1" "1 linha só (sem duplicar)"

# contar_processos_incidente (não muda, mas confirma que continua funcionando lado a lado)
eq "$(val "select contar_processos_incidente()")" "1" "contar_processos_incidente inalterado"

SIG="buscar_processos_incidente(text,text,text,text,text,text,text,bigint,bigint,boolean,text,date,date,integer,integer,text,integer,boolean,date,date,boolean,boolean,text)"
eq "$(val "select has_function_privilege('anon', '$SIG', 'execute')")" "t" "anon preserva EXECUTE após DROP+CREATE (grant reconcedido)"

echo
echo "FOR-195c sandbox: TODOS OS CENÁRIOS OK"
