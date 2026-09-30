#!/usr/bin/env bash
#
# FOR-177 (leads_processos ganha processo principal/cumprimento/nº do incidente) — valida a
# view nova num Postgres LOCAL descartável, recriando o estado VIVO ANTERIOR (34→37 colunas não,
# 33 colunas — pós FOR-176) antes de aplicar a migration nova por cima. Mesma lição aprendida
# reproduzindo os 2 erros reais do FOR-176 (42P16 + mudança de tipo): sem recriar o estado
# anterior, CREATE OR REPLACE VIEW nunca faz as checagens que batem em produção.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for177_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54342}"
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

CREATE TABLE public.precatorios (processo_depre text, saldo_depre bigint, valor_pago bigint, pagamentos_consultado_em timestamptz, updated_at timestamptz);
CREATE TABLE public.precatorios_pagamentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_depre text NOT NULL, data_pagamento date NOT NULL, valor bigint NOT NULL, tipo text NOT NULL DEFAULT '');
CREATE TABLE public.pagamentos_consultas_log (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_depre text NOT NULL, iniciada_em timestamptz NOT NULL, finalizada_em timestamptz, resultado text NOT NULL CHECK (resultado IN ('encontrado','nao_consta','falha')));
REVOKE ALL ON public.pagamentos_consultas_log FROM anon, authenticated;
-- FOR-177: origem_cnjs (fallback de processo principal via ficha) + processos/cumprimentos
-- (hierarquia do schema novo) — não existiam na réplica anterior (for174c).
CREATE TABLE public.djen_depre (cnj_normalizado text, acordo_homologado boolean, valor_acao bigint, ficha_crawled_at timestamptz, origem_cnjs text[]);
CREATE TABLE public.processos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), cnj text);
CREATE TABLE public.cumprimentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), cnj text, processo_id uuid REFERENCES public.processos(id));
CREATE TABLE public.incidentes (
  numero_depre text, cessao_credito boolean, numero_incidente text,
  processo_id uuid REFERENCES public.processos(id),
  cumprimento_id uuid REFERENCES public.cumprimentos(id)
);

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

-- Estado VIVO ANTERIOR (pós-FOR-176, 33 colunas, origem por último) — igual ao produzido por
-- sql/2026-09-29_for174c_leads_processos_fallback_pagamentos.sql, já em produção.
CREATE VIEW public.leads_processos WITH (security_invoker = true) AS
SELECT
  lp.id, lp.nome, lp.email, lp.telefone, lp.relacao, lp.processo_depre, lp.saldo_consultado,
  lp.devedora, lp.status_crm, lp.notas, lp.token_email_validado, lp.token_telefone_validado,
  lp.relatorio_enviado_at, lp.session_id, lp.intent, lp.created_at, lp.updated_at, lp.verified_at,
  lp.nivel_funil, lp.etapa1_busca, lp.etapa2_cadastro, lp.etapa3_token_email,
  lp.etapa4_email_validado, lp.etapa5_whatsapp_validado, lp.etapa6_relatorio,
  p.processo, dj.valor_causa, pr.saldo_depre,
  COALESCE(pr.valor_pago, vivo.valor_pago_vivo) AS valor_pago,
  COALESCE(pr.pagamentos_consultado_em, vivo.consultado_em_vivo) AS pagamentos_consultado_em,
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
  SELECT
    CASE WHEN soma.total > 0 THEN soma.total WHEN log.finalizada_em IS NOT NULL THEN 0 ELSE NULL END AS valor_pago_vivo,
    log.finalizada_em AS consultado_em_vivo
  FROM (SELECT COALESCE(SUM(valor), 0)::bigint AS total FROM public.precatorios_pagamentos WHERE processo_depre = p.processo) soma
  LEFT JOIN LATERAL (
    SELECT finalizada_em FROM public.pagamentos_consultas_log
    WHERE processo_depre = p.processo AND resultado IN ('encontrado', 'nao_consta') ORDER BY finalizada_em DESC NULLS LAST LIMIT 1
  ) log ON true
) vivo ON pr.valor_pago IS NULL
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
ok "réplica mínima carregada + estado VIVO anterior (33 colunas, pós-FOR-176) recriado"

for rodada in 1 2; do
  erros="$(psql_ -d sandbox -f "$ROOT/sql/2026-09-30_for177_leads_processos_processo_principal.sql" 2>&1 | grep -c 'ERROR' || true)"
  [[ "$erros" == "0" ]] || falha "view deu erro na rodada ${rodada}"
done
ok "view aplicada 2x sem erro (re-executável)"

read_col() {
  psql_ -d sandbox -Atc "SELECT $1 FROM leads_processos WHERE processo = '$2'"
}

DEP_HIERARQUIA="0253361-73.2018.8.26.0500"  # tem incidente+cumprimento+processo ligados
DEP_SO_FICHA="0000003-03.2020.8.26.0500"    # só tem ficha (djen_depre) COM origem_cnjs, sem incidente ligado
DEP_LEGADO="0000004-04.2020.8.26.0500"      # nem ficha nem incidente — nada disso disponível
DEP_FICHA_SEM_ORIGEM="0000005-05.2020.8.26.0500"  # tem ficha (djen_depre) mas SEM origem_cnjs — caso mais comum na prática

psql_ -d sandbox -c "
  INSERT INTO leads (email, relacao, lgpd_consent, origem, processo_depre) VALUES
    ('a@x.com','titular',true,'avulso','$DEP_HIERARQUIA'),
    ('b@x.com','titular',true,'avulso','$DEP_SO_FICHA'),
    ('c@x.com','titular',true,'avulso','$DEP_LEGADO'),
    ('e@x.com','titular',true,'avulso','$DEP_FICHA_SEM_ORIGEM');

  INSERT INTO processos (id, cnj) VALUES ('11111111-1111-1111-1111-111111111111', '0009394-05.2011.8.26.0565');
  INSERT INTO cumprimentos (id, cnj, processo_id) VALUES ('22222222-2222-2222-2222-222222222222', '0006914-78.2016.8.26.0565', '11111111-1111-1111-1111-111111111111');
  INSERT INTO incidentes (numero_depre, numero_incidente, processo_id, cumprimento_id)
    VALUES ('$DEP_HIERARQUIA', '00001', '11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');

  INSERT INTO djen_depre (cnj_normalizado, origem_cnjs, ficha_crawled_at)
    VALUES (regexp_replace('$DEP_SO_FICHA', '\D', '', 'g'), ARRAY['1005875-81.2022.8.26.0609'], now());

  -- Regressão do bug real batido em produção: DEP_HIERARQUIA (que já tem incidente ligado)
  -- TAMBÉM tem ficha crawleada (djen_depre existe), mas SEM origem_cnjs preenchido — o caso
  -- mais COMUM na prática (a maioria das fichas não lista CNJ de origem), não o raro. Sem essa
  -- linha, nenhum teste aqui exercitava array_agg(origem_cnjs) contra uma linha com origem_cnjs
  -- NULL — e foi exatamente isso que derrubou a grade inteira de /admin/leads em produção
  -- ('cannot accumulate null arrays').
  INSERT INTO djen_depre (cnj_normalizado, origem_cnjs, ficha_crawled_at)
    VALUES (regexp_replace('$DEP_HIERARQUIA', '\D', '', 'g'), NULL, now());

  -- Mesmo caso, mas isolado (sem incidente/cumprimento/processo ligados também) — representa a
  -- MAIORIA dos leads reais: ficha crawleada, sem origem_cnjs, sem hierarquia do schema novo.
  INSERT INTO djen_depre (cnj_normalizado, origem_cnjs, ficha_crawled_at)
    VALUES (regexp_replace('$DEP_FICHA_SEM_ORIGEM', '\D', '', 'g'), NULL, now());
"

[[ "$(read_col processo_principal "$DEP_HIERARQUIA")" == "0009394-05.2011.8.26.0565" ]] \
  || falha "processo_principal deveria vir do schema novo (processos.cnj) pro DEP_HIERARQUIA; achou '$(read_col processo_principal "$DEP_HIERARQUIA")'"
[[ "$(read_col cumprimento_sentenca "$DEP_HIERARQUIA")" == "0006914-78.2016.8.26.0565" ]] \
  || falha "cumprimento_sentenca errado"
[[ "$(read_col numero_incidente "$DEP_HIERARQUIA")" == "00001" ]] \
  || falha "numero_incidente errado"
ok "hierarquia completa (schema novo): processo_principal/cumprimento_sentenca/numero_incidente corretos"

[[ "$(read_col processo_principal "$DEP_SO_FICHA")" == "1005875-81.2022.8.26.0609" ]] \
  || falha "processo_principal deveria cair pro fallback da ficha (origem_cnjs) pro DEP_SO_FICHA; achou '$(read_col processo_principal "$DEP_SO_FICHA")'"
[[ -z "$(read_col cumprimento_sentenca "$DEP_SO_FICHA")" ]] || falha "cumprimento_sentenca não deveria existir (só ficha, sem incidente ligado)"
[[ -z "$(read_col numero_incidente "$DEP_SO_FICHA")" ]] || falha "numero_incidente não deveria existir (só ficha, sem incidente ligado)"
ok "só ficha (sem incidente ligado): processo_principal cai pro fallback, cumprimento/incidente ficam null"

[[ -z "$(read_col processo_principal "$DEP_LEGADO")" ]] || falha "processo_principal deveria ser null (nenhuma fonte disponível)"
[[ -z "$(read_col cumprimento_sentenca "$DEP_LEGADO")" ]] || falha "cumprimento_sentenca deveria ser null"
[[ -z "$(read_col numero_incidente "$DEP_LEGADO")" ]] || falha "numero_incidente deveria ser null"
ok "nenhuma fonte: os 3 campos ficam null (nunca '—' fabricado na view)"

# Regressão do bug real que derrubou a grade inteira de /admin/leads em produção: ficha
# crawleada (djen_depre existe) mas SEM origem_cnjs — array_agg sem FILTER lançava "cannot
# accumulate null arrays" pra QUALQUER lead nesse caso (a maioria).
[[ -z "$(read_col processo_principal "$DEP_FICHA_SEM_ORIGEM")" ]] \
  || falha "processo_principal deveria ser null (ficha sem origem_cnjs, sem incidente)"
ok "REGRESSÃO REAL: ficha com origem_cnjs NULL não lança 'cannot accumulate null arrays' (bug que derrubou a grade em produção)"

# Regressão específica dos 2 erros reais do FOR-176: confirma que as colunas ANTERIORES (33,
# incl. origem) sobrevivem à substituição.
[[ "$(psql_ -d sandbox -Atc "SELECT origem FROM leads_processos WHERE processo = '$DEP_HIERARQUIA'")" == "avulso" ]] \
  || falha "coluna 'origem' (FOR-173/176) não sobreviveu à substituição da view"
ok "colunas anteriores (33, incl. 'origem') sobrevivem à substituição — sem repetir o 42P16"

echo
echo "=== FOR-177 (leads_processos + processo principal/cumprimento/incidente): tudo ok ==="
