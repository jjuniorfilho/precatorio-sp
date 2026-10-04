#!/usr/bin/env bash
#
# FOR-200 — valida as 3 migrations (tabela crawler_execucoes_log + complete/fail_crawler_job
# com raia + RPCs de leitura dos gráficos) num Postgres local efêmero, ANTES de pedir aplicação
# manual no SQL Editor de produção.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for200_validate_local.sh
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

# Schema mínimo: estado PÓS-FOR-198 (erro_categoria já existe nas 2 tabelas) — prova que o
# DROP+CREATE desta sessão funciona de cima do estado real atual de produção, não de um schema
# pré-histórico.
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
                    'captcha','timeout','rate_limit','site_indisponivel',
                    'bloqueio_suspeito','cnj_nao_encontrado','outro'
                  )),
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE FUNCTION complete_crawler_job(p_id UUID)
RETURNS VOID LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE crawler_queue SET status='ok', updated_at=NOW() WHERE id = p_id;
$$;
GRANT EXECUTE ON FUNCTION complete_crawler_job(UUID) TO service_role;

CREATE FUNCTION fail_crawler_job(p_id UUID, p_erro TEXT, p_categoria TEXT DEFAULT NULL)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE crawler_queue
     SET tentativas     = tentativas + 1,
         erro           = p_erro,
         erro_categoria = p_categoria,
         updated_at     = NOW(),
         status         = CASE WHEN tentativas + 1 >= 3 THEN 'erro' ELSE 'pendente' END,
         scheduled_at   = CASE WHEN tentativas + 1 >= 3 THEN scheduled_at
                               ELSE NOW() + (ARRAY['15 minutes','1 hour'])[tentativas + 1]::interval END
   WHERE id = p_id;
END; $$;
GRANT EXECUTE ON FUNCTION fail_crawler_job(UUID, TEXT, TEXT) TO authenticated, service_role;

CREATE FUNCTION requeue_failed(p_origem TEXT DEFAULT NULL)
RETURNS INT LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE n INT;
BEGIN
  UPDATE crawler_queue cq
     SET status='pendente', scheduled_at=NOW(), erro=NULL, erro_categoria=NULL, tentativas=0, updated_at=NOW()
   WHERE cq.status='erro'
     AND (p_origem IS NULL OR cq.origem = p_origem)
     AND NOT EXISTS (
       SELECT 1 FROM crawler_queue o
        WHERE o.processo_codigo = cq.processo_codigo AND o.status IN ('pendente','processando')
     );
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END; $$;
GRANT EXECUTE ON FUNCTION requeue_failed(TEXT) TO service_role, authenticated;

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
  erro_categoria       text CHECK (erro_categoria IN (
                         'captcha','timeout','rate_limit','site_indisponivel',
                         'bloqueio_suspeito','cnj_nao_encontrado','outro'
                       )),
  criado_em            timestamptz NOT NULL DEFAULT now()
);
EOF
ok "schema PÓS-FOR-198 criado (crawler_queue/pagamentos_consultas_log com erro_categoria)"

psql_ -d sandbox -f "$ROOT/sql/2026-10-04_for200_1_tabela_crawler_execucoes_log.sql" >/dev/null
ok "migration 1/3 (tabela crawler_execucoes_log) aplicada"
psql_ -d sandbox -f "$ROOT/sql/2026-10-04_for200_2_completa_falha_job_com_raia.sql" >/dev/null
ok "migration 2/3 (complete/fail_crawler_job com raia) aplicada"
psql_ -d sandbox -f "$ROOT/sql/2026-10-04_for200_3_rpcs_leitura_graficos.sql" >/dev/null
ok "migration 3/3 (RPCs de leitura) aplicada"

# ---- complete_crawler_job --------------------------------------------------------------
psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('11111111-1111-1111-1111-111111111111', '0014507-06.2020.8.26.0053')" >/dev/null
psql_ -d sandbox -c "select complete_crawler_job('11111111-1111-1111-1111-111111111111'::uuid)" >/dev/null
eq "$(val "select status from crawler_queue where id='11111111-1111-1111-1111-111111111111'")" "ok" "complete_crawler_job sem p_raia continua marcando status=ok (compat)"
eq "$(val "select count(*) from crawler_execucoes_log")" "0" "complete_crawler_job sem p_raia NÃO loga (p_raia NULL → pula INSERT)"

psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('22222222-2222-2222-2222-222222222222', '0150268-84.2024.8.26.0500')" >/dev/null
psql_ -d sandbox -c "select complete_crawler_job('22222222-2222-2222-2222-222222222222'::uuid, 3)" >/dev/null
eq "$(val "select resultado from crawler_execucoes_log where job_id='22222222-2222-2222-2222-222222222222'")" "ok" "complete_crawler_job COM p_raia loga resultado=ok"
eq "$(val "select raia from crawler_execucoes_log where job_id='22222222-2222-2222-2222-222222222222'")" "3" "raia persistida corretamente"
eq "$(val "select terminal from crawler_execucoes_log where job_id='22222222-2222-2222-2222-222222222222'")" "t" "ok sempre é terminal=true"
eq "$(val "select processo_codigo from crawler_execucoes_log where job_id='22222222-2222-2222-2222-222222222222'")" "0150268-84.2024.8.26.0500" "processo_codigo denormalizado corretamente"

# ---- fail_crawler_job: retentativa (não-terminal) vs final (terminal) -------------------
psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('33333333-3333-3333-3333-333333333333', '1040838-47.2016.8.26.0053')" >/dev/null
psql_ -d sandbox -c "select fail_crawler_job('33333333-3333-3333-3333-333333333333'::uuid, 'HTTP 429', 'rate_limit', 2)" >/dev/null
eq "$(val "select status from crawler_queue where id='33333333-3333-3333-3333-333333333333'")" "pendente" "fail_crawler_job (1ª tentativa) volta pra pendente (comportamento antigo intocado)"
eq "$(val "select terminal from crawler_execucoes_log where job_id='33333333-3333-3333-3333-333333333333'")" "f" "1ª falha (tentativas=1 < 3) → terminal=false"
eq "$(val "select raia from crawler_execucoes_log where job_id='33333333-3333-3333-3333-333333333333'")" "2" "raia da falha persistida"

psql_ -d sandbox -c "select fail_crawler_job('33333333-3333-3333-3333-333333333333'::uuid, 'HTTP 429', 'rate_limit', 2)" >/dev/null
psql_ -d sandbox -c "select fail_crawler_job('33333333-3333-3333-3333-333333333333'::uuid, 'HTTP 429', 'rate_limit', 2)" >/dev/null
eq "$(val "select status from crawler_queue where id='33333333-3333-3333-3333-333333333333'")" "erro" "3ª falha → status final 'erro' (comportamento antigo intocado)"
eq "$(val "select count(*) from crawler_execucoes_log where job_id='33333333-3333-3333-3333-333333333333'")" "3" "3 linhas de log (1 por tentativa), nenhuma sobrescrita"
eq "$(val "select terminal from crawler_execucoes_log where job_id='33333333-3333-3333-3333-333333333333' order by criado_em desc limit 1")" "t" "3ª falha (tentativas=3) → terminal=true"

# chamada SEM p_raia (compat — worker antigo continuaria funcionando sem logar)
psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('44444444-4444-4444-4444-444444444444', '0034784-92.2010.8.26.0053')" >/dev/null
psql_ -d sandbox -c "select fail_crawler_job('44444444-4444-4444-4444-444444444444'::uuid, 'algum erro')" >/dev/null
eq "$(val "select count(*) from crawler_execucoes_log where job_id='44444444-4444-4444-4444-444444444444'")" "0" "fail_crawler_job sem p_raia NÃO loga (compat)"

# CHECK rejeita categoria/resultado fora da lista
if psql_ -d sandbox -c "select fail_crawler_job('44444444-4444-4444-4444-444444444444'::uuid, 'x', 'categoria_invalida', 1)" >/dev/null 2>&1; then
  falha "CHECK deveria ter rejeitado erro_categoria fora da lista em crawler_execucoes_log"
fi
ok "CHECK rejeita erro_categoria fora das 7 categorias em crawler_execucoes_log"

# ---- GRANTs -------------------------------------------------------------------------------
eq "$(val "select has_function_privilege('service_role', 'complete_crawler_job(uuid,integer)', 'execute')")" "t" "service_role tem EXECUTE em complete_crawler_job"
eq "$(val "select has_function_privilege('authenticated', 'complete_crawler_job(uuid,integer)', 'execute')")" "t" "authenticated GANHA EXECUTE explícito em complete_crawler_job (endurece o achado do FOR-198 — a assinatura original nunca teve REVOKE FROM PUBLIC)"
eq "$(val "select has_function_privilege('anon', 'complete_crawler_job(uuid,integer)', 'execute')")" "f" "anon fica SEM EXECUTE em complete_crawler_job (endurecimento deliberado)"
eq "$(val "select has_function_privilege('authenticated', 'fail_crawler_job(uuid,text,text,integer)', 'execute')")" "t" "authenticated tem EXECUTE na nova assinatura de fail_crawler_job"
eq "$(val "select has_function_privilege('anon', 'fail_crawler_job(uuid,text,text,integer)', 'execute')")" "f" "anon fica SEM EXECUTE em fail_crawler_job"
eq "$(val "select has_function_privilege('anon', 'crawler_execucoes_recentes(boolean,integer)', 'execute')")" "t" "anon TEM EXECUTE nas RPCs de leitura (admin roda anônimo)"
eq "$(val "select has_function_privilege('authenticated', 'requeue_failed(text)', 'execute')")" "t" "requeue_failed preserva GRANT (assinatura intocada por esta sessão)"

# ---- RPCs de leitura ------------------------------------------------------------------------
eq "$(val "select count(*) from crawler_execucoes_recentes(false, 10)")" "3" "crawler_execucoes_recentes(false) retorna só não-DEPRE (seeds 1,3,4 — não-terminal + terminal)"
eq "$(val "select count(*) from crawler_execucoes_recentes(true, 10)")" "1" "crawler_execucoes_recentes(true) retorna só .0500 (seed 2)"
eq "$(val "select processo_codigo from crawler_execucoes_recentes(true, 10) limit 1")" "0150268-84.2024.8.26.0500" "crawler_execucoes_recentes(true) devolve o processo certo"

psql_ -d sandbox -c "INSERT INTO pagamentos_consultas_log (processo_depre, iniciada_em, finalizada_em, origem, resultado, erro_categoria) VALUES ('0073316-98.2023.8.26.0500', now(), now(), 'crawler', 'falha', 'captcha')" >/dev/null
psql_ -d sandbox -c "INSERT INTO pagamentos_consultas_log (processo_depre, iniciada_em, finalizada_em, origem, resultado) VALUES ('0073316-98.2023.8.26.0500', now(), now(), 'crawler', 'encontrado')" >/dev/null
eq "$(val "select count(*) from pagamentos_consultas_recentes(10)")" "2" "pagamentos_consultas_recentes retorna as 2 linhas inseridas"

eq "$(val "select n_ok from crawler_execucoes_por_hora()")" "2" "crawler_execucoes_por_hora: 2 jobs status=ok na última hora (seeds 1 e 2)"
eq "$(val "select n_erro from crawler_execucoes_por_hora()")" "1" "crawler_execucoes_por_hora: 1 job status=erro na última hora (seed 3, 3ª falha)"

PENDENTES_AGORA="$(val "select pendentes from crawler_fila_pendente_tendencia() order by hora desc limit 1")"
eq "$PENDENTES_AGORA" "1" "crawler_fila_pendente_tendencia (agora): 1 pendente real (seed 4, nunca resolvido)"

eq "$(val "select n from erros_por_categoria_24h() where categoria='rate_limit'")" "1" "erros_por_categoria_24h conta o erro terminal de crawler_queue (seed 3)"
eq "$(val "select n from erros_por_categoria_24h() where categoria='captcha'")" "1" "erros_por_categoria_24h conta a falha de pagamentos_consultas_log"

# ---- retenção por tempo (3 dias) -------------------------------------------------------
psql_ -d sandbox -c "update crawler_execucoes_log set criado_em = now() - interval '10 days' where job_id='22222222-2222-2222-2222-222222222222'" >/dev/null
psql_ -d sandbox -c "INSERT INTO crawler_queue (id, processo_codigo) VALUES ('55555555-5555-5555-5555-555555555555', '1003056-11.2013.8.26.0053')" >/dev/null
psql_ -d sandbox -c "select complete_crawler_job('55555555-5555-5555-5555-555555555555'::uuid, 1)" >/dev/null
eq "$(val "select count(*) from crawler_execucoes_log where job_id='22222222-2222-2222-2222-222222222222'")" "0" "retenção: linha com 10 dias é apagada no próximo INSERT (DELETE WHERE criado_em < now()-3d)"

echo
echo "FOR-200 sandbox: TODOS OS CENÁRIOS OK"
