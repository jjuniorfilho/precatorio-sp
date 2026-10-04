#!/usr/bin/env bash
#
# FOR-198 — valida as 2 migrations de erro_categoria (crawler_queue + pagamentos_consultas_log)
# num Postgres local efêmero, ANTES de pedir aplicação manual no SQL Editor de produção.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for198_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54349}"
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

# Schema mínimo: só o que as 2 migrations tocam (crawler_queue/fail_crawler_job,
# pagamentos_consultas_log/registrar_consulta_pagamento), nas assinaturas ANTIGAS — pra provar
# que o DROP+CREATE funciona de cima de um estado real pré-FOR-198, não de um schema já migrado.
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
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION fail_crawler_job(p_id UUID, p_erro TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE crawler_queue
     SET tentativas   = tentativas + 1,
         erro         = p_erro,
         updated_at   = NOW(),
         status       = CASE WHEN tentativas + 1 >= 3 THEN 'erro' ELSE 'pendente' END,
         scheduled_at = CASE WHEN tentativas + 1 >= 3 THEN scheduled_at
                             ELSE NOW() + (ARRAY['15 minutes','1 hour'])[tentativas + 1]::interval END
   WHERE id = p_id;
END; $$;
GRANT EXECUTE ON FUNCTION fail_crawler_job(UUID, TEXT) TO service_role;

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
  passos               jsonb       NOT NULL DEFAULT '[]'::jsonb,
  criado_em            timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.registrar_consulta_pagamento(
  p_processo_depre       text,
  p_iniciada_em          timestamptz,
  p_finalizada_em        timestamptz,
  p_origem               text,
  p_resultado            text,
  p_tentativas           integer,
  p_situacao             text,
  p_qtd_pagamentos       integer,
  p_data_consulta_portal text,
  p_erro                 text,
  p_etapa_falha          text,
  p_passos               jsonb
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_processo_depre IS NULL OR p_processo_depre !~ '\.8\.26\.0500$' THEN
    RAISE EXCEPTION 'processo_depre inválido (esperado terminar em .8.26.0500)';
  END IF;
  INSERT INTO pagamentos_consultas_log (
    processo_depre, iniciada_em, finalizada_em, origem, resultado, tentativas, situacao,
    qtd_pagamentos, data_consulta_portal, erro, etapa_falha, passos
  ) VALUES (
    p_processo_depre, LEAST(p_iniciada_em, now()), LEAST(p_finalizada_em, now()), p_origem, p_resultado, LEAST(GREATEST(COALESCE(p_tentativas, 0), 0), 100), left(p_situacao, 200),
    p_qtd_pagamentos, left(p_data_consulta_portal, 40), left(p_erro, 1000), left(p_etapa_falha, 40),
    CASE WHEN p_passos IS NOT NULL AND jsonb_typeof(p_passos) = 'array' AND octet_length(p_passos::text) <= 20000 THEN p_passos ELSE '[]'::jsonb END
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.registrar_consulta_pagamento(text, timestamptz, timestamptz, text, text, integer, text, integer, text, text, text, jsonb) TO authenticated, service_role;
EOF
ok "schema PRÉ-FOR-198 criado (assinaturas antigas de fail_crawler_job/registrar_consulta_pagamento)"

psql_ -d sandbox -f "$ROOT/sql/2026-10-04_for198_1_erro_categoria_crawler_queue.sql" >/dev/null
ok "migration 1/2 (crawler_queue) aplicada"
psql_ -d sandbox -f "$ROOT/sql/2026-10-04_for198_2_erro_categoria_pagamentos_consultas_log.sql" >/dev/null
ok "migration 2/2 (pagamentos_consultas_log) aplicada"

# ---- crawler_queue / fail_crawler_job ------------------------------------------------------
psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('11111111-1111-1111-1111-111111111111', 'SEED1')" >/dev/null

psql_ -d sandbox -c "select fail_crawler_job('11111111-1111-1111-1111-111111111111'::uuid, 'HTTP 429', 'rate_limit')" >/dev/null
eq "$(val "select erro_categoria from crawler_queue where id='11111111-1111-1111-1111-111111111111'")" "rate_limit" "fail_crawler_job persiste erro_categoria"
eq "$(val "select tentativas from crawler_queue where id='11111111-1111-1111-1111-111111111111'")" "1" "tentativas segue incrementando (comportamento antigo intocado)"
eq "$(val "select status from crawler_queue where id='11111111-1111-1111-1111-111111111111'")" "pendente" "status segue a mesma regra (< 3 tentativas)"

# chamada SEM p_categoria (compat — chamador antigo continuaria funcionando)
psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('22222222-2222-2222-2222-222222222222', 'SEED2')" >/dev/null
psql_ -d sandbox -c "select fail_crawler_job('22222222-2222-2222-2222-222222222222'::uuid, 'algo')" >/dev/null
eq "$(val "select erro_categoria from crawler_queue where id='22222222-2222-2222-2222-222222222222'")" "" "fail_crawler_job sem p_categoria → erro_categoria fica NULL (default preservado)"

# CHECK rejeita categoria fora da lista
if psql_ -d sandbox -c "select fail_crawler_job('11111111-1111-1111-1111-111111111111'::uuid, 'x', 'categoria_invalida')" >/dev/null 2>&1; then
  falha "CHECK deveria ter rejeitado categoria fora da lista"
fi
ok "CHECK rejeita erro_categoria fora das 7 categorias"

eq "$(val "select has_function_privilege('service_role', 'fail_crawler_job(uuid,text,text)', 'execute')")" "t" "service_role preserva EXECUTE após DROP+CREATE"
eq "$(val "select has_function_privilege('anon', 'fail_crawler_job(uuid,text,text)', 'execute')")" "f" "anon NÃO tem EXECUTE (mesma restrição de antes)"

# ---- pagamentos_consultas_log / registrar_consulta_pagamento -----------------------------
psql_ -d sandbox -c "select registrar_consulta_pagamento('0088499-12.2023.8.26.0500', now(), now(), 'crawler', 'falha', 2, null, null, null, 'captcha não resolvido após 4 tentativas', 'busca', '[]'::jsonb, 'captcha')" >/dev/null
eq "$(val "select erro_categoria from pagamentos_consultas_log where processo_depre='0088499-12.2023.8.26.0500'")" "captcha" "registrar_consulta_pagamento persiste erro_categoria"

# chamada SEM p_categoria (compat)
psql_ -d sandbox -c "select registrar_consulta_pagamento('0088499-12.2023.8.26.0500', now(), now(), 'manual', 'nao_consta', 1, 'Pendente', 0, '01/01/2026', null, null, '[]'::jsonb)" >/dev/null
eq "$(val "select erro_categoria from pagamentos_consultas_log where resultado='nao_consta' and processo_depre='0088499-12.2023.8.26.0500'")" "" "registrar_consulta_pagamento sem p_categoria → NULL (compat preservada)"

if psql_ -d sandbox -c "select registrar_consulta_pagamento('0088499-12.2023.8.26.0500', now(), now(), 'manual', 'falha', 1, null, null, null, 'x', 'busca', '[]'::jsonb, 'categoria_invalida')" >/dev/null 2>&1; then
  falha "CHECK deveria ter rejeitado categoria fora da lista (pagamentos_consultas_log)"
fi
ok "CHECK rejeita erro_categoria fora das 7 categorias (pagamentos_consultas_log)"

eq "$(val "select has_function_privilege('authenticated', 'registrar_consulta_pagamento(text,timestamptz,timestamptz,text,text,integer,text,integer,text,text,text,jsonb,text)', 'execute')")" "t" "authenticated preserva EXECUTE após DROP+CREATE (worker em modo Opção B)"

echo
echo "FOR-198 sandbox: TODOS OS CENÁRIOS OK"
