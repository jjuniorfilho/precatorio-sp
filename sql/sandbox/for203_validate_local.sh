#!/usr/bin/env bash
#
# FOR-203 — valida o filtro p_acordo_homologado reescrito (equivalência com a semântica antiga)
# [orig: p_cessao_credito ('sim'|'nao'|'nao_verificado') de fato filtra
# em buscar_processos_incidente/contar_processos_incidente, num Postgres local efêmero.
# Cobre o bug achado em produção: o parâmetro existia na assinatura mas o corpo da
# função não tinha nenhum bloco que o usasse (filtro era no-op).
#
# Requer PostgreSQL 15+. Uso: sql/sandbox/for202_rpcs_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54355}"
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
psql_ -d sandbox -f "$ROOT/sql/2026-10-25_for203_acordo_homologado_filtro_timeout.sql" >/dev/null
ok "migrations FOR-202 + FOR-203 aplicadas"

psql_ -d sandbox <<'EOF2'
INSERT INTO processos (id, flag_sp) VALUES ('00000000-0000-0000-0000-000000000001', true);
INSERT INTO incidentes (processo_id, numero_depre, cessao_credito, valor_acao) VALUES
  ('00000000-0000-0000-0000-000000000001','0357709-45.2018.8.26.0500', false, 1),  -- acordo true
  ('00000000-0000-0000-0000-000000000001','0025461-31.2020.8.26.0500', false, 2),  -- acordo false
  ('00000000-0000-0000-0000-000000000001','0053750-37.2021.8.26.0500', false, 3),  -- djen sem veredito (null)
  ('00000000-0000-0000-0000-000000000001','0999999-99.2021.8.26.0500', false, 4),  -- sem linha em djen
  ('00000000-0000-0000-0000-000000000001', NULL,                       false, 5);  -- sem depre
INSERT INTO djen_depre (cnj_normalizado, acordo_homologado) VALUES
  ('03577094520188260500', true), ('00254613120208260500', false), ('00537503720218260500', NULL);
EOF2

eq "$(val "select contar_processos_incidente(p_acordo_homologado := 'sim')")" "1" "sim"
eq "$(val "select contar_processos_incidente(p_acordo_homologado := 'nao')")" "1" "nao"
eq "$(val "select contar_processos_incidente(p_acordo_homologado := 'nao_verificado')")" "3" "nao_verificado (null verdict + sem djen + sem depre)"
eq "$(val "select contar_processos_incidente(p_acordo_homologado := 'sim', p_cessao_credito := 'nao')")" "1" "combinado com cessao=nao (caso da tela)"
eq "$(val "select count(*) from buscar_processos_incidente(p_acordo_homologado := 'sim', p_cessao_credito := 'nao')")" "1" "buscar"
eq "$(val "select acordo_homologado from buscar_processos_incidente(p_acordo_homologado := 'sim')")" "t" "coluna acordo_homologado do resultado"

eq "$(val "select contar_processos_incidente(p_q := 'abc')")" "0" "q sem dígitos -> vazio (não varre tudo)"
eq "$(val "select contar_processos_incidente(p_q := '12')")" "0" "q com 2 dígitos -> vazio"
eq "$(val "select contar_processos_incidente(p_q := '0357709')")" "1" "q com dígitos suficientes continua achando"

# plano: com massa de dados o filtro tem que usar o btree de numero_depre
psql_ -d sandbox -c "CREATE INDEX idx_incidentes_numero_depre ON incidentes(numero_depre)"
psql_ -d sandbox -c "INSERT INTO incidentes (processo_id, numero_depre, cessao_credito) SELECT '00000000-0000-0000-0000-000000000001', lpad(g::text,7,'0')||'-00.2020.8.26.0500', false FROM generate_series(1,200000) g"
psql_ -d sandbox -c "INSERT INTO djen_depre (cnj_normalizado, acordo_homologado) SELECT lpad(g::text,7,'0')||'0020208260500', true FROM generate_series(1,50) g"
psql_ -d sandbox -c "ANALYZE"
PLANO="$(psql_ -d sandbox -At -c "explain select * from incidentes i join processos p on p.id=i.processo_id where $(val "select _where_processo_incidente(null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,null,'sim')")")"
echo "$PLANO" | grep -q "idx_incidentes_numero_depre" && ok "plano usa idx_incidentes_numero_depre" || { echo "$PLANO"; falha "plano não usa o btree"; }

echo
echo "FOR-203 sandbox: TODOS OS CENÁRIOS OK"
