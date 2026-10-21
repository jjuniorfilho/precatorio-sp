#!/usr/bin/env bash
#
# FOR-202 — valida que p_cessao_credito ('sim'|'nao'|'nao_verificado') de fato filtra
# em buscar_processos_incidente/contar_processos_incidente, num Postgres local efêmero.
# Cobre o bug achado em produção: o parâmetro existia na assinatura mas o corpo da
# função não tinha nenhum bloco que o usasse (filtro era no-op).
#
# Requer PostgreSQL 15+. Uso: sql/sandbox/for202_rpcs_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54354}"
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

# Schema mínimo — só o necessário pras 3 RPCs compilarem e rodarem. Tabelas referenciadas
# em subqueries não usadas pelo teste (precatorios, precatorios_pagamentos, djen_depre,
# crawler_queue, partes) entram vazias, só pra satisfazer o planner.
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cnj text, cnj_normalizado text, ente_esfera text, ente_nome text,
  flag_sp boolean NOT NULL DEFAULT true, last_crawled_at timestamptz
);
CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id), cnj text, cnj_normalizado text
);
CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id), cumprimento_id uuid REFERENCES cumprimentos(id),
  numero_incidente text, numero_depre text, cnj text, cnj_normalizado text,
  tipo_previsto text, macrofase text, fase text, fase_desde date,
  elegivel boolean, possivelmente_pago boolean, ordem_cronologica boolean,
  tramitacao_prioritaria boolean, ano_oc integer, em_cumprimento_real boolean,
  cessao_credito boolean, valor_acao bigint, data_base date, status text
);
CREATE TABLE andamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incidente_id uuid REFERENCES incidentes(id),
  data date, descricao text
);
CREATE TABLE partes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incidente_id uuid REFERENCES incidentes(id),
  processo_id uuid, papel text, nome text, advogado_nome text, oab_normalizada text
);
CREATE TABLE djen_depre (
  id bigint PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
  cnj_normalizado text UNIQUE NOT NULL, acordo_homologado boolean,
  titular_nome text, titular_documento text
);
CREATE TABLE precatorios (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_depre text, saldo_depre bigint);
CREATE TABLE precatorios_pagamentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_depre text, valor bigint);
CREATE TABLE crawler_queue (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_codigo text, status text, updated_at timestamptz);
EOF
ok "schema mínimo criado (stubs pras tabelas referenciadas em subqueries não testadas)"

psql_ -d sandbox -f "$ROOT/sql/2026-10-21_for202_rpcs_cessao_credito_enum.sql" >/dev/null
ok "migration FOR-202 (RPCs) aplicada"

# ---- Fixture: 3 incidentes, 1 em cada estado -----------------------------------------
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, flag_sp) VALUES
  ('00000000-0000-0000-0000-000000000001', true);
INSERT INTO incidentes (id, processo_id, cessao_credito, valor_acao) VALUES
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000001', true,  100),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000001', false, 200),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-000000000001', NULL,  300);
EOF
ok "fixture: I1=true, I2=false, I3=NULL (não verificado)"

eq "$(val "select contar_processos_incidente(p_cessao_credito := 'sim')")" "1" \
  "'sim' filtra só o true — ANTES desta migration (bug), isso retornava 3 (filtro era no-op)"
eq "$(val "select contar_processos_incidente(p_cessao_credito := 'nao')")" "1" \
  "'nao' filtra só o false"
eq "$(val "select contar_processos_incidente(p_cessao_credito := 'nao_verificado')")" "1" \
  "'nao_verificado' filtra só o NULL"
eq "$(val "select contar_processos_incidente()")" "3" \
  "sem filtro (null) continua retornando todos os 3 — comportamento 'Todos' preservado"
eq "$(val "select contar_processos_incidente(p_cessao_credito := 'lixo')")" "3" \
  "valor fora do enum é no-op silencioso (mesmo espírito defensivo do resto da função), não erro"

eq "$(val "select cessao_credito from buscar_processos_incidente(p_cessao_credito := 'sim', p_limit := 10)")" "t" \
  "buscar_processos_incidente também filtra corretamente (não só contar)"

echo
echo "FOR-202 RPCs sandbox: TODOS OS CENÁRIOS OK"
