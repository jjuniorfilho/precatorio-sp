#!/usr/bin/env bash
#
# FOR-178 (reconciliação LEGADO no nível do CUMPRIMENTO) — valida a RPC nova
# merge_legado_processo_para_cumprimento num Postgres LOCAL descartável, reproduzindo o caso real
# (DEPRE 0088499-12.2023.8.26.0500, cumprimento 0016525-29.2022.8.26.0053, raiz real
# 0023830-02.2001.8.26.0053) e executando, em SQL, a MESMA sequência que o worker
# (supabase.ts: persistTree) executa: upsert raiz → upsert cumprimento → busca LEGADO- pelo cnj do
# cumprimento → RPC nova → recarrega incidentes LEGADO- do processo → rename/merge do incidente →
# upsert do incidente real.
#
# Cenários:
#   A) 1º crawl (só existe o legado)                → rename do incidente, 1 linha com cumprimento_id
#   B) hierarquia paralela já existe (crawl antigo) → merge_legado_incidente apaga a órfã, 1 linha
#   C) idempotência (2ª chamada da RPC)             → no-op
#   D) guardas: processo não-LEGADO → no-op; cumprimento de outra árvore → erro
#   E) grants: PUBLIC/anon sem EXECUTE; service_role/authenticated com
#
# Requer PostgreSQL 15+ (Homebrew: brew install postgresql@15). Uso:
#   sql/sandbox/for178_validate_local.sh
set -euo pipefail

PGBIN="${PGBIN:-/opt/homebrew/opt/postgresql@15/bin}"
PORT="${PORT_SANDBOX:-54345}"
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

# Schema mínimo espelhando FOR-69 (mesmas FKs ON DELETE CASCADE e UNIQUE de processo_codigo).
psql_ -d sandbox <<'EOF'
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE ROLE anon NOLOGIN;
CREATE ROLE authenticated NOLOGIN;
CREATE ROLE service_role NOLOGIN BYPASSRLS;

CREATE TABLE processos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_codigo text NOT NULL UNIQUE, cnj text, cnj_normalizado text
);
CREATE TABLE cumprimentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_id uuid NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  processo_codigo text NOT NULL UNIQUE, cnj text, cnj_normalizado text
);
CREATE TABLE incidentes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  cumprimento_id uuid REFERENCES cumprimentos(id) ON DELETE CASCADE,
  processo_id uuid NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  processo_codigo text NOT NULL UNIQUE, numero_depre text, cnj text
);
CREATE TABLE partes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id uuid NOT NULL REFERENCES incidentes(id) ON DELETE CASCADE,
  processo_id uuid NOT NULL REFERENCES processos(id) ON DELETE CASCADE,
  papel text NOT NULL, nome text
);
CREATE TABLE andamentos (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  incidente_id uuid NOT NULL REFERENCES incidentes(id) ON DELETE CASCADE,
  hash text NOT NULL, UNIQUE (incidente_id, hash)
);
EOF

psql_ -d sandbox -f "$ROOT/sql/2026-08-19_for143_merge_legado_rpcs.sql"
psql_ -d sandbox -f "$ROOT/sql/2026-09-29_for178_merge_legado_processo_para_cumprimento.sql"
ok "migrations aplicadas (FOR-143 RPCs + FOR-178 RPC nova)"

# Semeia o estado LEGADO do caso real (import FOR-143): processo "fake" com cnj = CUMPRIMENTO,
# incidente LEGADO- sem cumprimento_id + partes + andamento.
seed_legado() {
  psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('11111111-1111-1111-1111-111111111111', 'LEGADO-00165252920228260053', '0016525-29.2022.8.26.0053', '00165252920228260053');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre, cnj) VALUES
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', NULL,
   'LEGADO-00165252920228260053-00001', '0088499-12.2023.8.26.0500', '0016525-29.2022.8.26.0053');
INSERT INTO partes (incidente_id, processo_id, papel, nome) VALUES
  ('22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 'ativa', 'CREDOR LEGADO');
INSERT INTO andamentos (incidente_id, hash) VALUES ('22222222-2222-2222-2222-222222222222', 'h-legado');
EOF
}

# Sequência do worker (persistTree) em SQL, pro caminho raiz=0023830-02.2001, cumprimento=0016525-29.2022.
# Códigos e-SAJ fictícios: raiz 1H0000RAIZ, cumprimento 1H0000CUMP, incidente 1H0000INC1.
simula_worker() {
  psql_ -d sandbox <<'EOF'
DO $$
DECLARE v_proc uuid; v_cump uuid; v_leg uuid; v_real_inc uuid; v_inc uuid;
BEGIN
  -- reconcileLegadoProcesso(raiz): procura LEGADO- pelo cnj da RAIZ — não acha (é o bug original).
  PERFORM 1 FROM processos WHERE cnj_normalizado = '00238300220018260053' AND processo_codigo LIKE 'LEGADO-%';
  IF FOUND THEN RAISE EXCEPTION 'não devia existir legado na raiz'; END IF;

  INSERT INTO processos (processo_codigo, cnj, cnj_normalizado)
       VALUES ('1H0000RAIZ', '0023830-02.2001.8.26.0053', '00238300220018260053')
  ON CONFLICT (processo_codigo) DO UPDATE SET cnj = EXCLUDED.cnj RETURNING id INTO v_proc;

  INSERT INTO cumprimentos (processo_id, processo_codigo, cnj, cnj_normalizado)
       VALUES (v_proc, '1H0000CUMP', '0016525-29.2022.8.26.0053', '00165252920228260053')
  ON CONFLICT (processo_codigo) DO UPDATE SET processo_id = EXCLUDED.processo_id RETURNING id INTO v_cump;

  -- FOR-178: reconcileLegadoCumprimento
  FOR v_leg IN SELECT id FROM processos WHERE cnj_normalizado = '00165252920228260053' AND processo_codigo LIKE 'LEGADO-%' LOOP
    PERFORM merge_legado_processo_para_cumprimento(v_leg, v_proc, v_cump);
  END LOOP;

  -- buscarIncidentesLegadoDoProcesso (recarregado) + reconcileLegadoIncidente
  SELECT id INTO v_real_inc FROM incidentes WHERE processo_codigo = '1H0000INC1';
  FOR v_inc IN SELECT id FROM incidentes WHERE processo_id = v_proc AND processo_codigo LIKE 'LEGADO-%'
                                          AND numero_depre = '0088499-12.2023.8.26.0500' LOOP
    IF v_real_inc IS NOT NULL THEN
      PERFORM merge_legado_incidente(v_inc, v_real_inc);
    ELSE
      UPDATE incidentes SET processo_codigo = '1H0000INC1' WHERE id = v_inc;
    END IF;
  END LOOP;

  -- upsert incidente real
  INSERT INTO incidentes (cumprimento_id, processo_id, processo_codigo, numero_depre, cnj)
       VALUES (v_cump, v_proc, '1H0000INC1', '0088499-12.2023.8.26.0500', '0088499-12.2023.8.26.0500')
  ON CONFLICT (processo_codigo) DO UPDATE
     SET cumprimento_id = EXCLUDED.cumprimento_id, processo_id = EXCLUDED.processo_id,
         numero_depre = EXCLUDED.numero_depre, cnj = EXCLUDED.cnj;
END $$;
EOF
}

confere_final() {
  local cen="$1"
  eq "$(val "select count(*) from incidentes where numero_depre = '0088499-12.2023.8.26.0500'")" "1" "[$cen] exatamente 1 incidente pro numero_depre"
  eq "$(val "select count(*) from incidentes i join cumprimentos c on c.id = i.cumprimento_id join processos p on p.id = i.processo_id
             where i.numero_depre = '0088499-12.2023.8.26.0500' and c.cnj = '0016525-29.2022.8.26.0053'
               and p.cnj = '0023830-02.2001.8.26.0053' and c.processo_id = p.id")" "1" "[$cen] incidente com cumprimento_id e processo_id (raiz real) corretos"
  eq "$(val "select count(*) from processos where processo_codigo like 'LEGADO-%'")" "0" "[$cen] linha processos LEGADO- apagada"
  eq "$(val "select count(*) from incidentes where processo_codigo like 'LEGADO-%'")" "0" "[$cen] nenhum incidente LEGADO- remanescente"
  eq "$(val "select count(*) from processos")" "1" "[$cen] só a raiz real em processos"
}

reset_db() { psql_ -d sandbox -c "TRUNCATE processos, cumprimentos, incidentes, partes, andamentos CASCADE"; }

# ---- A) 1º crawl ------------------------------------------------------------
seed_legado
simula_worker
confere_final A
eq "$(val "select id from incidentes where numero_depre = '0088499-12.2023.8.26.0500'")" "22222222-2222-2222-2222-222222222222" "[A] incidente legado foi COMPLETADO (mesmo id), não recriado"
eq "$(val "select count(*) from partes p join processos r on r.id = p.processo_id where r.cnj = '0023830-02.2001.8.26.0053'")" "1" "[A] partes reapontadas pra raiz real"
eq "$(val "select count(*) from andamentos")" "1" "[A] andamento do legado preservado"

# ---- C) idempotência: 2º crawl + RPC de novo com o id legado já apagado -------
simula_worker
confere_final "A 2º crawl"
psql_ -d sandbox -c "select merge_legado_processo_para_cumprimento('11111111-1111-1111-1111-111111111111',
  (select id from processos where processo_codigo='1H0000RAIZ'), (select id from cumprimentos where processo_codigo='1H0000CUMP'))" >/dev/null
confere_final "C RPC repetida"

# ---- B) hierarquia paralela já existe (crawl pré-fix) + legado órfão ----------
reset_db
psql_ -d sandbox <<'EOF'
INSERT INTO processos (id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('33333333-3333-3333-3333-333333333333', '1H0000RAIZ', '0023830-02.2001.8.26.0053', '00238300220018260053');
INSERT INTO cumprimentos (id, processo_id, processo_codigo, cnj, cnj_normalizado) VALUES
  ('44444444-4444-4444-4444-444444444444', '33333333-3333-3333-3333-333333333333', '1H0000CUMP', '0016525-29.2022.8.26.0053', '00165252920228260053');
INSERT INTO incidentes (id, processo_id, cumprimento_id, processo_codigo, numero_depre) VALUES
  ('55555555-5555-5555-5555-555555555555', '33333333-3333-3333-3333-333333333333', '44444444-4444-4444-4444-444444444444', '1H0000INC1', '0088499-12.2023.8.26.0500');
EOF
seed_legado
eq "$(val "select count(*) from incidentes where numero_depre = '0088499-12.2023.8.26.0500'")" "2" "[B] estado inicial reproduz a duplicata de produção"
simula_worker
confere_final B
eq "$(val "select id from incidentes where numero_depre = '0088499-12.2023.8.26.0500'")" "55555555-5555-5555-5555-555555555555" "[B] sobrevive o incidente REAL (e-SAJ prevalece)"

# ---- D) guardas -------------------------------------------------------------
psql_ -d sandbox -c "select merge_legado_processo_para_cumprimento('33333333-3333-3333-3333-333333333333','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444')" >/dev/null
eq "$(val "select count(*) from processos where id = '33333333-3333-3333-3333-333333333333'")" "1" "[D] legado = real → no-op"
psql_ -d sandbox -c "INSERT INTO processos (id, processo_codigo, cnj) VALUES ('66666666-6666-6666-6666-666666666666', '1H0000OUTRO', 'x')"
psql_ -d sandbox -c "select merge_legado_processo_para_cumprimento('66666666-6666-6666-6666-666666666666','33333333-3333-3333-3333-333333333333','44444444-4444-4444-4444-444444444444')"
eq "$(val "select count(*) from processos where id = '66666666-6666-6666-6666-666666666666'")" "1" "[D] processo NÃO-LEGADO nunca é apagado (no-op)"
seed_legado
if psql_ -d sandbox -c "select merge_legado_processo_para_cumprimento('11111111-1111-1111-1111-111111111111','66666666-6666-6666-6666-666666666666','44444444-4444-4444-4444-444444444444')" 2>"$TMP/err"; then
  falha "[D] cumprimento de outra árvore devia dar erro"
fi
grep -q "não pertence ao processo" "$TMP/err" && ok "[D] cumprimento de outra árvore → exceção" || falha "[D] mensagem inesperada: $(cat "$TMP/err")"
eq "$(val "select count(*) from processos where id = '11111111-1111-1111-1111-111111111111'")" "1" "[D] após exceção a linha legado continua intacta (rollback)"

# ---- E) grants --------------------------------------------------------------
SIG="public.merge_legado_processo_para_cumprimento(uuid, uuid, uuid)"
eq "$(val "select has_function_privilege('anon', '$SIG', 'execute')")" "f" "[E] anon SEM execute"
eq "$(val "select count(*) from pg_proc p, aclexplode(p.proacl) a where p.proname = 'merge_legado_processo_para_cumprimento' and a.grantee = 0")" "0" "[E] PUBLIC SEM execute"
eq "$(val "select has_function_privilege('authenticated', '$SIG', 'execute')")" "t" "[E] authenticated COM execute"
eq "$(val "select has_function_privilege('service_role', '$SIG', 'execute')")" "t" "[E] service_role COM execute"
eq "$(val "select prosecdef from pg_proc where proname = 'merge_legado_processo_para_cumprimento'")" "t" "[E] security definer"

echo
echo "FOR-178 sandbox: TODOS OS CENÁRIOS OK"
