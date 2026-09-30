#!/usr/bin/env bash
#
# FOR-174 (fallback de leitura em leads_processos) — valida a view nova num Postgres LOCAL
# descartável. Réplica mínima (leads/leads_com_progresso iguais à produção — mesma base do
# for173_sandbox_schema.sql — + precatorios/precatorios_pagamentos/pagamentos_consultas_log/
# djen_depre/incidentes só com as colunas que a view usa).
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for174c_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54333}"
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

psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;
GRANT anon, authenticated, service_role TO CURRENT_USER;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL ON TABLES TO anon, authenticated, service_role;
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

CREATE TABLE public.leads (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nome text, email text, telefone text, relacao text, processo_depre text,
  saldo_consultado bigint NOT NULL DEFAULT 0, devedora text,
  status_crm text NOT NULL DEFAULT 'novo', notas text DEFAULT '',
  token_email_validado boolean NOT NULL DEFAULT false, token_telefone_validado boolean NOT NULL DEFAULT false,
  session_id text, intent text, lgpd_consent boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(), updated_at timestamptz DEFAULT now(),
  relatorio_enviado_at timestamptz, verified_at timestamptz, origem text
);
CREATE TABLE public.funnel_events (event_type text, lead_id uuid, session_id text);

-- só as colunas que a view usa (réplica mínima, não o schema real inteiro)
CREATE TABLE public.precatorios (processo_depre text, saldo_depre bigint, valor_pago bigint, pagamentos_consultado_em timestamptz, updated_at timestamptz);
CREATE TABLE public.precatorios_pagamentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_depre text NOT NULL, data_pagamento date NOT NULL, valor bigint NOT NULL, tipo text NOT NULL DEFAULT '');
CREATE TABLE public.pagamentos_consultas_log (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_depre text NOT NULL, iniciada_em timestamptz NOT NULL, finalizada_em timestamptz, resultado text NOT NULL CHECK (resultado IN ('encontrado','nao_consta','falha')));
REVOKE ALL ON public.pagamentos_consultas_log FROM anon, authenticated;
CREATE TABLE public.djen_depre (cnj_normalizado text, acordo_homologado boolean, valor_acao bigint, ficha_crawled_at timestamptz);
CREATE TABLE public.incidentes (numero_depre text, cessao_credito boolean);

CREATE VIEW public.leads_com_progresso WITH (security_invoker = true) AS
 SELECT id, nome, email, telefone, relacao, processo_depre, saldo_consultado, devedora, status_crm, notas,
    token_email_validado, token_telefone_validado, session_id, lgpd_consent, created_at, updated_at, intent,
    relatorio_enviado_at, verified_at, origem,
    2 AS nivel_funil,
    true AS etapa1_busca, true AS etapa2_cadastro, false AS etapa3_token_email,
    false AS etapa4_email_validado, false AS etapa5_whatsapp_validado,
    relatorio_enviado_at IS NOT NULL AS etapa6_relatorio
   FROM leads l;
REVOKE ALL ON public.leads_com_progresso FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_com_progresso TO service_role;

-- Estado VIVO de produção ANTES desta migration: leads_processos como o FOR-173 deixou (33
-- colunas, `origem` por último — sql/2026-09-28_for173_2_view_leads_processos_origem.sql).
-- Achado real (2026-09-29, 1ª tentativa de aplicar em prod): sem recriar esse estado ANTERIOR
-- aqui, `CREATE OR REPLACE VIEW` na migration nova nunca teria uma view pré-existente pra
-- comparar — o Postgres só reclama de "cannot drop columns" quando REALMENTE substitui uma
-- view já viva; contra uma view inexistente é um CREATE normal, sem checagem nenhuma. Esta
-- seção existe especificamente pra fechar essa lacuna de metodologia.
CREATE VIEW public.leads_processos WITH (security_invoker = true) AS
SELECT
  lp.id, lp.nome, lp.email, lp.telefone, lp.relacao, lp.processo_depre, lp.saldo_consultado,
  lp.devedora, lp.status_crm, lp.notas, lp.token_email_validado, lp.token_telefone_validado,
  lp.relatorio_enviado_at, lp.session_id, lp.intent, lp.created_at, lp.updated_at, lp.verified_at,
  lp.nivel_funil, lp.etapa1_busca, lp.etapa2_cadastro, lp.etapa3_token_email,
  lp.etapa4_email_validado, lp.etapa5_whatsapp_validado, lp.etapa6_relatorio,
  p.processo, dj.valor_causa, pr.saldo_depre, pr.valor_pago, pr.pagamentos_consultado_em,
  dj.acordo_homologado, inc.cessao_credito, lp.origem
FROM public.leads_com_progresso lp
LEFT JOIN LATERAL (
  SELECT DISTINCT btrim(x) AS processo FROM regexp_split_to_table(coalesce(lp.processo_depre, ''), ',') AS x WHERE btrim(x) <> ''
) p ON true
LEFT JOIN LATERAL (
  SELECT r.saldo_depre, r.valor_pago, r.pagamentos_consultado_em FROM public.precatorios r
  WHERE r.processo_depre = p.processo ORDER BY r.updated_at DESC NULLS LAST LIMIT 1
) pr ON true
LEFT JOIN LATERAL (
  SELECT bool_or(d.acordo_homologado) AS acordo_homologado,
         max(d.valor_acao) FILTER (WHERE d.ficha_crawled_at IS NOT NULL) AS valor_causa
  FROM public.djen_depre d WHERE d.cnj_normalizado = regexp_replace(p.processo, '\D', '', 'g')
) dj ON true
LEFT JOIN LATERAL (
  SELECT bool_or(i.cessao_credito) AS cessao_credito FROM public.incidentes i WHERE i.numero_depre = p.processo
) inc ON true;
REVOKE ALL ON public.leads_processos FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leads_processos TO service_role;
EOF
ok "réplica mínima carregada (leads/leads_com_progresso + precatorios/precatorios_pagamentos/pagamentos_consultas_log/djen_depre/incidentes)"
ok "estado VIVO pré-migration recriado: leads_processos com 33 colunas (origem por último, FOR-173)"

for rodada in 1 2; do
  erros="$(psql_ -d sandbox -f "$ROOT/sql/2026-09-29_for174c_leads_processos_fallback_pagamentos.sql" 2>&1 | grep -c 'ERROR' || true)"
  [[ "$erros" == "0" ]] || falha "view deu erro na rodada ${rodada}"
done
ok "view aplicada 2x sem erro (re-executável)"

DEP_NOVO="0253361-73.2018.8.26.0500"   # só schema novo, sem linha em precatorios
DEP_LEGADO="0145616-63.2020.8.26.0500" # tem linha em precatorios (PDF)
DEP_NUNCA="0000001-01.2020.8.26.0500"  # nunca consultado por ninguém

psql_ -d sandbox -c "
  INSERT INTO leads (email, relacao, lgpd_consent, origem, processo_depre) VALUES
    ('a@x.com','titular',true,'avulso','$DEP_NOVO'),
    ('b@x.com','titular',true,'avulso','$DEP_LEGADO'),
    ('c@x.com','titular',true,'avulso','$DEP_NUNCA');
  -- nível 1: DEP_LEGADO tem linha em precatorios (simula o PDF já importado, valor_pago=0 lido antigamente)
  INSERT INTO precatorios (processo_depre, saldo_depre, valor_pago, pagamentos_consultado_em, updated_at)
    VALUES ('$DEP_LEGADO', 700000, 0, now() - interval '10 days', now());
  -- nível 2: DEP_NOVO só tem os dados vivos (scraper), nunca teve linha em precatorios
  INSERT INTO precatorios_pagamentos (processo_depre, data_pagamento, valor, tipo) VALUES
    ('$DEP_NOVO', '2020-01-01', 100000, 'Cronológica'),
    ('$DEP_NOVO', '2020-02-01', 50000, 'Cronológica');
  INSERT INTO pagamentos_consultas_log (processo_depre, iniciada_em, finalizada_em, resultado)
    VALUES ('$DEP_NOVO', now() - interval '1 minute', now(), 'encontrado');
"

read_valor() {
  psql_ -d sandbox -Atc "SELECT valor_pago FROM leads_processos WHERE processo = '$1'"
}
read_consultado() {
  psql_ -d sandbox -Atc "SELECT (pagamentos_consultado_em IS NOT NULL) FROM leads_processos WHERE processo = '$1'"
}

[[ "$(read_valor "$DEP_LEGADO")" == "0" ]] \
  || falha "nível 1 (precatorios/PDF) deveria vencer pro DEP_LEGADO (esperava 0, o valor do PDF)"
ok "nível 1 (precatorios/PDF) continua sendo o autoritativo quando existe — nunca sobrescrito pelo nível 2"

[[ "$(read_valor "$DEP_NOVO")" == "150000" ]] \
  || falha "nível 2 deveria somar precatorios_pagamentos pro DEP_NOVO (esperava 150000, achou $(read_valor "$DEP_NOVO"))"
[[ "$(read_consultado "$DEP_NOVO")" == "t" ]] || falha "DEP_NOVO deveria ter pagamentos_consultado_em preenchido (nível 2)"
ok "nível 2 (scraper ao vivo + log) preenche o que o nível 1 (precatorios) deixou em branco — achado real corrigido"

[[ -z "$(read_valor "$DEP_NUNCA")" ]] || falha "DEP_NUNCA não deveria ter valor_pago (nunca foi consultado com sucesso)"
[[ "$(read_consultado "$DEP_NUNCA")" == "f" ]] || falha "DEP_NUNCA não deveria ter pagamentos_consultado_em"
ok "DEP nunca consultado continua 'Não verificado' (null), nunca vira 'Não' por engano"

# --- nao_consta (0 pagamentos, mas consultado com sucesso) -> valor_pago=0, NÃO null
DEP_NAO_CONSTA="0000002-02.2020.8.26.0500"
psql_ -d sandbox -c "
  INSERT INTO leads (email, relacao, lgpd_consent, origem, processo_depre) VALUES ('d@x.com','titular',true,'avulso','$DEP_NAO_CONSTA');
  INSERT INTO pagamentos_consultas_log (processo_depre, iniciada_em, finalizada_em, resultado)
    VALUES ('$DEP_NAO_CONSTA', now() - interval '1 minute', now(), 'nao_consta');
"
[[ "$(read_valor "$DEP_NAO_CONSTA")" == "0" ]] \
  || falha "nao_consta (0 pagamentos, consultado com sucesso) deveria dar valor_pago=0, não null; achou '$(read_valor "$DEP_NAO_CONSTA")'"
ok "nao_consta vira valor_pago=0 (não null) — formatPagamento mostra 'Não (consultado em X)', não 'Não verificado'"

# --- Regressão específica do erro real (42P16 cannot drop columns): confirma que `origem`
# (33ª coluna, FOR-173) sobreviveu à substituição da view e continua legível.
[[ "$(psql_ -d sandbox -Atc "SELECT origem FROM leads_processos WHERE processo = '$DEP_NOVO'")" == "avulso" ]] \
  || falha "coluna 'origem' (FOR-173) não sobreviveu à substituição da view"
ok "coluna 'origem' (FOR-173, 33ª coluna) sobrevive à substituição da view — não é mais possível reintroduzir o 42P16"

echo
echo "=== FOR-174c (fallback leads_processos): tudo ok ==="
