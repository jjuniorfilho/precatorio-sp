#!/usr/bin/env bash
#
# FOR-179 (hotfix de segurança: merge_legado_processo/merge_legado_incidente nasceram com
# EXECUTE liberado pra PUBLIC/anon, e sem guarda contra apagar linha não-legado) — valida em
# Postgres LOCAL descartável: (1) anon/PUBLIC ficam sem EXECUTE após o fix, (2) a guarda
# "LEGADO-%" bloqueia apagar uma linha REAL mesmo se chamada com o id certo, (3) o caso legítimo
# (merge de linha LEGADO- de verdade) continua funcionando igual.
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for179_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54344}"
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
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

CREATE TABLE public.processos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_codigo text UNIQUE, cnj text);
CREATE TABLE public.incidentes (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_codigo text UNIQUE, processo_id uuid REFERENCES public.processos(id) ON DELETE CASCADE, numero_depre text);
CREATE TABLE public.partes (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), processo_id uuid, incidente_id uuid);
CREATE TABLE public.andamentos (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), incidente_id uuid);
GRANT ALL ON public.processos, public.incidentes, public.partes, public.andamentos TO anon, authenticated, service_role;
EOF
ok "réplica mínima carregada (processos/incidentes/partes/andamentos)"

# Estado VIVO ANTERIOR: as 2 RPCs exatamente como estavam em produção (sem guarda, sem revoke).
psql_ -d sandbox <<'EOF'
create or replace function public.merge_legado_processo(p_legado_id uuid, p_real_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_id = p_real_id then return; end if;
  update incidentes set processo_id = p_real_id where processo_id = p_legado_id;
  update partes     set processo_id = p_real_id where processo_id = p_legado_id;
  delete from processos where id = p_legado_id;
end; $$;

create or replace function public.merge_legado_incidente(p_legado_id uuid, p_real_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_id = p_real_id then return; end if;
  delete from partes     where incidente_id = p_legado_id;
  delete from andamentos where incidente_id = p_legado_id;
  delete from incidentes where id = p_legado_id;
end; $$;

grant execute on function public.merge_legado_processo(uuid, uuid)  to service_role, authenticated;
grant execute on function public.merge_legado_incidente(uuid, uuid) to service_role, authenticated;
EOF
ok "estado VIVO anterior recriado (RPCs de agosto, sem guarda nem revoke)"

# Confirma a falha real ANTES do fix: anon consegue apagar um processo REAL (não-legado).
psql_ -d sandbox -c "
  insert into processos (id, processo_codigo, cnj) values
    ('11111111-1111-1111-1111-111111111111', 'REAL0001', '0001111-11.2020.8.26.0100'),
    ('22222222-2222-2222-2222-222222222222', 'REAL0002', '0002222-22.2020.8.26.0100');
"
psql_ -d sandbox -c "SET ROLE anon; select merge_legado_processo('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222');" \
  || falha "isto NÃO deveria falhar ainda — é a reprodução do bug real, antes do fix"
[[ -z "$(psql_ -d sandbox -Atc "select id from processos where id = '11111111-1111-1111-1111-111111111111'")" ]] \
  || falha "reprodução do bug falhou: o processo REAL deveria ter sido apagado por 'anon' (confirma o buraco)"
ok "BUG REAL REPRODUZIDO: anon apagou um processo NÃO-legado sem nenhuma autorização real"

for rodada in 1 2; do
  erros="$(psql_ -d sandbox -f "$ROOT/sql/2026-09-30_for179_hotfix_revoke_public_merge_legado.sql" 2>&1 | grep -c 'ERROR' || true)"
  [[ "$erros" == "0" ]] || falha "hotfix deu erro na rodada ${rodada}"
done
ok "hotfix aplicado 2x sem erro (re-executável)"

# 1) anon/PUBLIC não conseguem mais chamar nenhuma das duas.
#
# NUNCA `psql_ ... | grep -q "permission denied"` direto: com `set -o pipefail`, o psql
# (com -v ON_ERROR_STOP=1) sai com status != 0 exatamente quando o SQL dá o erro esperado —
# e pipefail propaga ESSA falha como status da pipeline inteira, mesmo quando o grep à direita
# ACHOU a mensagem esperada. Resultado: `|| falha` dispara mesmo com o teste passando de
# verdade. Captura a saída numa variável primeiro (com `|| true` pra não disparar `set -e`),
# grep depois, como comando separado.
saida="$(psql_ -d sandbox -c "SET ROLE anon; select merge_legado_processo(gen_random_uuid(), gen_random_uuid());" 2>&1 || true)"
echo "$saida" | grep -q "permission denied" \
  || falha "anon ainda consegue chamar merge_legado_processo após o REVOKE (saída: $saida)"
ok "anon SEM EXECUTE em merge_legado_processo (permission denied confirmado)"

saida="$(psql_ -d sandbox -c "SET ROLE anon; select merge_legado_incidente(gen_random_uuid(), gen_random_uuid());" 2>&1 || true)"
echo "$saida" | grep -q "permission denied" \
  || falha "anon ainda consegue chamar merge_legado_incidente após o REVOKE (saída: $saida)"
ok "anon SEM EXECUTE em merge_legado_incidente (permission denied confirmado)"

# 2) mesmo 'authenticated' (autorizado a chamar) não apaga mais um processo REAL por engano —
#    a guarda LEGADO-% protege mesmo o caller legítimo.
psql_ -d sandbox -c "
  insert into processos (id, processo_codigo, cnj) values
    ('33333333-3333-3333-3333-333333333333', 'REAL0003', '0003333-33.2020.8.26.0100'),
    ('44444444-4444-4444-4444-444444444444', 'REAL0004', '0004444-44.2020.8.26.0100');
"
psql_ -d sandbox -c "SET ROLE authenticated; select merge_legado_processo('33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444');"
[[ -n "$(psql_ -d sandbox -Atc "select id from processos where id = '33333333-3333-3333-3333-333333333333'")" ]] \
  || falha "REGRESSÃO: a guarda deveria ter impedido apagar um processo REAL (não-legado), mesmo chamado por 'authenticated'"
ok "GUARDA: mesmo 'authenticated' não apaga processo REAL (só age em linhas LEGADO-%)"

# 3) caso legítimo continua funcionando: merge de uma linha LEGADO- de verdade.
psql_ -d sandbox -c "
  insert into processos (id, processo_codigo, cnj) values
    ('55555555-5555-5555-5555-555555555555', 'LEGADO-0005555', '0005555-55.2020.8.26.0100'),
    ('66666666-6666-6666-6666-666666666666', 'REAL0006', '0005555-55.2020.8.26.0100');
  insert into incidentes (processo_id, processo_codigo, numero_depre) values
    ('55555555-5555-5555-5555-555555555555', 'LEGADO-INC-0007', '0007777-77.2020.8.26.0500');
"
psql_ -d sandbox -c "SET ROLE authenticated; select merge_legado_processo('55555555-5555-5555-5555-555555555555', '66666666-6666-6666-6666-666666666666');"
[[ -z "$(psql_ -d sandbox -Atc "select id from processos where id = '55555555-5555-5555-5555-555555555555'")" ]] \
  || falha "caso legítimo: linha LEGADO- deveria ter sido apagada após o merge"
[[ "$(psql_ -d sandbox -Atc "select processo_id from incidentes where processo_codigo = 'LEGADO-INC-0007'")" == "66666666-6666-6666-6666-666666666666" ]] \
  || falha "caso legítimo: incidente deveria ter sido reapontado pro processo real"
ok "CASO LEGÍTIMO: merge de linha LEGADO- de verdade continua funcionando igual"

echo
echo "=== FOR-179 (hotfix: revoke PUBLIC/anon + guarda LEGADO-% em merge_legado_*): tudo ok ==="
