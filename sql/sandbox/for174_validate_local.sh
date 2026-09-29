#!/usr/bin/env bash
#
# FOR-174 (achado em produção) — valida a correção da RLS de precatorios_pagamentos num
# Postgres LOCAL descartável (nunca toca produção).
#
# Reproduz o bug de verdade (não só o texto do SQL): cria a tabela + RLS exatamente como em
# produção (sql/2026-07-21_pagamentos_tjsp.sql + 2026-07-22_fix_precatorios_pagamentos_index.sql),
# prova que um INSERT direto como `authenticated` falha com RLS (baseline do bug), aplica o fix
# (sql/2026-09-29_for174_fix_upsert_pagamentos_rls.sql) e prova que a RPC funciona como
# `authenticated`, é idempotente (upsert) e não abre uma policy geral de INSERT.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for174_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54331}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
[[ -x "$PGBIN/initdb" ]] || { echo "ERRO: initdb não encontrado em $PGBIN (defina PGBIN)"; exit 2; }

cleanup() { "$PGBIN/pg_ctl" -D "$TMP/data" -m immediate stop >/dev/null 2>&1 || true; rm -rf "$TMP"; }
trap cleanup EXIT

psql_() { "$PGBIN/psql" -h 127.0.0.1 -p "$PORT" -U postgres -q -v ON_ERROR_STOP=1 "$@"; }
falha() { echo "✘ $*" >&2; exit 1; }
ok() { echo "✔ $*"; }

"$PGBIN/initdb" -D "$TMP/data" --auth=trust -U postgres >/dev/null
"$PGBIN/pg_ctl" -D "$TMP/data" -o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" -l "$TMP/pg.log" -w start >/dev/null
psql_ -c "CREATE DATABASE sandbox" postgres

# --- Réplica mínima do schema real: extensão, roles anon/authenticated (papel do Supabase, com os
# GRANTs de schema que o Supabase concede por padrão — sem eles o erro seria "permission denied"
# genérico em vez da RLS específica que apareceu no log real de produção), stub de `precatorios`
# (só o suficiente pro ALTER TABLE do arquivo original não falhar), a tabela e a RLS EXATAS de
# produção (sql/2026-07-21 + sql/2026-07-22).
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN;
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO anon, authenticated;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT, INSERT, UPDATE ON TABLES TO anon, authenticated;
CREATE TABLE public.precatorios (processo_depre TEXT PRIMARY KEY);
EOF
psql_ -d sandbox -f "$ROOT/sql/2026-07-21_pagamentos_tjsp.sql" 2>&1 | grep -v NOTICE || true
psql_ -d sandbox -f "$ROOT/sql/2026-07-22_fix_precatorios_pagamentos_index.sql" 2>&1 | grep -v NOTICE || true
ok "réplica de precatorios_pagamentos (schema + RLS de produção) carregada"

# --- Baseline: reproduz o bug — INSERT direto como `authenticated` falha com RLS.
erro_baseline="$(psql_ -d sandbox -Atc "
  SET ROLE authenticated;
  INSERT INTO precatorios_pagamentos (processo_depre, data_pagamento, valor, tipo)
  VALUES ('0253361-73.2018.8.26.0500', '2020-01-01', 100000, 'Preferência');
" 2>&1 || true)"
echo "$erro_baseline" | grep -qi "row-level security policy" \
  || falha "baseline não reproduziu o bug (esperava RLS violation); saída: $erro_baseline"
ok "baseline confirmado: INSERT direto como authenticated falha com RLS (reproduz o log real de produção)"
[[ "$(psql_ -d sandbox -Atc "SELECT count(*) FROM precatorios_pagamentos")" == "0" ]] \
  || falha "não deveria ter gravado nada no baseline"

# --- Aplica o fix, 2x (re-executável).
for rodada in 1 2; do
  erros="$(psql_ -d sandbox -f "$ROOT/sql/2026-09-29_for174_fix_upsert_pagamentos_rls.sql" 2>&1 | grep -c 'ERROR' || true)"
  [[ "$erros" == "0" ]] || falha "migration deu erro na rodada ${rodada}"
done
ok "migration aplicada 2x sem erro (re-executável)"

# --- A RPC funciona como `authenticated` (o mesmo role que falhava no baseline).
psql_ -d sandbox -Atc "
  SET ROLE authenticated;
  SELECT upsert_precatorios_pagamentos(
    '0253361-73.2018.8.26.0500',
    '[{\"data\":\"2020-01-01\",\"valor\":100000,\"tipo\":\"Preferência\"},
      {\"data\":\"2020-02-01\",\"valor\":50000,\"tipo\":null}]'::jsonb
  );
"
n="$(psql_ -d sandbox -Atc "SELECT count(*) FROM precatorios_pagamentos WHERE processo_depre='0253361-73.2018.8.26.0500'")"
[[ "$n" == "2" ]] || falha "esperava 2 linhas gravadas via RPC, achou $n"
ok "RPC grava como authenticated (achado real: 17 pagamentos que hoje se perdem passam a persistir)"

# --- data=null é descartado (mesmo filtro que o worker já fazia em memória — data_pagamento é NOT NULL).
psql_ -d sandbox -c "
  SET ROLE authenticated;
  SELECT upsert_precatorios_pagamentos('0253361-73.2018.8.26.0500', '[{\"data\":null,\"valor\":999,\"tipo\":\"x\"}]'::jsonb);
"
n="$(psql_ -d sandbox -Atc "SELECT count(*) FROM precatorios_pagamentos WHERE processo_depre='0253361-73.2018.8.26.0500'")"
[[ "$n" == "2" ]] || falha "pagamento com data=null não deveria ter sido gravado (esperava continuar em 2, achou $n)"
ok "pagamento sem data é descartado, nunca lança (data_pagamento é NOT NULL)"

# --- Idempotência: reconsultar (mesmos dados) não duplica.
psql_ -d sandbox -c "
  SET ROLE authenticated;
  SELECT upsert_precatorios_pagamentos(
    '0253361-73.2018.8.26.0500',
    '[{\"data\":\"2020-01-01\",\"valor\":100000,\"tipo\":\"Preferência\"}]'::jsonb
  );
"
n="$(psql_ -d sandbox -Atc "SELECT count(*) FROM precatorios_pagamentos WHERE processo_depre='0253361-73.2018.8.26.0500'")"
[[ "$n" == "2" ]] || falha "reconsulta com o mesmo pagamento duplicou (esperava continuar em 2, achou $n)"
ok "idempotente: reconsultar o mesmo pagamento não duplica (ON CONFLICT DO NOTHING)"

# --- Blast radius: nenhuma policy geral de INSERT foi aberta (o INSERT direto continua bloqueado
# pra authenticated — só a RPC, que valida o shape via SECURITY DEFINER, tem acesso).
erro_direto="$(psql_ -d sandbox -Atc "
  SET ROLE authenticated;
  INSERT INTO precatorios_pagamentos (processo_depre, data_pagamento, valor, tipo)
  VALUES ('outro-depre', '2020-01-01', 1, '');
" 2>&1 || true)"
echo "$erro_direto" | grep -qi "row-level security policy" \
  || falha "INSERT direto deveria CONTINUAR bloqueado (o fix não deve abrir uma policy geral)"
ok "blast radius contido: INSERT direto continua bloqueado, só a RPC ganhou acesso"

echo
echo "=== FOR-174 (fix RLS pagamentos): tudo ok ==="
