#!/usr/bin/env bash
#
# FOR-202 — valida a função tick do backfill (for202_backfill_cessao_credito_tick) num
# Postgres local efêmero: correção seletiva, cursor avançando, autodesligamento quando
# o lote vem menor que o tamanho pedido, pausa/retomada manual, e que nunca toca em
# linhas já true/NULL.
#
# Não testa `cron.schedule` em si (exigiria a extensão pg_cron, fora de escopo deste
# sandbox) — só a função que o cron chama, que é a parte com lógica de negócio.
#
# Requer PostgreSQL 15+. Uso: sql/sandbox/for202_backfill_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54353}"
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

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text UNIQUE NOT NULL, andamentos jsonb,
  last_crawled_at timestamptz, next_crawl_at timestamptz, updated_at timestamptz DEFAULT now()
);
CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id), processo_codigo text UNIQUE NOT NULL, andamentos jsonb
);
CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id), cumprimento_id uuid REFERENCES cumprimentos(id),
  processo_codigo text UNIQUE NOT NULL, numero_depre text,
  cessao_credito boolean, updated_at timestamptz DEFAULT now()
);
CREATE TABLE andamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id uuid NOT NULL REFERENCES incidentes(id),
  data date, descricao text, arquivo_url text, hash text
);
CREATE TABLE coleta_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(), rotina text NOT NULL, status text NOT NULL,
  started_at timestamptz NOT NULL DEFAULT now(), finished_at timestamptz,
  itens_ok int, itens_erro int, detalhe jsonb
);

-- Shim de pg_cron (não dá pra instalar a extensão real num cluster efêmero sem
-- reconfigurar shared_preload_libraries antes do start) — só pra deixar o arquivo real
-- aplicar SEM edição nenhuma, em vez de testar uma cópia mutilada por sed.
CREATE SCHEMA cron;
CREATE FUNCTION cron.schedule(text, text, text) RETURNS bigint
  LANGUAGE sql AS $$ SELECT 1::bigint $$;
EOF
ok "schema mínimo criado (incidentes.cessao_credito já nullable — pressupõe Fase 1 aplicada) + shim de pg_cron"

# Aplica o arquivo REAL, sem edição — prova que ele é sintaticamente válido de ponta a
# ponta, inclusive a chamada cron.schedule (contra o shim acima).
psql_ -d sandbox -f "$ROOT/sql/2026-10-21_for202_backfill_cessao_credito.sql" >/dev/null
ok "arquivo real aplicado sem edição (tabela de estado + função tick + cron.schedule contra o shim)"

# ---- Fixture: 5 incidentes, cessao_credito=false em todos -----------------------------
# IA: sem andamento em lugar nenhum -> DEVE virar NULL.
# IB: tem andamento próprio -> NÃO deve mudar (continua false).
# IC: sem andamento -> DEVE virar NULL.
# ID: já é TRUE (não false) -> nunca deve ser tocado pelo backfill.
# IE: já é NULL (um classify_processo concorrente já rodou) -> nunca deve ser "re-tocado".
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo) VALUES
  ('00000000-0000-0000-0000-000000000001', 'P1');
INSERT INTO cumprimentos (id, processo_id, processo_codigo) VALUES
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-000000000001', 'C1');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, cessao_credito) VALUES
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'IA', false),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'IB', false),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'IC', false),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'ID', true),
  ('00000000-0000-0000-0000-00000000a005', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'IE', NULL);
INSERT INTO andamentos (incidente_id, data, descricao, hash) VALUES
  ('00000000-0000-0000-0000-00000000a002', '2024-01-01', 'Qualquer andamento', 'h1');
EOF
ok "fixture: IA/IC sem andamento, IB com andamento, ID já true, IE já null"

psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
ok "1º tick rodou sem erro"

eq "$(val "select cessao_credito is null from incidentes where processo_codigo='IA'")" "t" "IA vira NULL"
eq "$(val "select cessao_credito is null from incidentes where processo_codigo='IC'")" "t" "IC vira NULL"
eq "$(val "select cessao_credito from incidentes where processo_codigo='IB'")" "f" "IB continua false (tem andamento, não é tocado)"
eq "$(val "select cessao_credito from incidentes where processo_codigo='ID'")" "t" "ID continua true (guard cessao_credito=false não bate nele)"
eq "$(val "select cessao_credito is null from incidentes where processo_codigo='IE'")" "t" "IE continua null (já estava, guard não bate)"

eq "$(val "select total_corrigidos from for202_backfill_cessao_credito_estado")" "2" \
  "estado: 2 corrigidos (IA + IC)"
eq "$(val "select ativo from for202_backfill_cessao_credito_estado")" "f" \
  "autodesligou sozinho — lote (5) veio menor que o limite (3000), sinal de que acabou"

# ---- Tick de novo com ativo=false -> no-op ---------------------------------------------
psql_ -d sandbox -c "update for202_backfill_cessao_credito_estado set total_lotes = 999" >/dev/null
psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select total_lotes from for202_backfill_cessao_credito_estado")" "999" \
  "tick com ativo=false é no-op (não mexeu em total_lotes)"

# ---- Retomada manual ---------------------------------------------------------------
psql_ -d sandbox -c "update for202_backfill_cessao_credito_estado set ativo = true, cursor_atual = null" >/dev/null
psql_ -d sandbox -c "update incidentes set cessao_credito = false where processo_codigo in ('IA','IC')" >/dev/null
psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select cessao_credito is null from incidentes where processo_codigo='IA'")" "t" \
  "retomada manual (ativo=true de novo): IA volta a virar NULL"

# ---- Gap: guard contra jsonb de cumprimento (fonte 2) e jsonb de processo raiz (fonte 3)
# nunca tinha sido exercitado — só IB (andamento na tabela `andamentos`, fonte 1) testava
# a função tick NÃO corrigir uma linha com andamento. Processo/cumprimento NOVOS e
# isolados de P1/C1 pra não contaminar os guards já testados acima (C1 é compartilhado
# por IA/IB/IC/IE; mexer nele retestaria tudo de novo com outro resultado).
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, andamentos) VALUES
  ('00000000-0000-0000-0000-000000000002', 'P2',
   '[{"data":"2024-01-01","descricao":"Audiência de conciliação designada","arquivo_url":null}]'::jsonb);
INSERT INTO cumprimentos (id, processo_id, processo_codigo, andamentos) VALUES
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-000000000002', 'C2',
   '[{"data":"2024-02-01","descricao":"Conclusos para despacho","arquivo_url":null}]'::jsonb),
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-000000000002', 'C3', NULL);
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, cessao_credito) VALUES
  ('00000000-0000-0000-0000-00000000a006', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c002', 'IF', false),
  ('00000000-0000-0000-0000-00000000a007', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c003', 'IG', false);
EOF
ok "fixture adicional: IF (cumprimento C2 com jsonb não-vazio) / IG (cumprimento C3 sem jsonb, mas PROCESSO P2 com jsonb não-vazio)"

psql_ -d sandbox -c "update for202_backfill_cessao_credito_estado set ativo = true, cursor_atual = null" >/dev/null
psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null

eq "$(val "select cessao_credito from incidentes where processo_codigo='IF'")" "f" \
  "IF: cumprimento tem jsonb de andamentos não-vazio (fonte 2) -> guard bloqueia, NÃO vira NULL (continua false)"
eq "$(val "select cessao_credito from incidentes where processo_codigo='IG'")" "f" \
  "IG: cumprimento próprio sem jsonb, mas o PROCESSO raiz (P2) tem jsonb não-vazio (fonte 3) -> guard também bloqueia, NÃO vira NULL"

# ---- Gap: paginação multi-tick de verdade (lote CHEIO de 3000 -> cursor avança -> tick
# seguinte retoma e completa). Até aqui todo teste usava <5 linhas, então o lote nunca
# vinha "cheio" (sempre autodesligava no 1º tick) — o código do cursor/LIMIT 3000 nunca
# tinha sido exercitado de fato. Estado limpo (TRUNCATE) pra isolar de UUIDs já
# "ultrapassados" pelo cursor nos cenários acima (ids anteriores são aleatórios — se não
# isolar, a contagem de corrigidos por tick fica não-determinística).
psql_ -d sandbox <<'EOF'
TRUNCATE incidentes, andamentos, cumprimentos, processos CASCADE;
DELETE FROM for202_backfill_cessao_credito_estado;
INSERT INTO for202_backfill_cessao_credito_estado (id) VALUES (true);

INSERT INTO incidentes (processo_codigo, cessao_credito)
SELECT 'BULK-' || gs, false FROM generate_series(1, 3005) gs;
EOF
ok "fixture de paginação: 3005 incidentes elegíveis (sem processo/cumprimento/andamento), estado resetado"

psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select total_corrigidos from for202_backfill_cessao_credito_estado")" "3000" \
  "1º tick da paginação: lote CHEIO (3000), todos corrigidos (nenhum tinha andamento)"
eq "$(val "select ativo from for202_backfill_cessao_credito_estado")" "t" \
  "1º tick: lote veio exatamente 3000 (cheio) -> ativo continua true, ainda tem mais pra processar"
eq "$(val "select cursor_atual is not null from for202_backfill_cessao_credito_estado")" "t" \
  "1º tick: cursor avançou (não é mais NULL)"

psql_ -d sandbox -c "select for202_backfill_cessao_credito_tick()" >/dev/null
eq "$(val "select total_corrigidos from for202_backfill_cessao_credito_estado")" "3005" \
  "2º tick: completa os 5 restantes (3000+5=3005, nenhum ficou de fora pela paginação)"
eq "$(val "select ativo from for202_backfill_cessao_credito_estado")" "f" \
  "2º tick: lote veio incompleto (5 < 3000) -> autodesligou, confirma fim do backfill"
eq "$(val "select count(*) from incidentes where cessao_credito = false")" "0" \
  "paginação completa: nenhum incidente elegível ficou pra trás entre os dois ticks"

echo
echo "FOR-202 backfill sandbox: TODOS OS CENÁRIOS OK"
