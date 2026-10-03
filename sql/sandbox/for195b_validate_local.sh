#!/usr/bin/env bash
#
# FOR-195b — valida o fix de merge_legado_cumprimento_para_principal (backfill de
# incidentes.cumprimento_id) num Postgres LOCAL descartável.
#
# Achado real (validação do caso-teste em produção, 2026-10-03): o fixture do sandbox original
# (for195_validate_local.sh, cenário A) criava o incidente já com cumprimento_id PREENCHIDO —
# não reproduz a forma real dos ~11.202 candidatos (98% com cumprimento_id NULL, heurística
# FOR-178). Por isso aquele sandbox não pegou o bug: o caminho que ele testou não é o caminho
# que a imensa maioria dos dados reais percorre. Este script corrige o fixture (cumprimento_id
# NULL no início, como no legado de verdade) e adiciona o cenário que faltava.
#
# Cenários:
#   A) incidente com cumprimento_id NULL (caso real) → depois do merge, cumprimento_id passa a
#      apontar pra linha `cumprimentos` nova (o antigo "processo" convertido).
#   B) incidente que JÁ tinha cumprimento_id preenchido (hierarquia normal, não-legado) → nunca é
#      sobrescrito pelo merge (coalesce preserva o valor original).
#   C) idempotência (2ª chamada) → no-op, cumprimento_id inalterado.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for195b_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54347}"
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

# Schema mínimo espelhando FOR-69 (mesmas FKs ON DELETE CASCADE e UNIQUE de processo_codigo).
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text NOT NULL UNIQUE, cnj text, cnj_normalizado text
);
CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  processo_codigo text NOT NULL UNIQUE, cnj text, cnj_normalizado text
);
CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cumprimento_id uuid REFERENCES cumprimentos(id) ON DELETE CASCADE,
  processo_id uuid NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  processo_codigo text NOT NULL UNIQUE, numero_depre text, cnj text
);
CREATE TABLE partes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id uuid NOT NULL REFERENCES incidentes(id) ON DELETE CASCADE,
  processo_id uuid NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  papel text NOT NULL, nome text
);
EOF

psql_ -d sandbox -f "$ROOT/sql/2026-10-03_for195b_fix_incidentes_cumprimento_id.sql" >/dev/null 2>&1 || true
# a correção retroativa no fim do arquivo referencia ids de produção que não existem aqui —
# aplica só a função, separadamente, pra não poluir a saída com um UPDATE 0 esperado.
psql_ -d sandbox -c "$(sed -n '/^create or replace function/,/^grant execute/p' "$ROOT/sql/2026-10-03_for195b_fix_incidentes_cumprimento_id.sql")" >/dev/null
ok "migration aplicada (FOR-195b fix)"

# ---- A) caso REAL: incidente com cumprimento_id NULL (legado, FOR-178) ----------------------
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('11111111-1111-1111-1111-111111111111', 'LEGADO-00180281320228260562', '0018028-13.2022.8.26.0562', '00180281320228260562');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre, cnj) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', NULL,
   'LEGADO-00180281320228260562-00001', '0436868-90.2025.8.26.0500', '0018028-13.2022.8.26.0562');
INSERT INTO partes (incidente_id, processo_id, papel, nome) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'ativa', 'Claudio Mauricio Santos');
EOF

PRINCIPAL_ID="$(val "INSERT INTO processos (processo_codigo, cnj, cnj_normalizado)
  VALUES ('FM000RJ270000', '1000594-91.2022.8.26.0562', '10005949120228260562')
  ON CONFLICT (processo_codigo) DO UPDATE SET cnj = EXCLUDED.cnj
  RETURNING id")"

psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('11111111-1111-1111-1111-111111111111', '$PRINCIPAL_ID')" >/dev/null

eq "$(val "SELECT count(*) FROM processos WHERE processo_codigo LIKE 'LEGADO-%'")" "0" "[A] processos legado (cumprimento promovido a raiz por engano) apagado"
eq "$(val "SELECT processo_id FROM incidentes WHERE id = '33333333-3333-3333-3333-333333333333'")" "$PRINCIPAL_ID" "[A] incidente reapontado pro principal"
CUMP_ID="$(val "SELECT cumprimento_id FROM incidentes WHERE id = '33333333-3333-3333-3333-333333333333'")"
[[ -n "$CUMP_ID" ]] && ok "[A] cumprimento_id NÃO é mais NULL ($CUMP_ID) — achado real corrigido" || falha "[A] cumprimento_id continua NULL — bug NÃO corrigido"
eq "$(val "SELECT processo_id FROM cumprimentos WHERE id = '$CUMP_ID'")" "$PRINCIPAL_ID" "[A] a linha cumprimentos apontada é a do principal certo"
eq "$(val "SELECT cnj FROM cumprimentos WHERE id = '$CUMP_ID'")" "0018028-13.2022.8.26.0562" "[A] cnj da linha cumprimentos é o do CUMPRIMENTO, não o do principal"
eq "$(val "SELECT processo_id FROM partes WHERE incidente_id = '33333333-3333-3333-3333-333333333333'")" "$PRINCIPAL_ID" "[A] partes reapontadas pro principal"

# ---- B) hierarquia normal: incidente JÁ tinha cumprimento_id — nunca sobrescrito -------------
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj) VALUES
  ('44444444-4444-4444-4444-444444444444', '1H0000OUTRO', '0099999-00.2023.8.26.0562');
INSERT INTO cumprimentos (id, processo_id, processo_codigo, cnj) VALUES
  ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444', '1H0000OUTRO#cump', '0099999-00.2023.8.26.0562');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre) VALUES
  ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555',
   '1H0000INC-B', '0055555-00.2023.8.26.0500');
EOF
psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('44444444-4444-4444-4444-444444444444', '$PRINCIPAL_ID')" >/dev/null
eq "$(val "SELECT cumprimento_id FROM incidentes WHERE id = '66666666-6666-6666-6666-666666666666'")" "55555555-5555-5555-5555-555555555555" "[B] cumprimento_id pré-existente PRESERVADO (coalesce não sobrescreve)"

# ---- C) idempotência ---------------------------------------------------------------------------
psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('11111111-1111-1111-1111-111111111111', '$PRINCIPAL_ID')" >/dev/null
eq "$(val "SELECT cumprimento_id FROM incidentes WHERE id = '33333333-3333-3333-3333-333333333333'")" "$CUMP_ID" "[C] 2ª chamada é no-op — cumprimento_id inalterado"

echo
echo "FOR-195b sandbox: TODOS OS CENÁRIOS OK"
