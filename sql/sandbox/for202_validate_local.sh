#!/usr/bin/env bash
#
# FOR-202 — valida que cessao_credito nullable + o fix em classify_processo/
# classify_incidentes distinguem corretamente "nunca verificado" (NULL) de "verificado,
# sem cessão" (false), num Postgres local efêmero, ANTES de pedir aplicação manual em
# produção.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for202_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54352}"
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

# Schema mínimo — mesmas tabelas/colunas do FOR-201, já no estado PÓS-FOR-201 (colunas
# jsonb de andamentos já presentes), PRÉ-FOR-202 (cessao_credito ainda NOT NULL DEFAULT
# false — é o estado real de produção hoje).
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text UNIQUE NOT NULL,
  cnj text, cnj_normalizado text,
  andamentos jsonb,
  last_crawled_at timestamptz, next_crawl_at timestamptz,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id),
  processo_codigo text UNIQUE NOT NULL,
  cnj text, cnj_normalizado text,
  andamentos jsonb
);

CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id),
  cumprimento_id uuid REFERENCES cumprimentos(id),
  processo_codigo text UNIQUE NOT NULL,
  numero_depre text, cnj text, cnj_normalizado text,
  tipo_previsto text NOT NULL DEFAULT 'Indefinido',
  macrofase text, fase text, fase_desde date,
  calculo_homologado boolean, incidente_instaurado boolean, termo_declaracao boolean,
  oficio_deferido boolean, oficio_expedido boolean, ordem_cronologica boolean,
  possivelmente_pago boolean, elegivel boolean, ano_oc integer,
  cessao_credito boolean NOT NULL DEFAULT false,
  valor_acao bigint, data_base date, status text,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE andamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id uuid NOT NULL REFERENCES incidentes(id),
  data date, descricao text, arquivo_url text, hash text
);

CREATE TABLE classificacao_regras (
  flag text NOT NULL, padrao text NOT NULL, tipo text NOT NULL DEFAULT 'ilike',
  ativo boolean NOT NULL DEFAULT true,
  PRIMARY KEY (flag, padrao)
);

CREATE TABLE coleta_config (
  rotina text PRIMARY KEY, params jsonb NOT NULL DEFAULT '{}'::jsonb
);

INSERT INTO classificacao_regras (flag, padrao, tipo) VALUES
  ('calculo_homologado',   '%homologaç%cálculo%',                        'ilike'),
  ('incidente_instaurado', '%Incidente Processual Instaurado%',          'ilike'),
  ('termo_declaracao',     '%termo de declaraç%',                        'ilike'),
  ('oficio_deferido',      '%Expedição de Ofício Requisitório Deferido%','ilike'),
  ('oficio_expedido',      '%precatório expedido%',                     'ilike'),
  ('ordem_cronologica',    '%ordem cronológica%',                       'ilike'),
  ('possivelmente_pago',   '%arquivado definitivamente%',               'ilike'),
  ('cessao_credito', 'DEPRE - Informação de Cessão de Crédito%',  'ilike'),
  ('cessao_credito', 'Ofício Requisitório - Cessão de Crédito%',  'ilike'),
  ('cessao_credito', 'Decisão - Homologada a Cessão de Crédito%', 'ilike'),
  ('cessao_credito', '%+ Ofício Cessão de Crédito%',              'ilike');
EOF
ok "schema PÓS-FOR-201/PRÉ-FOR-202 criado (cessao_credito ainda NOT NULL DEFAULT false)"

psql_ -d sandbox -f "$ROOT/sql/2026-10-21_for202_cessao_credito_nullable.sql" >/dev/null
ok "migration FOR-202 aplicada (schema + classify_processo + classify_incidentes)"

eq "$(val "select is_nullable from information_schema.columns where table_name='incidentes' and column_name='cessao_credito'")" "YES" \
  "cessao_credito agora é nullable"
eq "$(val "select column_default from information_schema.columns where table_name='incidentes' and column_name='cessao_credito'")" "" \
  "sem DEFAULT"

# ---- Fixture ---------------------------------------------------------------------
# P1/C1/I1: NENHUM andamento em lugar nenhum -> espera NULL (nunca verificado).
# P1/C2/I2: cumprimento tem andamento batendo cessão -> espera true.
# P1/C3/I3: cumprimento tem andamento mas NENHUM bate nenhuma regra -> espera false
#   (já verificado, negativo real — não NULL).
# P2/C4/I4 (processo raiz com andamento, sem bater cessão, incidente sem numero_depre):
#   confirma que tem_andamento via processo-level também conta.
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, last_crawled_at) VALUES
  ('00000000-0000-0000-0000-000000000001', 'P1', now()),
  ('00000000-0000-0000-0000-000000000002', 'P2', now());

UPDATE processos SET andamentos =
  '[{"data":"2024-01-01","descricao":"Audiência de conciliação designada","arquivo_url":null}]'::jsonb
 WHERE id = '00000000-0000-0000-0000-000000000002';

INSERT INTO cumprimentos (id, processo_id, processo_codigo, andamentos) VALUES
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-000000000001', 'C1', NULL),
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-000000000001', 'C2',
    '[{"data":"2024-03-10","descricao":"Ofício Requisitório - Cessão de Crédito Homologada","arquivo_url":null}]'::jsonb),
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-000000000001', 'C3',
    '[{"data":"2024-04-05","descricao":"Conclusos para despacho","arquivo_url":null}]'::jsonb),
  ('00000000-0000-0000-0000-00000000c004', '00000000-0000-0000-0000-000000000002', 'C4', NULL);

INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre, tipo_previsto) VALUES
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'I1', '0000001-00.2020.8.26.0500', 'Precatorio'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c002', 'I2', NULL, 'Indefinido'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c003', 'I3', NULL, 'Indefinido'),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c004', 'I4', NULL, 'Indefinido');
EOF
ok "fixture inserida (I1 sem nada / I2 bate cessão / I3 tem andamento mas não bate nada / I4 só via processo raiz)"

psql_ -d sandbox -c "select classify_processo(id) from processos" >/dev/null
ok "classify_processo rodou sem erro"

eq "$(val "select cessao_credito is null from incidentes where processo_codigo='I1'")" "t" \
  "I1: zero andamento em qualquer fonte -> NULL (nunca verificado) — ANTES do fix ficava false pra sempre"

eq "$(val "select cessao_credito from incidentes where processo_codigo='I2'")" "t" \
  "I2: andamento no cumprimento bate regra de cessão -> true"

eq "$(val "select cessao_credito from incidentes where processo_codigo='I3'")" "f" \
  "I3: tem andamento (no cumprimento) mas nenhuma regra bateu -> false (verificado, não NULL)"

eq "$(val "select cessao_credito from incidentes where processo_codigo='I4'")" "f" \
  "I4: andamento só existe no PROCESSO raiz (não no cumprimento/incidente) -> ainda assim conta como verificado -> false"

# ---- classify_incidentes (caminho batch) — reseta e confirma mesmo resultado --------
psql_ -d sandbox -c "update incidentes set cessao_credito=false where processo_codigo in ('I1','I2','I3','I4')" >/dev/null
psql_ -d sandbox -c "select classify_incidentes(array_agg(id)) from incidentes where processo_codigo in ('I1','I2','I3','I4')" >/dev/null

eq "$(val "select cessao_credito is null from incidentes where processo_codigo='I1'")" "t" \
  "classify_incidentes: I1 também vira NULL (mesma lógica, caminho batch)"
eq "$(val "select cessao_credito from incidentes where processo_codigo='I2'")" "t" \
  "classify_incidentes: I2 também true"
eq "$(val "select cessao_credito from incidentes where processo_codigo='I3'")" "f" \
  "classify_incidentes: I3 também false (não NULL)"

# ---- Regressão: outros flags continuam exatamente como antes (FOR-201) --------------
psql_ -d sandbox -c "
  insert into andamentos (incidente_id, data, descricao, hash) values
    ('00000000-0000-0000-0000-00000000a001', '2023-01-01', 'Certidão de precatório expedido', 'h1')
" >/dev/null
psql_ -d sandbox -c "select classify_processo('00000000-0000-0000-0000-000000000001')" >/dev/null

eq "$(val "select oficio_expedido from incidentes where processo_codigo='I1'")" "t" \
  "regressão: oficio_expedido continua funcionando via andamento próprio do incidente, igual antes do FOR-202"
eq "$(val "select macrofase from incidentes where processo_codigo='I1'")" "precatorio_efetivo" \
  "regressão: macrofase inalterada (só cessao_credito mudou de comportamento)"
eq "$(val "select cessao_credito from incidentes where processo_codigo='I1'")" "f" \
  "I1 agora TEM andamento (acabou de ganhar um) -> false, não mais NULL (comportamento correto, não é mais 'nunca verificado')"

echo
echo "FOR-202 sandbox: TODOS OS CENÁRIOS OK"
