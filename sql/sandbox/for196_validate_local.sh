#!/usr/bin/env bash
#
# FOR-196 — valida o backfill (sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql)
# num Postgres LOCAL descartável (nunca toca produção).
#
# Por quê: a migration é um UPDATE simples, mas o risco é duplo — (a) não cobrir TODOS os
# cumprimentos sintéticos (cnj is null) e (b) não ser idempotente (rodar 2x não pode alterar
# nada na 2ª rodada, nem sobrescrever um cnj que já estava preenchido corretamente). Este
# script cria uma réplica mínima de processos/cumprimentos/incidentes (só as colunas usadas
# pelo UPDATE), semeia 3 cenários (cumprimento sintético cnj=null, cumprimento "de verdade" já
# com cnj preenchido, cumprimento sintético com 2 incidentes apontando pro mesmo processo) e
# roda o UPDATE duas vezes, provando o resultado em cada rodada.
#
# Requer o PostgreSQL 15+ instalado (Homebrew: `brew install postgresql@15`). Uso:
#   sql/sandbox/for196_validate_local.sh
#   PGBIN=/caminho/para/bin PORT_SANDBOX=54331 sql/sandbox/for196_validate_local.sh
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
# sem socket unix (caminho longo estoura o limite); só TCP em 127.0.0.1
"$PGBIN/pg_ctl" -D "$TMP/data" -o "-p $PORT -c listen_addresses=127.0.0.1 -c unix_socket_directories=''" -l "$TMP/pg.log" -w start >/dev/null
psql_ -c "CREATE DATABASE sandbox" postgres

# --- schema sintético: só as colunas tocadas pelo UPDATE (réplica do shape real de
# supabase/migrations/20260627192837_for69_schema_base_propria.sql).
psql_ -d sandbox -c "
  create extension if not exists pgcrypto;
  create table processos (id uuid primary key default gen_random_uuid(), cnj text);
  create table cumprimentos (id uuid primary key default gen_random_uuid(), processo_id uuid not null references processos(id), cnj text);
  create table incidentes (id uuid primary key default gen_random_uuid(), cumprimento_id uuid references cumprimentos(id), processo_id uuid not null references processos(id), cnj text);
"
ok "schema sintético criado (processos/cumprimentos/incidentes)"

# --- cenário 1: processo A, cumprimento sintético (cnj null), 2 incidentes pendurados nele
#     (reproduz o caso de 'incidentes pendurados direto na raiz' do crawl.ts).
# --- cenário 2: processo B, cumprimento "de verdade" já com cnj preenchido (não pode mudar).
# --- cenário 3: processo C, cumprimento sintético cnj=null SEM nenhum incidente associado
#     (não deve quebrar nem ser alterado — não há join possível, fica null mesmo).
psql_ -d sandbox -c "
  insert into processos (id, cnj) values
    ('00000000-0000-0000-0000-00000000000a', '0000001-11.2020.8.26.0100'),
    ('00000000-0000-0000-0000-00000000000b', '0000002-22.2020.8.26.0100'),
    ('00000000-0000-0000-0000-00000000000c', '0000003-33.2020.8.26.0100');
  insert into cumprimentos (id, processo_id, cnj) values
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', null),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', '0009999-99.2019.8.26.0100'),
    ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000c', null);
  insert into incidentes (id, cumprimento_id, processo_id, cnj) values
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '0000500-01.2021.8.26.0500'),
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '0000500-02.2021.8.26.0500'),
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', '0000500-03.2021.8.26.0500');
"
ok "3 cenários semeados (sintético c/ 2 incidentes, de-verdade já preenchido, sintético sem incidente)"

# --- rodada 1
psql_ -d sandbox -f "$ROOT/sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql"

r1_a="$(psql_ -d sandbox -Atc "select cnj from cumprimentos where id = '10000000-0000-0000-0000-000000000001'")"
r1_b="$(psql_ -d sandbox -Atc "select cnj from cumprimentos where id = '10000000-0000-0000-0000-000000000002'")"
r1_c="$(psql_ -d sandbox -Atc "select cnj from cumprimentos where id = '10000000-0000-0000-0000-000000000003'")"

[[ "$r1_a" == "0000001-11.2020.8.26.0100" ]] || falha "rodada 1: cumprimento sintético (A) deveria herdar o cnj da raiz, veio '$r1_a'"
ok "rodada 1: cumprimento sintético com incidentes (A) preenchido = cnj da raiz ($r1_a)"

[[ "$r1_b" == "0009999-99.2019.8.26.0100" ]] || falha "rodada 1: cumprimento 'de verdade' (B) foi alterado indevidamente, veio '$r1_b'"
ok "rodada 1: cumprimento 'de verdade' (B) preservado, não foi sobrescrito ($r1_b)"

[[ -z "$r1_c" ]] || falha "rodada 1: cumprimento sintético sem incidente (C) deveria continuar null (sem join possível), veio '$r1_c'"
ok "rodada 1: cumprimento sintético sem incidente associado (C) continua null (nada pra casar)"

# --- rodada 2 (idempotência: nada pode mudar)
psql_ -d sandbox -f "$ROOT/sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql"

r2_a="$(psql_ -d sandbox -Atc "select cnj from cumprimentos where id = '10000000-0000-0000-0000-000000000001'")"
r2_b="$(psql_ -d sandbox -Atc "select cnj from cumprimentos where id = '10000000-0000-0000-0000-000000000002'")"
r2_c="$(psql_ -d sandbox -Atc "select cnj from cumprimentos where id = '10000000-0000-0000-0000-000000000003'")"
total="$(psql_ -d sandbox -Atc "select count(*) from cumprimentos")"

[[ "$r2_a" == "$r1_a" && "$r2_b" == "$r1_b" && -z "$r2_c" ]] || falha "rodada 2: idempotência quebrada (A='$r2_a' B='$r2_b' C='$r2_c')"
[[ "$total" == "3" ]] || falha "rodada 2: contagem de linhas mudou (esperava 3, veio $total) — UPDATE não deveria duplicar nada"
ok "rodada 2 (idempotente): A/B/C inalterados em relação à rodada 1, 3 linhas em cumprimentos (sem duplicar)"

echo "RESUMO: backfill FOR-196 validado — preenche só cnj=null via incidentes->processos, preserva cnj já existente, idempotente em 2 rodadas."
