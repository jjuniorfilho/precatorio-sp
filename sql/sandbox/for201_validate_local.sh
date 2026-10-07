#!/usr/bin/env bash
#
# FOR-201 (passo 2) — valida classify_processo/classify_incidentes com as 3 fontes de
# andamentos (incidente + cumprimento + processo raiz) num Postgres local efêmero, ANTES
# de pedir aplicação manual no SQL Editor de produção.
#
# Cenário central: um incidente SEM nenhum andamento próprio, cuja única evidência de
# cessão de crédito / ordem cronológica está no jsonb do CUMPRIMENTO ou do PROCESSO pai —
# exatamente o caso que hoje (antes do FOR-201) nunca era classificado.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for201_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54351}"
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

# Schema mínimo — só as tabelas/colunas que classify_processo/classify_incidentes tocam.
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text UNIQUE NOT NULL,
  cnj text, cnj_normalizado text,
  last_crawled_at timestamptz, next_crawl_at timestamptz,
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid REFERENCES processos(id),
  processo_codigo text UNIQUE NOT NULL,
  cnj text, cnj_normalizado text
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
ok "schema mínimo criado (pré-FOR-201: sem as colunas andamentos jsonb ainda)"

# Passo 1 (migration anterior) — adiciona as colunas jsonb.
psql_ -d sandbox -f "$ROOT/sql/2026-10-07_for201_andamentos_cumprimento_processo.sql" >/dev/null
ok "migration passo 1 aplicada (processos.andamentos / cumprimentos.andamentos)"

# Passo 2 (esta migration) — classify_processo/classify_incidentes com as 3 fontes.
psql_ -d sandbox -f "$ROOT/sql/2026-10-07_for201_classify_usa_andamentos_cumprimento_processo.sql" >/dev/null
ok "migration passo 2 aplicada (classify_processo/classify_incidentes)"

# ---- Fixture -----------------------------------------------------------------------
# P1: processo raiz, SEM andamentos próprios.
#   C1 (cumprimento): SEM andamentos próprios. I1 (incidente, tipo Precatorio): SEM
#     andamentos próprios, mas numero_depre setado (has_depre=true).
#   C2 (cumprimento): COM andamentos próprios contendo cessão de crédito. I2 (incidente):
#     SEM andamentos próprios nenhum — a única evidência de cessão está em C2.andamentos.
# P2: processo raiz COM andamentos próprios contendo "Ordem Cronológica ... 2024".
#   C3 (cumprimento): SEM andamentos próprios. I3 (incidente, tipo RPV): SEM andamentos
#     próprios — a única evidência de OC está em P2.andamentos (nível processo, não
#     cumprimento).
# I4 (sob C1): COM andamento PRÓPRIO de oficio_expedido (comportamento pré-existente,
#   não deve regredir) — tipo Precatorio, confirma macrofase = precatorio_efetivo.
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, last_crawled_at) VALUES
  ('00000000-0000-0000-0000-000000000001', 'P1', now()),
  ('00000000-0000-0000-0000-000000000002', 'P2', now());

INSERT INTO cumprimentos (id, processo_id, processo_codigo, andamentos) VALUES
  ('00000000-0000-0000-0000-00000000c001', '00000000-0000-0000-0000-000000000001', 'C1', NULL),
  ('00000000-0000-0000-0000-00000000c002', '00000000-0000-0000-0000-000000000001', 'C2',
    '[{"data":"2024-03-10","descricao":"Ofício Requisitório - Cessão de Crédito Homologada","arquivo_url":null}]'::jsonb),
  ('00000000-0000-0000-0000-00000000c003', '00000000-0000-0000-0000-000000000002', 'C3', NULL);

UPDATE processos SET andamentos =
  '[{"data":"2024-05-20","descricao":"Ordem Cronológica referente ao exercício de 2024","arquivo_url":null}]'::jsonb
 WHERE id = '00000000-0000-0000-0000-000000000002';

INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre, tipo_previsto) VALUES
  ('00000000-0000-0000-0000-00000000a001', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'I1', '0000001-00.2020.8.26.0500', 'Precatorio'),
  ('00000000-0000-0000-0000-00000000a002', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c002', 'I2', NULL, 'Indefinido'),
  ('00000000-0000-0000-0000-00000000a003', '00000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000c003', 'I3', NULL, 'RPV'),
  ('00000000-0000-0000-0000-00000000a004', '00000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000c001', 'I4', NULL, 'Precatorio');

INSERT INTO andamentos (incidente_id, data, descricao, hash) VALUES
  ('00000000-0000-0000-0000-00000000a004', '2023-01-01', 'Certidão de precatório expedido', 'h1');
EOF
ok "fixture inserida (I1/I2/I3/I4 — evidência relevante fora do próprio incidente em I2 e I3)"

psql_ -d sandbox -c "select classify_processo(id) from processos" >/dev/null
ok "classify_processo rodou pros 2 processos sem erro"

# ---- Asserções -----------------------------------------------------------------------
eq "$(val "select cessao_credito from incidentes where processo_codigo='I1'")" "f" \
  "I1: sem evidência em nenhum nível — cessao_credito=false (não é falso positivo cruzado com I2/C2)"

eq "$(val "select cessao_credito from incidentes where processo_codigo='I2'")" "t" \
  "I2: cessão só existe em C2.andamentos (cumprimento pai) — detectada (ANTES do FOR-201 ficaria false pra sempre)"

eq "$(val "select ordem_cronologica from incidentes where processo_codigo='I3'")" "t" \
  "I3: OC só existe em P2.andamentos (processo raiz) — detectada (ANTES do FOR-201 ficaria false pra sempre)"
eq "$(val "select fase from incidentes where processo_codigo='I3'")" "oc" \
  "I3: fase='oc' derivada do flag cruzado"
eq "$(val "select ano_oc from incidentes where processo_codigo='I3'")" "2024" \
  "I3: ano_oc extraído por regex do texto em P2.andamentos (nível processo), não do próprio incidente"

eq "$(val "select oficio_expedido from incidentes where processo_codigo='I4'")" "t" \
  "I4: comportamento PRÉ-EXISTENTE (andamento próprio do incidente) não regrediu"
eq "$(val "select macrofase from incidentes where processo_codigo='I4'")" "precatorio_efetivo" \
  "I4: macrofase inalterada pelo fix (continua derivando só dos flags, mesma lógica de sempre)"

eq "$(val "select next_crawl_at is not null from processos where processo_codigo='P1'")" "t" \
  "next_crawl_at continua sendo atualizado (comportamento pré-existente preservado)"

# ---- classify_incidentes (variante batch, usada pra processos "mega") ----------------
# Reseta os 2 flags-chave e roda só via classify_incidentes, confirma mesmo resultado.
psql_ -d sandbox -c "update incidentes set cessao_credito=false, ordem_cronologica=false, fase=null, ano_oc=null where processo_codigo in ('I2','I3')" >/dev/null
psql_ -d sandbox -c "select classify_incidentes(array[id]) from incidentes where processo_codigo in ('I2','I3')" >/dev/null

eq "$(val "select cessao_credito from incidentes where processo_codigo='I2'")" "t" \
  "classify_incidentes: I2 também detecta via cumprimento pai (mesma lógica, caminho batch)"
eq "$(val "select ano_oc from incidentes where processo_codigo='I3'")" "2024" \
  "classify_incidentes: I3 também detecta via processo raiz (mesma lógica, caminho batch)"

echo
echo "FOR-201 (passo 2) sandbox: TODOS OS CENÁRIOS OK"
