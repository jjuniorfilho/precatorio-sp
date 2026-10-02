#!/usr/bin/env bash
#
# FOR-196 — valida o backfill (sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql)
# num Postgres LOCAL descartável (nunca toca produção).
#
# Por quê: a migration restringe por `processo_codigo like '%#cumprimento'` (achado do code
# review: nem todo `cnj is null` é um cumprimento sintético — um cumprimento "de verdade" sem
# CNJ reconhecido no texto do link também tem `cnj is null`, e herdar o CNJ da raiz nesse caso
# estaria errado). Este script cria uma réplica mínima de processos/cumprimentos/incidentes (só
# as colunas usadas pelo UPDATE) e semeia 4 cenários:
# A) cumprimento sintético (sufixo #cumprimento) cnj=null, com 2 incidentes no mesmo processo
#    -> deve ser preenchido com o cnj/cnj_normalizado da raiz.
# B) cumprimento "de verdade" já com cnj preenchido -> não pode ser alterado.
# C) cumprimento sintético cnj=null SEM nenhum incidente associado -> preenchido mesmo assim
#    (o UPDATE usa processo_id, não depende de incidentes).
# D) cumprimento "de verdade" (SEM o sufixo #cumprimento) com cnj=null -> deve CONTINUAR null
#    (extractCnj não achou o número no texto do link; não é o bug desta issue, herdar o cnj
#    da raiz aqui estaria errado).
# Roda o UPDATE duas vezes (idempotência: nada muda na 2ª rodada, sem duplicar linha).
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
  create table processos (id uuid primary key default gen_random_uuid(), cnj text, cnj_normalizado text);
  create table cumprimentos (id uuid primary key default gen_random_uuid(), processo_id uuid not null references processos(id), processo_codigo text not null, cnj text, cnj_normalizado text);
  create table incidentes (id uuid primary key default gen_random_uuid(), cumprimento_id uuid references cumprimentos(id), processo_id uuid not null references processos(id), cnj text);
"
ok "schema sintético criado (processos/cumprimentos/incidentes)"

psql_ -d sandbox -c "
  insert into processos (id, cnj, cnj_normalizado) values
    ('00000000-0000-0000-0000-00000000000a', '0000001-11.2020.8.26.0100', '00000001120208260100'),
    ('00000000-0000-0000-0000-00000000000b', '0000002-22.2020.8.26.0100', '00000002220208260100'),
    ('00000000-0000-0000-0000-00000000000c', '0000003-33.2020.8.26.0100', '00000003320208260100'),
    ('00000000-0000-0000-0000-00000000000d', '0000004-44.2020.8.26.0100', '00000004420208260100');
  insert into cumprimentos (id, processo_id, processo_codigo, cnj, cnj_normalizado) values
    ('10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '1H0000A#cumprimento', null, null),
    ('10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', '1H0000B', '0009999-99.2019.8.26.0100', '00099999920198260100'),
    ('10000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000000c', '1H0000C#cumprimento', null, null),
    ('10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000d', '1H0000D', null, null);
  insert into incidentes (id, cumprimento_id, processo_id, cnj) values
    ('20000000-0000-0000-0000-000000000001', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '0000500-01.2021.8.26.0500'),
    ('20000000-0000-0000-0000-000000000002', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000000a', '0000500-02.2021.8.26.0500'),
    ('20000000-0000-0000-0000-000000000003', '10000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000000b', '0000500-03.2021.8.26.0500'),
    ('20000000-0000-0000-0000-000000000004', '10000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-00000000000d', '0000500-04.2021.8.26.0500');
"
ok "4 cenários semeados (A sintético c/2 incidentes, B de-verdade já preenchido, C sintético sem incidente, D de-verdade com cnj null)"

ler() { psql_ -d sandbox -Atc "select coalesce(cnj,'') || '|' || coalesce(cnj_normalizado,'') from cumprimentos where id = '$1'"; }

# --- rodada 1
psql_ -d sandbox -f "$ROOT/sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql"

r1_a="$(ler 10000000-0000-0000-0000-000000000001)"
r1_b="$(ler 10000000-0000-0000-0000-000000000002)"
r1_c="$(ler 10000000-0000-0000-0000-000000000003)"
r1_d="$(ler 10000000-0000-0000-0000-000000000004)"

[[ "$r1_a" == "0000001-11.2020.8.26.0100|00000001120208260100" ]] || falha "rodada 1: (A) sintético deveria herdar cnj+cnj_normalizado da raiz, veio '$r1_a'"
ok "rodada 1: (A) sintético com incidentes preenchido = cnj+cnj_normalizado da raiz"

[[ "$r1_b" == "0009999-99.2019.8.26.0100|00099999920198260100" ]] || falha "rodada 1: (B) 'de verdade' foi alterado indevidamente, veio '$r1_b'"
ok "rodada 1: (B) 'de verdade' já preenchido preservado"

[[ "$r1_c" == "0000003-33.2020.8.26.0100|00000003320208260100" ]] || falha "rodada 1: (C) sintético sem incidente deveria herdar cnj mesmo assim (usa processo_id, não incidentes), veio '$r1_c'"
ok "rodada 1: (C) sintético SEM incidente associado também preenchido (via processo_id)"

[[ "$r1_d" == "|" ]] || falha "rodada 1: (D) 'de verdade' sem sufixo #cumprimento deveria CONTINUAR null, veio '$r1_d'"
ok "rodada 1: (D) 'de verdade' sem sufixo #cumprimento continua null (não é o bug desta issue)"

# --- rodada 2 (idempotência: nada pode mudar)
psql_ -d sandbox -f "$ROOT/sql/2026-10-02_for196_backfill_cnj_cumprimento_sintetico.sql"

r2_a="$(ler 10000000-0000-0000-0000-000000000001)"
r2_b="$(ler 10000000-0000-0000-0000-000000000002)"
r2_c="$(ler 10000000-0000-0000-0000-000000000003)"
r2_d="$(ler 10000000-0000-0000-0000-000000000004)"
total="$(psql_ -d sandbox -Atc "select count(*) from cumprimentos")"

[[ "$r2_a" == "$r1_a" && "$r2_b" == "$r1_b" && "$r2_c" == "$r1_c" && "$r2_d" == "$r1_d" ]] \
  || falha "rodada 2: idempotência quebrada (A='$r2_a' B='$r2_b' C='$r2_c' D='$r2_d')"
[[ "$total" == "4" ]] || falha "rodada 2: contagem de linhas mudou (esperava 4, veio $total) — UPDATE não deveria duplicar nada"
ok "rodada 2 (idempotente): A/B/C/D inalterados em relação à rodada 1, 4 linhas em cumprimentos (sem duplicar)"

echo "RESUMO: backfill FOR-196 validado — preenche cnj+cnj_normalizado só nos sintéticos (sufixo #cumprimento) com cnj null via processo_id->processos, preserva cnj já existente E cumprimento 'de verdade' com cnj null, idempotente em 2 rodadas."
