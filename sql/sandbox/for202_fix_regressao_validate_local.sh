#!/usr/bin/env bash
#
# FOR-202 (fix pós-aplicação) — confirma que aplicar
# sql/2026-10-21_for202_fix_backfill_revoke_e_corrida.sql POR CIMA do backfill original
# não quebra nenhum comportamento já validado em for202_backfill_validate_local.sh:
# correção seletiva básica, grants fechados, e paginação multi-tick (a lógica do cursor
# mudou — de "max(v_max_id) via subquery" pra "v_ids[v_tamanho] via array_agg ORDER BY",
# já que uuid não tem função max() agregada, achado ao rodar este mesmo teste pela
# primeira vez).
#
# Requer PostgreSQL 15+. Uso: sql/sandbox/for202_fix_regressao_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54356}"
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

psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE TABLE processos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_codigo text UNIQUE NOT NULL, andamentos jsonb, last_crawled_at timestamptz, next_crawl_at timestamptz, updated_at timestamptz DEFAULT now());
CREATE TABLE cumprimentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_id uuid REFERENCES processos(id), processo_codigo text UNIQUE NOT NULL, andamentos jsonb);
CREATE TABLE incidentes (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_id uuid REFERENCES processos(id), cumprimento_id uuid REFERENCES cumprimentos(id), processo_codigo text UNIQUE NOT NULL, numero_depre text, cessao_credito boolean, updated_at timestamptz DEFAULT now());
CREATE TABLE andamentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incidente_id uuid NOT NULL REFERENCES incidentes(id), data date, descricao text, arquivo_url text, hash text);
CREATE TABLE coleta_runs (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), rotina text NOT NULL, status text NOT NULL, started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz, itens_ok int, itens_erro int, detalhe jsonb);
CREATE SCHEMA cron;
CREATE FUNCTION cron.schedule(text, text, text) RETURNS bigint LANGUAGE sql AS $$ SELECT 1::bigint $$;
EOF
ok "schema mínimo + roles anon/authenticated (pra testar o REVOKE de verdade)"

psql_ -d sandbox -f "$ROOT/sql/2026-10-21_for202_backfill_cessao_credito.sql" >/dev/null
ok "backfill original aplicado"
psql_ -d sandbox -f "$ROOT/sql/2026-10-21_for202_fix_backfill_revoke_e_corrida.sql" >/dev/null
ok "fix aplicado por cima, sem erro (inclusive o CREATE OR REPLACE da função)"

# ---- Grants fechados --------------------------------------------------------------
eq "$(val "select count(*) from information_schema.role_table_grants where table_name='for202_backfill_cessao_credito_estado' and grantee in ('anon','authenticated')")" "0" \
  "tabela de estado: zero grants pra anon/authenticated"
eq "$(val "select has_function_privilege('anon', 'public.for202_backfill_cessao_credito_tick()', 'execute')")" "f" \
  "função tick: anon NÃO tem mais EXECUTE"
eq "$(val "select has_function_privilege('authenticated', 'public.for202_backfill_cessao_credito_tick()', 'execute')")" "f" \
  "função tick: authenticated NÃO tem mais EXECUTE"

# ---- Correção seletiva básica continua igual (mesmo resultado do script original) -----
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo) VALUES ('00000000-0000-0000-0000-000000000001', 'P1');
INSERT INTO cumprimentos (id, processo_id, processo_codigo) VALUES ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-000000000001', 'C1');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, cessao_credito) VALUES
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'IA', false),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'IB', false),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'ID', true);
INSERT INTO andamentos (incidente_id, data, descricao, hash) VALUES ('00000000-0000-0000-0000-00000000a002', '2024-01-01', 'Qualquer andamento', 'h1');
EOF
psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select cessao_credito is null from incidentes where processo_codigo='IA'")" "t" "pós-fix: IA ainda vira NULL (sem andamento)"
eq "$(val "select cessao_credito from incidentes where processo_codigo='IB'")" "f" "pós-fix: IB ainda fica false (tem andamento)"
eq "$(val "select cessao_credito from incidentes where processo_codigo='ID'")" "t" "pós-fix: ID continua true (guard intacto)"

# ---- Paginação multi-tick continua igual (cursor mudou de implementação: de
# "max(v_max_id)" pra "v_ids[v_tamanho] via array_agg ORDER BY id", já que uuid não tem
# função max() agregada — achado AO RODAR este teste pela 1ª vez, corrigido na migration) --
psql_ -d sandbox <<'EOF'
TRUNCATE incidentes, andamentos, cumprimentos, processos CASCADE;
DELETE FROM for202_backfill_cessao_credito_estado;
INSERT INTO for202_backfill_cessao_credito_estado (id) VALUES (true);
INSERT INTO incidentes (processo_codigo, cessao_credito) SELECT 'BULK-' || gs, false FROM generate_series(1, 3005) gs;
EOF
psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select total_corrigidos from for202_backfill_cessao_credito_estado")" "3000" "1º tick: lote cheio de 3000"
eq "$(val "select ativo from for202_backfill_cessao_credito_estado")" "t" "1º tick: ainda ativo (tem mais)"
psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select total_corrigidos from for202_backfill_cessao_credito_estado")" "3005" "2º tick: completa os 3005"
eq "$(val "select ativo from for202_backfill_cessao_credito_estado")" "f" "2º tick: autodesliga (lote incompleto)"

echo
echo "FOR-202 fix regressão sandbox: TODOS OS CENÁRIOS OK"
