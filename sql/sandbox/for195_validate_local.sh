#!/usr/bin/env bash
#
# FOR-195 (processo principal real acima do cumprimento, legado) — valida a RPC nova
# merge_legado_cumprimento_para_principal num Postgres LOCAL descartável, reproduzindo o caso
# real confirmado manualmente no e-SAJ: DEPRE 0436868-90.2025.8.26.0500, cumprimento
# 0018028-13.2022.8.26.0562, ação principal real 1000594-91.2022.8.26.0562.
#
# Estado ANTES da RPC (saída da reconciliação FOR-178): processos row = o CUMPRIMENTO
# (0018028-13...), rotulado "raiz" por engano; cumprimentos tem 1 linha sintética sob ele;
# incidentes/partes pendurados nessa hierarquia errada.
#
# Cenários:
#   A) achou o link (processoPrincLink) → reorganiza: cumprimentos/incidentes/partes migram pro
#      principal; o processo antigo (0018028) se torna uma linha `cumprimentos` do principal;
#      `processos` antigo é apagado.
#   B) idempotência (2ª chamada da RPC, processo_atual já apagado) → no-op.
#   C) duas reconciliações diferentes resolvendo pro MESMO principal (2 incidentes legado
#      distintos, 2 cumprimentos "processos" diferentes, ambos sobem pra 1000594) → upsert do
#      principal por processo_codigo (UNIQUE) não duplica `processos`; `cumprimentos` termina
#      com as 2 linhas originais, as duas sob o mesmo principal.
#   D) guardas: processo atual inexistente → no-op; processo principal inexistente → exceção.
#   E) grants: PUBLIC/anon sem EXECUTE; service_role/authenticated com.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for195_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54346}"
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

psql_ -d sandbox -f "$ROOT/sql/2026-10-02_for195_merge_legado_cumprimento_para_principal.sql"
ok "migration aplicada (FOR-195 RPC nova)"

# ---- A) achou o link — reorganiza a hierarquia ------------------------------
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('11111111-1111-1111-1111-111111111111', '1H0000CUMP', '0018028-13.2022.8.26.0562', '00180281320228260562');
INSERT INTO cumprimentos (id, processo_id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', '1H0000CUMP#cumprimento', '0018028-13.2022.8.26.0562', '00180281320228260562');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre, cnj) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222',
   '1H0000INC1', '0436868-90.2025.8.26.0500', '0018028-13.2022.8.26.0562');
INSERT INTO partes (incidente_id, processo_id, papel, nome) VALUES
  ('33333333-3333-3333-3333-333333333333', '11111111-1111-1111-1111-111111111111', 'ativa', 'CREDOR LEGADO');
EOF

# upsert do principal — mesmo padrão de upsertReturningId("processos", row, "processo_codigo")
PRINCIPAL_ID="$(val "INSERT INTO processos (processo_codigo, cnj, cnj_normalizado)
  VALUES ('1H0000PRINC', '1000594-91.2022.8.26.0562', '10005949120228260562')
  ON CONFLICT (processo_codigo) DO UPDATE SET cnj = EXCLUDED.cnj
  RETURNING id")"

psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('11111111-1111-1111-1111-111111111111', '$PRINCIPAL_ID')" >/dev/null

eq "$(val "SELECT count(*) FROM processos WHERE processo_codigo = '1H0000CUMP'")" "0" "[A] processos antigo (cumprimento promovido a raiz por engano) apagado"
eq "$(val "SELECT count(*) FROM processos")" "1" "[A] só o principal em processos"
eq "$(val "SELECT count(*) FROM cumprimentos WHERE processo_id = '$PRINCIPAL_ID'")" "2" "[A] 2 cumprimentos sob o principal (o original + o antigo 'processo' convertido)"
eq "$(val "SELECT count(*) FROM cumprimentos WHERE processo_codigo = '1H0000CUMP' AND processo_id = '$PRINCIPAL_ID'")" "1" "[A] o antigo 'processo' agora é cumprimento do principal"
eq "$(val "SELECT processo_id FROM incidentes WHERE id = '33333333-3333-3333-3333-333333333333'")" "$PRINCIPAL_ID" "[A] incidente reapontado pro principal"
eq "$(val "SELECT cumprimento_id FROM incidentes WHERE id = '33333333-3333-3333-3333-333333333333'")" "22222222-2222-2222-2222-222222222222" "[A] cumprimento_id do incidente preservado (mesma linha cumprimentos, só processo_id mudou)"
eq "$(val "SELECT processo_id FROM partes WHERE incidente_id = '33333333-3333-3333-3333-333333333333'")" "$PRINCIPAL_ID" "[A] partes reapontadas pro principal"

# ---- B) idempotência ---------------------------------------------------------
psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('11111111-1111-1111-1111-111111111111', '$PRINCIPAL_ID')" >/dev/null
eq "$(val "SELECT count(*) FROM processos")" "1" "[B] 2ª chamada é no-op — ainda só 1 processos"
eq "$(val "SELECT count(*) FROM cumprimentos WHERE processo_id = '$PRINCIPAL_ID'")" "2" "[B] cumprimentos inalterado"

# ---- C) 2 reconciliações diferentes resolvendo pro MESMO principal ----------
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('44444444-4444-4444-4444-444444444444', '1H0000CUMP2', '0099999-00.2023.8.26.0562', '00999990020238260562');
INSERT INTO cumprimentos (id, processo_id, processo_codigo, cnj) VALUES
  ('55555555-5555-5555-5555-555555555555', '44444444-4444-4444-4444-444444444444', '1H0000CUMP2#cumprimento', '0099999-00.2023.8.26.0562');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre) VALUES
  ('66666666-6666-6666-6666-666666666666', '44444444-4444-4444-4444-444444444444', '55555555-5555-5555-5555-555555555555',
   '1H0000INC2', '0055555-00.2023.8.26.0500');
EOF
# o script faria o MESMO upsert por processo_codigo='1H0000PRINC' — ON CONFLICT devolve o id já existente, nunca duplica.
PRINCIPAL_ID_2="$(val "INSERT INTO processos (processo_codigo, cnj, cnj_normalizado)
  VALUES ('1H0000PRINC', '1000594-91.2022.8.26.0562', '10005949120228260562')
  ON CONFLICT (processo_codigo) DO UPDATE SET cnj = EXCLUDED.cnj
  RETURNING id")"
eq "$PRINCIPAL_ID_2" "$PRINCIPAL_ID" "[C] upsert por processo_codigo devolve o MESMO id do principal (sem duplicar processos)"

psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('44444444-4444-4444-4444-444444444444', '$PRINCIPAL_ID_2')" >/dev/null
eq "$(val "SELECT count(*) FROM processos")" "1" "[C] ainda só 1 processos (o principal) mesmo com 2 reconciliações"
eq "$(val "SELECT count(*) FROM cumprimentos WHERE processo_id = '$PRINCIPAL_ID'")" "4" "[C] 4 cumprimentos sob o principal (2 originais 22222222/55555555 + os 2 'processos' antigos 11111111/44444444 convertidos)"
eq "$(val "SELECT count(*) FROM incidentes WHERE processo_id = '$PRINCIPAL_ID'")" "2" "[C] os 2 incidentes (de árvores legado diferentes) convergem pro mesmo principal"

# ---- D) guardas ---------------------------------------------------------------
# processo atual inexistente (nunca existiu) → no-op silencioso, sem erro (idempotência).
eq "$(val "SELECT merge_legado_cumprimento_para_principal('99999999-9999-9999-9999-999999999999', '$PRINCIPAL_ID')")" "" "[D] processo atual inexistente → no-op silencioso (idempotência)"

# processo principal inexistente → exceção (nunca apaga o atual às cegas). Processo isolado novo,
# só pra este teste.
psql_ -d sandbox -c "INSERT INTO processos (id, processo_codigo, cnj) VALUES ('77777777-7777-7777-7777-777777777777', '1H0000ISOLADO', 'x')"
if psql_ -d sandbox -c "SELECT merge_legado_cumprimento_para_principal('77777777-7777-7777-7777-777777777777', '99999999-9999-9999-9999-999999999999')" 2>"$TMP/err"; then
  falha "[D] processo principal inexistente devia dar erro"
fi
grep -q "não existe" "$TMP/err" && ok "[D] processo principal inexistente → exceção" || falha "[D] mensagem inesperada: $(cat "$TMP/err")"
eq "$(val "SELECT count(*) FROM processos WHERE id = '77777777-7777-7777-7777-777777777777'")" "1" "[D] após exceção, processo atual continua intacto (rollback)"

# ---- E) grants ----------------------------------------------------------------
SIG="public.merge_legado_cumprimento_para_principal(uuid, uuid)"
eq "$(val "select has_function_privilege('anon', '$SIG', 'execute')")" "f" "[E] anon SEM execute"
eq "$(val "select count(*) from pg_proc p, aclexplode(p.proacl) a where p.proname = 'merge_legado_cumprimento_para_principal' and a.grantee = 0")" "0" "[E] PUBLIC SEM execute"
eq "$(val "select has_function_privilege('authenticated', '$SIG', 'execute')")" "t" "[E] authenticated COM execute"
eq "$(val "select has_function_privilege('service_role', '$SIG', 'execute')")" "t" "[E] service_role COM execute"
eq "$(val "select prosecdef from pg_proc where proname = 'merge_legado_cumprimento_para_principal'")" "t" "[E] security definer"

echo
echo "FOR-195 sandbox: TODOS OS CENÁRIOS OK"
