#!/usr/bin/env bash
#
# FOR-173 — valida os SQLs 1 a 6 num Postgres LOCAL descartável (nunca toca produção).
#
# Por quê: os testes do worker só conferem o TEXTO dos SQLs. Este script EXECUTA de verdade, contra uma réplica do
# schema vivo de `leads` (sql/sandbox/for173_sandbox_schema.sql): aplica 1..4 duas vezes (re-executável), roda a
# verificação (SQL 5, tudo ok = true) e o roteiro comportamental (SQL 6, 0 FALHOU) e prova que nada ficou gravado.
# Também prova o achado H1 (antes do SQL 1, o anon FORJA origem='avulso' com consentimento).
#
# Requer o PostgreSQL 15+ instalado (Homebrew: `brew install postgresql@15`). Uso:
#   sql/sandbox/for173_validate_local.sh
#   PGBIN=/caminho/para/bin PORT_SANDBOX=54330 sql/sandbox/for173_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54329}"
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
psql_ -d sandbox -f "$ROOT/sql/sandbox/for173_sandbox_schema.sql" 2>&1 | grep -v NOTICE || true
[[ "$(psql_ -d sandbox -Atc "select count(*) from information_schema.columns where table_name='leads_processos'")" == "32" ]] \
  || falha "réplica do schema não carregou (leads_processos deveria ter 32 colunas)"
ok "schema-réplica de produção carregado (32 colunas em leads_processos)"

# --- H1: antes do SQL 1, o anon forja avulso com consentimento (a policy original só exige lgpd_consent = true)
# (sem RETURNING: como anon o INSERT...RETURNING exigiria também uma policy de SELECT, que o anon não tem)
forjado="$(psql_ -d sandbox -Atc "SET ROLE anon; INSERT INTO public.leads (email, relacao, lgpd_consent, origem, processo_depre) VALUES ('f@x.com','titular',true,'avulso','0000010-01.2020.8.26.0500'); RESET ROLE; SELECT origem FROM public.leads" | head -1)"
[[ "$forjado" == "avulso" ]] || falha "esperava que a policy ORIGINAL deixasse o anon forjar avulso (baseline do achado H1)"
psql_ -d sandbox -c "DELETE FROM public.leads"
ok "baseline H1 confirmado: com a policy original o anon consegue gravar origem='avulso'"

# --- aplica 1..4 duas vezes
for rodada in 1 2; do
  for f in 1_leads_avulso 2_view_leads_processos_origem 3_tabela_progresso 4_rpcs_progresso; do
    erros="$(psql_ -d sandbox -f "$ROOT/sql/2026-09-28_for173_${f}.sql" 2>&1 | grep -c 'ERROR' || true)"
    [[ "$erros" == "0" ]] || falha "SQL ${f} deu erro na rodada ${rodada}"
  done
done
ok "SQLs 1 a 4 aplicados 2x sem erro (re-executáveis)"

# --- SQL 5: tudo ok = true
verif="$(psql_ -d sandbox -At -f "$ROOT/sql/2026-09-28_for173_5_verifica_aplicacao.sql")"
total="$(echo "$verif" | grep -c '|' || true)"; certos="$(echo "$verif" | grep -c '|t$' || true)"
[[ "$total" -ge 30 && "$total" == "$certos" ]] || { echo "$verif" | grep -v '|t$' >&2; falha "SQL 5: $certos/$total ok=true"; }
ok "SQL 5 (verificação): $certos/$total ok = true"

# --- SQL 6: roteiro comportamental (o RAISE final carrega o relatório e desfaz tudo)
rel="$(psql_ -d sandbox -f "$ROOT/sql/2026-09-28_for173_6_roteiro_teste_transacional.sql" 2>&1 || true)"
resumo="$(echo "$rel" | grep -E 'RESUMO:' | head -1)"
[[ "$resumo" =~ ,\ 0\ FALHOU ]] || { echo "$rel" | grep -E '^FALHOU' >&2; falha "SQL 6: $resumo"; }
ok "SQL 6 (roteiro): ${resumo#*RESUMO: }"

# --- nada persistiu; e o worker fala com a RPC pelos nomes certos (chamada com argumentos nomeados)
[[ "$(psql_ -d sandbox -Atc "select (select count(*) from leads)+(select count(*) from pagamentos_consultas_progresso)")" == "0" ]] \
  || falha "o roteiro deixou linhas gravadas"
ok "nada ficou gravado pelo roteiro"
nomes="$(grep -A14 'export async function registrarProgressoPagamento' "$ROOT/worker-crawler/src/supabase.ts" | grep -o 'p_[a-z_]*:' | tr -d ':' | sort | tr '\n' ' ')"
esperados="p_detalhe p_estado p_etapa p_etapa_falha p_max_tentativas p_nova p_origem p_processo_depre p_resultado p_tentativa "
[[ "$nomes" == "$esperados" ]] || falha "nomes p_* do worker divergem da RPC: $nomes"
psql_ -d sandbox -c "SELECT public.registrar_progresso_consulta_pagamento(p_processo_depre => '0000777-01.2020.8.26.0500', p_estado => 'em_andamento', p_etapa => 'busca', p_tentativa => 2, p_max_tentativas => 4, p_detalhe => 'x', p_resultado => NULL, p_etapa_falha => NULL, p_origem => 'manual', p_nova => true)" >/dev/null
ok "RPC chamada com os 10 nomes p_* que o worker envia (argumentos nomeados, como o PostgREST)"
echo; echo "TUDO OK — SQLs do FOR-173 validados em Postgres real (sandbox descartável)."
