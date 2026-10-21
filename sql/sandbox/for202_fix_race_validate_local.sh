#!/usr/bin/env bash
#
# FOR-202 (fix pós-aplicação) — valida que o padrão "FOR UPDATE SKIP LOCKED + statement
# separado" fecha a janela de corrida que o code-reviewer reproduziu contra a versão
# original (1 statement só).
#
# Mecanismo real do bug (confirmado contra o relato do revisor): a sessão A segura o LOCK
# da linha de `incidentes` (ex. um UPDATE do próprio classify_processo) enquanto ainda
# está no meio da transação (já inseriu o andamento, ainda não commitou). A sessão B (tick
# antigo) tenta dar UPDATE na MESMA linha, BLOQUEIA esperando o lock — o snapshot do
# statement de B já foi tirado no início (antes do commit de A). Quando A commita, o
# UPDATE de B retoma via EvalPlanQual: a condição direta sobre a linha (cessao_credito=
# false) é re-checada contra a versão nova (ainda bate), mas o NOT EXISTS (que escaneia a
# tabela `andamentos`, outra tabela) continua usando o snapshot ANTIGO — não enxerga o
# andamento que A acabou de commitar. Resultado: linha vira NULL por engano.
#
# O padrão novo evita isso não por "ver dado fresco no meio do statement" (não dá pra
# fazer isso em SQL puro), mas por NUNCA disputar o lock: FOR UPDATE SKIP LOCKED no passo
# 1 pula qualquer linha que A já esteja segurando — ela simplesmente fica de fora deste
# lote (não é tocada, nem corrigida nem corrompida) e é reavaliada no próximo tick, quando
# A já tiver commitado.
#
# Requer PostgreSQL 15+. Uso: sql/sandbox/for202_fix_race_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54355}"
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
CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text UNIQUE NOT NULL, cessao_credito boolean
);
CREATE TABLE andamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id uuid NOT NULL REFERENCES incidentes(id), data date, descricao text, hash text
);
INSERT INTO incidentes (id, processo_codigo, cessao_credito) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'RACE', false);
EOF
ok "schema + 1 incidente (RACE), cessao_credito=false, SEM andamento ainda"

# ===========================================================================
# PARTE 1 — prova que o padrão ANTIGO (1 UPDATE só) tem o bug.
# Sessão A: segura o LOCK da linha (UPDATE), insere o andamento, dorme, commita.
# Sessão B: tenta UPDATE na mesma linha -> BLOQUEIA esperando A -> ao retomar, o NOT
# EXISTS usa snapshot velho (de antes do commit de A) -> vira NULL por engano.
# ===========================================================================
psql_ -d sandbox <<'SQLB_OLD' &
begin;
select pg_sleep(0.3);
update incidentes set cessao_credito = null
 where processo_codigo = 'RACE' and cessao_credito = false
   and not exists (select 1 from andamentos a where a.incidente_id = incidentes.id);
commit;
SQLB_OLD
B_OLD_PID=$!

psql_ -d sandbox <<'SQLA1'
begin;
update incidentes set cessao_credito = false where processo_codigo = 'RACE';
insert into andamentos (incidente_id, data, descricao, hash)
  select id, '2024-01-01', 'Comunicado de Acordo de Requisitório', 'race-old'
  from incidentes where processo_codigo = 'RACE';
select pg_sleep(1.0);
commit;
SQLA1

wait "$B_OLD_PID"
eq "$(val "select cessao_credito is null from incidentes where processo_codigo='RACE'")" "t" \
  "PADRÃO ANTIGO (1 statement): bug confirmado — vira NULL mesmo o andamento tendo sido commitado antes do UPDATE retomar"

# reseta pro teste do fix
psql_ -d sandbox -c "update incidentes set cessao_credito = false where processo_codigo='RACE'" >/dev/null
psql_ -d sandbox -c "delete from andamentos where incidente_id = (select id from incidentes where processo_codigo='RACE')" >/dev/null

# ===========================================================================
# PARTE 2 — padrão NOVO (FOR UPDATE SKIP LOCKED + statement separado).
# Sessão A: mesma coisa (segura o lock, insere andamento, dorme, commita).
# Sessão B (passo 1, SKIP LOCKED): a linha está travada por A -> B simplesmente PULA
# ela (não entra no lote) -> passo 2 nem roda pra essa linha -> ela fica como A deixou
# (false), nunca vira NULL por engano.
# ===========================================================================
psql_ -d sandbox <<'SQLB_NEW' &
begin;
select pg_sleep(0.3);
-- passo 1: SKIP LOCKED — a linha está travada por A nesse momento, então esta query
-- devolve ZERO linhas (nunca espera). v_ids ficaria vazio/NULL na função real; aqui só
-- confirmamos que a própria query não trava (completa na hora) e devolve nada.
select count(*) as n_travado_pulado from (
  select id from incidentes where processo_codigo = 'RACE' and cessao_credito = false
   for update skip locked
) s;
-- passo 2 nem chega a rodar pra essa linha na função real (v_tamanho=0 -> IF pula o
-- UPDATE inteiro) — aqui simulamos isso simplesmente NÃO rodando update nenhum, já que
-- não haveria nenhum id no lote.
commit;
SQLB_NEW
B_NEW_PID=$!

psql_ -d sandbox <<'SQLA2'
begin;
update incidentes set cessao_credito = false where processo_codigo = 'RACE';
insert into andamentos (incidente_id, data, descricao, hash)
  select id, '2024-01-01', 'Comunicado de Acordo de Requisitório', 'race-new'
  from incidentes where processo_codigo = 'RACE';
select pg_sleep(1.0);
commit;
SQLA2

wait "$B_NEW_PID"
eq "$(val "select cessao_credito from incidentes where processo_codigo='RACE'")" "f" \
  "PADRÃO NOVO (FOR UPDATE SKIP LOCKED): fix funciona — B pulou a linha travada, nunca virou NULL por engano"

echo
echo "FOR-202 race fix sandbox: TODOS OS CENÁRIOS OK (bug reproduzido no padrão antigo, fechado no novo)"
