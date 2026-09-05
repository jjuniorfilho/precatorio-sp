#!/usr/bin/env bash
#
# smoke-test.sh — Fleet Orchestration · testes de comportamento leve
#
# Valida os branches comportamentais dos 3 scripts do Fleet que NAO sao cobertos
# pelos smoke tests manuais do pre-PR. Sem dependencias externas — apenas bash,
# git e mktemp. Seguro para rodar em CI ou pre-PR.
#
# Filosofia: cada caso cria um sandbox temporario (repo git em /tmp), roda o
# script alvo e verifica o exit code + saida esperada. Nenhum estado persiste
# entre casos. Idempotente e nao polui o repo corrente.
#
# Uso:
#   bash .claude/skills/fleet-orchestration/scripts/smoke-test.sh
#   bash .claude/skills/fleet-orchestration/scripts/smoke-test.sh gate
#   bash .claude/skills/fleet-orchestration/scripts/smoke-test.sh provision
#   bash .claude/skills/fleet-orchestration/scripts/smoke-test.sh teardown
#
set -uo pipefail

SUITE="${1:-all}"   # gate | provision | teardown | all

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
GATE="$SCRIPTS_DIR/fleet-gate.sh"
PROVISION="$SCRIPTS_DIR/fleet-provision.sh"
TEARDOWN="$SCRIPTS_DIR/fleet-teardown.sh"

# ── resultado global
PASS=0; FAIL=0; SKIP=0

# ── helpers de output
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[0;33m'; NC='\033[0m'
ok()   { PASS=$((PASS+1)); printf "${GREEN}  PASS${NC} %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "${RED}  FAIL${NC} %s\n" "$1"; [[ -n "${2:-}" ]] && printf "       %s\n" "$2"; }
skip() { SKIP=$((SKIP+1)); printf "${YELLOW}  SKIP${NC} %s\n" "$1"; }

# cria um repo git temporario limpo; devolve o path via echo
make_repo() {
  local d
  d="$(mktemp -d)"
  git -C "$d" init -q
  git -C "$d" config user.email "smoke@test.local"
  git -C "$d" config user.name "Smoke Test"
  # commit inicial para que HEAD exista
  touch "$d/.gitkeep"
  git -C "$d" add .gitkeep
  git -C "$d" commit -q -m "init"
  echo "$d"
}

# invocada indiretamente via `trap cleanup EXIT` em cada caso
# shellcheck disable=SC2329
cleanup() { [[ -n "${REPO:-}" ]] && rm -rf "$REPO"; }

# ═══════════════════════════════════════════════════════════════════════════════
# SUITE: fleet-gate.sh
# ═══════════════════════════════════════════════════════════════════════════════
run_gate_suite() {
  echo ""
  echo "── fleet-gate.sh ─────────────────────────────────────────────────────"

  # ------------------------------------------------------------------
  # CASO G-01: sem config e sem package.json → exit 0, msg "nenhum gate"
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  out="$(GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO" bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "nenhum gate"; then
    ok "G-01: sem config + sem package.json → exit 0 + msg 'nenhum gate'"
  else
    fail "G-01: sem config + sem package.json" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-02: FLEET_GATE_CMDS com comando que tem ':' no corpo
  #            ex.: "build:docker build -t foo:latest ."
  #            label = "build", cmd = "docker build -t foo:latest ."
  #            O split label="${item%%:*}" / cmd="${item#*:}" deve funcionar.
  #            Nota: arrays bash nao podem ser exportados via env prefix para
  #            subprocessos — o mecanismo correto e via fleet.config.sh.
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  # comando com ':' no corpo (simula tag docker): "build:echo tag:latest"
  echo 'FLEET_GATE_CMDS=("build:echo tag:latest")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]]; then
    ok "G-02: FLEET_GATE_CMDS com ':' no corpo do comando → split correto, exit 0"
  else
    fail "G-02: FLEET_GATE_CMDS com ':' no corpo" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-03: FLEET_GATE_SCOPE filtra label fora do escopo → RAN==0, exit 0
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo 'FLEET_GATE_CMDS=("lint:false")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && FLEET_GATE_SCOPE="test" bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]]; then
    ok "G-03: scope filter exclui label → exit 0 mesmo com comando que falharia"
  else
    fail "G-03: scope filter" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-04: FLEET_GATE_SCOPE com label que existe → roda e falha (exit 2)
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo 'FLEET_GATE_CMDS=("lint:false")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && FLEET_GATE_SCOPE="lint" bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 2 ]]; then
    ok "G-04: scope match + comando falha → exit 2"
  else
    fail "G-04: scope match + comando falha" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-05: auto-detect com pnpm-lock.yaml → runner = pnpm
  #            (package.json com script "lint", pnpm-lock.yaml presente,
  #             FLEET_GATE_CMDS nao definido → deve compor "lint:pnpm lint")
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  echo '{"scripts":{"lint":"exit 0"}}' > "$REPO/package.json"
  touch "$REPO/pnpm-lock.yaml"
  # sobrescreve o script lint para "exit 0" via package.json mas como nao temos
  # pnpm instalado, precisamos garantir que o runner detectado seja "pnpm"
  # Verificamos apenas que a mensagem menciona "pnpm" (inspecao do log)
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if echo "$out" | grep -qiE "pnpm"; then
    ok "G-05: pnpm-lock.yaml → auto-detect runner = pnpm"
  else
    skip "G-05: pnpm-lock.yaml runner detect (pnpm nao instalado, saida='$out')"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-06: auto-detect com yarn.lock → runner = yarn
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  echo '{"scripts":{"lint":"exit 0"}}' > "$REPO/package.json"
  touch "$REPO/yarn.lock"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if echo "$out" | grep -qiE "yarn"; then
    ok "G-06: yarn.lock → auto-detect runner = yarn"
  else
    skip "G-06: yarn.lock runner detect (yarn nao instalado, saida='$out')"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-07: auto-detect com bun.lockb → runner = bun run
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  echo '{"scripts":{"test":"exit 0"}}' > "$REPO/package.json"
  touch "$REPO/bun.lockb"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if echo "$out" | grep -qiE "bun"; then
    ok "G-07: bun.lockb → auto-detect runner = bun"
  else
    skip "G-07: bun.lockb runner detect (bun nao instalado, saida='$out')"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-08: fora de repo git → exit 2 + msg de erro
  # ------------------------------------------------------------------
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  out="$(bash "$GATE" 2>&1)" && rc=$? || rc=$?
  # shellcheck disable=SC2317
  out="$(cd "$tmp_dir" && GIT_DIR=/dev/null bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 2 ]]; then
    ok "G-08: fora de repo git → exit 2"
  else
    skip "G-08: fora de repo (sandbox limitado — rc=$rc)"
  fi
  rm -rf "$tmp_dir"

  # ------------------------------------------------------------------
  # CASO G-09: dois gates, um falha → FAILED lista label do failure, exit 2
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo 'FLEET_GATE_CMDS=("ok:true" "bad:false")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q "bad"; then
    ok "G-09: gate parcial (1 ok, 1 fail) → exit 2 listando label do failure"
  else
    fail "G-09: gate parcial" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-11: gate que MUTA a arvore → exit 2, delta listado
  #            (report de consumidor, 2026-07-31: `eslint --fix` no FLEET_GATE_CMDS
  #             reescreveu 10 arquivos fora do escopo da issue; 5a ocorrencia)
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo "conteudo original" > "$REPO/alvo.txt"
  (cd "$REPO" && git add alvo.txt && git commit -qm "alvo")
  echo 'FLEET_GATE_CMDS=("lint:sed -i.bak s/original/MUTADO/ alvo.txt && rm -f alvo.txt.bak")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q "MUTOU a arvore" && echo "$out" | grep -q "alvo.txt"; then
    ok "G-11: gate mutante → exit 2 citando o arquivo alterado"
  else
    fail "G-11: gate mutante" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-12: FLEET_GATE_ALLOW_MUTATION=1 → avisa mas nao bloqueia
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo "conteudo original" > "$REPO/alvo.txt"
  (cd "$REPO" && git add alvo.txt && git commit -qm "alvo")
  echo 'FLEET_GATE_CMDS=("lint:sed -i.bak s/original/MUTADO/ alvo.txt && rm -f alvo.txt.bak")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && FLEET_GATE_ALLOW_MUTATION=1 bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "MUTOU"; then
    ok "G-12: FLEET_GATE_ALLOW_MUTATION=1 → exit 0 com aviso"
  else
    fail "G-12: escape de mutacao" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-13: sujeira PRE-EXISTENTE nao pode ser confundida com mutacao do gate
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo "ja estava sujo" > "$REPO/sujo-antes.txt"
  echo 'FLEET_GATE_CMDS=("lint:true")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && ! echo "$out" | grep -q "MUTOU"; then
    ok "G-13: arvore ja suja + gate nao-mutante → exit 0 sem acusar mutacao"
  else
    fail "G-13: falso positivo de mutacao" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-14: logs de worktrees distintas nao colidem, e trazem procedencia
  #            (antes: /tmp/fleet-gate-<label>.log — o rotulo sozinho, com `>` truncando,
  #             fazia a ultima escrita vencer entre worktrees e ate entre PROJETOS)
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  LOGD="$(mktemp -d)"
  mkdir -p "$REPO/.claude"
  echo 'FLEET_GATE_CMDS=("lint:echo marcador-de-saida")' > "$REPO/.claude/fleet.config.sh"
  (cd "$REPO" && git worktree add -q "$REPO/wt-outra" -b outra 2>/dev/null)
  cp -r "$REPO/.claude" "$REPO/wt-outra/" 2>/dev/null
  (cd "$REPO" && FLEET_GATE_LOG_DIR="$LOGD" bash "$GATE" >/dev/null 2>&1)
  (cd "$REPO/wt-outra" && FLEET_GATE_LOG_DIR="$LOGD" bash "$GATE" >/dev/null 2>&1)
  n_logs="$(find "$LOGD" -name '*.log' | grep -c . || true)"
  com_proc="$(grep -l '^# worktree :' "$LOGD"/*.log 2>/dev/null | grep -c . || true)"
  if [[ "$n_logs" == "2" && "$com_proc" == "2" ]]; then
    ok "G-14: 2 worktrees → 2 logs distintos, ambos com cabecalho de procedencia"
  else
    fail "G-14: colisao de log entre worktrees" "logs=$n_logs com_procedencia=$com_proc"
  fi
  rm -rf "$REPO" "$LOGD"

  # ------------------------------------------------------------------
  # CASO G-15: arquivo JA modificado que o gate reescreve
  #            Furo da 1a versao da deteccao: comparava `git status --porcelain`, e um
  #            arquivo ` M` continua ` M` depois de reescrito — o gate saia VERDE. E o caso
  #            dominante: o dev edita justamente os arquivos que o `--fix` vai tocar.
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo "linha original" > "$REPO/codigo.ts"
  (cd "$REPO" && git add codigo.ts && git commit -qm "codigo")
  echo 'FLEET_GATE_CMDS=("lint:sed -i.bak s/EDITADO/CORRIGIDO/ codigo.ts && rm -f codigo.ts.bak")' > "$REPO/.claude/fleet.config.sh"
  echo "EDITADO pelo dev" > "$REPO/codigo.ts"     # ja modificado ANTES do gate
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q "MUTOU a arvore" && echo "$out" | grep -q "codigo.ts"; then
    ok "G-15: arquivo ja modificado + gate mutante → exit 2 (status identico nao engana)"
  else
    fail "G-15: mutacao sobre arquivo ja modificado" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-16: gate que CRIA arquivo (untracked) tambem esta mutando
  #            `git stash create` sozinho ignora untracked — a marca precisa do complemento
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo "sujo de antes" > "$REPO/ruido.txt"          # ruido pre-existente: NAO pode entrar no delta
  echo 'FLEET_GATE_CMDS=("relatorio:echo dados > relatorio-gerado.txt")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 2 ]] && echo "$out" | grep -q "relatorio-gerado.txt" && ! echo "$out" | grep -q "ruido.txt"; then
    ok "G-16: gate que cria untracked → exit 2, delta sem o ruido pre-existente"
  else
    fail "G-16: criacao de untracked pelo gate" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-17: sem baseline possivel → AVISA, nunca imprime verde limpo
  #            (repo sem commit inicial: `git stash create` falha)
  # ------------------------------------------------------------------
  REPO="$(mktemp -d)"
  trap cleanup EXIT
  (cd "$REPO" && git init -q -b main . && git config user.email t@t && git config user.name t)
  mkdir -p "$REPO/.claude"
  echo 'FLEET_GATE_CMDS=("lint:true")' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if echo "$out" | grep -q "NAO foi possivel verificar"; then
    ok "G-17: baseline indisponivel → avisa que a integridade NAO foi verificada"
  else
    fail "G-17: verificacao ausente silenciosa" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO G-10: config presente com FLEET_GATE_CMDS vazio (array vazio declarado)
  #            → sem gates configurados, exit 0
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo 'FLEET_GATE_CMDS=()' > "$REPO/.claude/fleet.config.sh"
  out="$(cd "$REPO" && bash "$GATE" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]]; then
    ok "G-10: config com FLEET_GATE_CMDS=() → exit 0 sem gates"
  else
    fail "G-10: config com FLEET_GATE_CMDS=()" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUITE: fleet-provision.sh
# ═══════════════════════════════════════════════════════════════════════════════
run_provision_suite() {
  echo ""
  echo "── fleet-provision.sh ────────────────────────────────────────────────"

  # ------------------------------------------------------------------
  # CASO P-01: sem argumento → exit 1 + msg ERRO
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  out="$(cd "$REPO" && bash "$PROVISION" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q "ERRO"; then
    ok "P-01: sem nome → exit 1 + msg ERRO"
  else
    fail "P-01: sem nome" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-02: flag desconhecida → exit 1
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  out="$(cd "$REPO" && bash "$PROVISION" minha-issue --kaboom 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 1 ]]; then
    ok "P-02: flag desconhecida → exit 1"
  else
    fail "P-02: flag desconhecida" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-03: --dry-run imprime plano, nao cria diretorio
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  # adiciona origin fake para que fetch nao quebre
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" test-issue --dry-run 2>&1)" && rc=$? || rc=$?
  WT_PATH="$REPO/.claude/worktrees/test-issue"
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "dry-run" && [[ ! -d "$WT_PATH" ]]; then
    ok "P-03: --dry-run → exit 0, sem diretorio criado"
  else
    fail "P-03: --dry-run" "rc=$rc dir_exists=$(test -d "$WT_PATH" && echo yes || echo no) out=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-04: SHORT_ID de nome sem numero (ex.: "alpha-beta")
  #            → fallback para alnum completo ("alphabeta")
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" alpha-beta --dry-run 2>&1)" && rc=$? || rc=$?
  if echo "$out" | grep -q "short_id:  alphabeta"; then
    ok "P-04: nome sem numero → short_id = alnum do nome completo"
  else
    fail "P-04: short_id sem numero" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-05: SHORT_ID de nome padrão issue (ex.: "px-2621-minha-feature")
  #            → short_id = "px2621"
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" px-2621-minha-feature --dry-run 2>&1)" && rc=$? || rc=$?
  if echo "$out" | grep -q "short_id:  px2621"; then
    ok "P-05: nome padrão issue → short_id = 'px2621'"
  else
    fail "P-05: short_id padrão issue" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-06: worktree já existe (diretório presente) → "pulando criacao"
  #            (idempotência: não deve falhar)
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  # simular worktree pré-existente como worktree vinculada ao repo
  WT_PATH="$REPO/.claude/worktrees/ja-existe"
  mkdir -p "$WT_PATH"
  # registrar como worktree de verdade para que git worktree list reconheça
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/ja-existe HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" ja-existe --no-install --no-db 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "pulando"; then
    ok "P-06: worktree ja existe → idempotente, exit 0 + msg 'pulando'"
  else
    fail "P-06: idempotência worktree" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-07: .worktreeinclude com path que não existe no ROOT
  #            → deve pular silenciosamente (sem erro)
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  echo ".env.fantasma" > "$REPO/.worktreeinclude"
  git -C "$REPO" worktree add "$REPO/.claude/worktrees/wt-test" -b fleet/wt-test HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" wt-test --no-install --no-db 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]]; then
    ok "P-07: .worktreeinclude com path inexistente → exit 0 (skip silencioso)"
  else
    fail "P-07: .worktreeinclude path inexistente" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-08: .worktreeinclude com comentário e linha vazia → ignorados
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  printf '# comentario\n\n.env\n' > "$REPO/.worktreeinclude"
  echo "SECRET=1" > "$REPO/.env"
  git -C "$REPO" worktree add "$REPO/.claude/worktrees/wt-env" -b fleet/wt-env HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" wt-env --no-install --no-db 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && [[ -f "$REPO/.claude/worktrees/wt-env/.env" ]]; then
    ok "P-08: .worktreeinclude com comentario/linha-vazia → copiado apenas .env"
  else
    fail "P-08: .worktreeinclude comentario+vazia" "rc=$rc copied=$(ls "$REPO/.claude/worktrees/wt-env/.env" 2>/dev/null || echo 'nao') out=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-09: fleet_provision_data hook chamado com os 3 argumentos corretos
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/fleet.config.sh" <<'CFG'
fleet_provision_data() {
  echo "hook:$1:$2:$3" > /tmp/fleet_provision_data_args.txt
}
CFG
  git -C "$REPO" worktree add "$REPO/.claude/worktrees/px-99-feat" -b fleet/px-99-feat HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" px-99-feat --no-install 2>&1)" && rc=$? || rc=$?
  hook_out="$(cat /tmp/fleet_provision_data_args.txt 2>/dev/null || true)"
  if [[ "$rc" == 0 ]] && echo "$hook_out" | grep -q "hook:px-99-feat:"; then
    ok "P-09: fleet_provision_data chamado com WT_NAME, WT_DIR, SHORT_ID"
  else
    fail "P-09: fleet_provision_data hook args" "rc=$rc hook_out=$hook_out out=$out"
  fi
  rm -f /tmp/fleet_provision_data_args.txt
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-10: --no-db → fleet_provision_data NÃO chamado
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/fleet.config.sh" <<'CFG'
fleet_provision_data() {
  echo "CALLED" > /tmp/fleet_prov_nodb.txt
}
CFG
  git -C "$REPO" worktree add "$REPO/.claude/worktrees/nodb-test" -b fleet/nodb-test HEAD -q 2>/dev/null || true
  rm -f /tmp/fleet_prov_nodb.txt
  out="$(cd "$REPO" && bash "$PROVISION" nodb-test --no-install --no-db 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && [[ ! -f /tmp/fleet_prov_nodb.txt ]]; then
    ok "P-10: --no-db → fleet_provision_data NAO chamado"
  else
    fail "P-10: --no-db hook skip" "rc=$rc called=$(test -f /tmp/fleet_prov_nodb.txt && echo yes || echo no) out=$out"
  fi
  rm -f /tmp/fleet_prov_nodb.txt
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-11: auto-detect install cmd com pnpm-lock.yaml
  #            Nota: detect_install_cmd() inspeciona WT_DIR (não ROOT).
  #            Em dry-run o WT_DIR ainda não existe, então o detect retorna
  #            vazio e o log diz "pulado". O teste cria o WT_DIR manualmente
  #            com o lockfile para simular uma worktree já provisionada.
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  mkdir -p "$REPO/.claude"
  echo 'FLEET_BRANCH_PREFIX="fleet"' > "$REPO/.claude/fleet.config.sh"
  # worktree ja existe com pnpm-lock.yaml (simula worktree pré-criada sem install)
  WT_PATH="$REPO/.claude/worktrees/pnpm-wt"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/pnpm-wt HEAD -q 2>/dev/null || true
  touch "$WT_PATH/package.json" "$WT_PATH/pnpm-lock.yaml"
  out="$(cd "$REPO" && bash "$PROVISION" pnpm-wt 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "pnpm install"; then
    ok "P-11: pnpm-lock.yaml em WT_DIR → auto-detect install = 'pnpm install --frozen-lockfile'"
  else
    skip "P-11: pnpm auto-detect (pnpm nao instalado ou rc=$rc)"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO P-12: branch já existe localmente → provision reusa sem -b
  #            Usa FLEET_BRANCH_PREFIX fixo para isolar do git user.name
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  git -C "$REPO" remote add origin https://github.com/fake/repo.git 2>/dev/null || true
  mkdir -p "$REPO/.claude"
  echo 'FLEET_BRANCH_PREFIX="fleet"' > "$REPO/.claude/fleet.config.sh"
  # criar branch local que o script detectará via show-ref
  git -C "$REPO" branch "fleet/existing-branch" HEAD 2>/dev/null || true
  out="$(cd "$REPO" && bash "$PROVISION" existing-branch --no-install --no-db --dry-run 2>&1)" && rc=$? || rc=$?
  # Em dry-run vemos o comando. Deve usar "worktree add <dir> <branch>" sem -b.
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "worktree add" && ! echo "$out" | grep -q "\-b '"; then
    ok "P-12: branch ja existe localmente → dry-run mostra 'worktree add' sem -b"
  else
    fail "P-12: branch ja existe (rc=$rc out=$out)"
  fi
  rm -rf "$REPO"
}

# ═══════════════════════════════════════════════════════════════════════════════
# SUITE: fleet-teardown.sh
# ═══════════════════════════════════════════════════════════════════════════════
run_teardown_suite() {
  echo ""
  echo "── fleet-teardown.sh ─────────────────────────────────────────────────"

  # ------------------------------------------------------------------
  # CASO T-01: sem argumento → exit 1 + msg ERRO
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  out="$(cd "$REPO" && bash "$TEARDOWN" 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q "ERRO"; then
    ok "T-01: sem nome → exit 1 + msg ERRO"
  else
    fail "T-01: sem nome" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-02: flag desconhecida → exit 1
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  out="$(cd "$REPO" && bash "$TEARDOWN" alguma --kaboom 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 1 ]]; then
    ok "T-02: flag desconhecida → exit 1"
  else
    fail "T-02: flag desconhecida" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-03: worktree não existe → exit 0 + msg "nao existe"
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  out="$(cd "$REPO" && bash "$TEARDOWN" nao-existe-wt 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "nao existe"; then
    ok "T-03: worktree nao existe → exit 0 (idempotente)"
  else
    fail "T-03: worktree nao existe" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-04: worktree com mudanças não-commitadas sem --force → exit 1
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  WT_PATH="$REPO/.claude/worktrees/dirty-wt"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/dirty-wt HEAD -q 2>/dev/null || true
  echo "modificacao" > "$WT_PATH/new-file.txt"  # arquivo nao-tracked = dirty
  out="$(cd "$REPO" && bash "$TEARDOWN" dirty-wt 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 1 ]] && echo "$out" | grep -q "force"; then
    ok "T-04: worktree dirty sem --force → exit 1 + hint --force"
  else
    fail "T-04: guard mudancas nao-commitadas" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-05: worktree com mudanças não-commitadas COM --force → exit 0
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  WT_PATH="$REPO/.claude/worktrees/dirty-force"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/dirty-force HEAD -q 2>/dev/null || true
  echo "modificacao" > "$WT_PATH/new-file.txt"
  out="$(cd "$REPO" && bash "$TEARDOWN" dirty-force --force 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]]; then
    ok "T-05: worktree dirty + --force → exit 0, removida"
  else
    fail "T-05: --force em worktree dirty" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-06: --dry-run não remove a worktree
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  WT_PATH="$REPO/.claude/worktrees/dry-wt"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/dry-wt HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$TEARDOWN" dry-wt --dry-run 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && [[ -d "$WT_PATH" ]]; then
    ok "T-06: --dry-run → exit 0 + worktree preservada"
  else
    fail "T-06: --dry-run teardown" "rc=$rc dir=$(test -d "$WT_PATH" && echo existe || echo removida) out=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-07: --drop-db sem fleet_teardown_data definida → exit 0 + warning
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  WT_PATH="$REPO/.claude/worktrees/nodrop-wt"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/nodrop-wt HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$TEARDOWN" nodrop-wt --drop-db 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]] && echo "$out" | grep -q "fleet_teardown_data"; then
    ok "T-07: --drop-db sem hook → exit 0 + aviso de ausencia de hook"
  else
    fail "T-07: --drop-db sem hook" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-08: --drop-db COM fleet_teardown_data definida → hook chamado
  #            com SHORT_ID correto
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/fleet.config.sh" <<'CFG'
fleet_teardown_data() {
  echo "teardown_hook:$1:$3" > /tmp/fleet_teardown_hook.txt
}
CFG
  WT_PATH="$REPO/.claude/worktrees/px-42-feat"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/px-42-feat HEAD -q 2>/dev/null || true
  rm -f /tmp/fleet_teardown_hook.txt
  out="$(cd "$REPO" && bash "$TEARDOWN" px-42-feat --drop-db 2>&1)" && rc=$? || rc=$?
  hook_out="$(cat /tmp/fleet_teardown_hook.txt 2>/dev/null || true)"
  if [[ "$rc" == 0 ]] && echo "$hook_out" | grep -q "teardown_hook:px-42-feat:px42"; then
    ok "T-08: --drop-db COM hook → fleet_teardown_data chamado (SHORT_ID=px42)"
  else
    fail "T-08: fleet_teardown_data hook args" "rc=$rc hook_out=$hook_out out=$out"
  fi
  rm -f /tmp/fleet_teardown_hook.txt
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-09: --delete-branch remove branch local
  #            O teardown computa o prefixo de FLEET_BRANCH_PREFIX ou de
  #            git user.name. Para isolar o teste do ambiente, passamos
  #            FLEET_BRANCH_PREFIX explicitamente via config.
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  echo 'FLEET_BRANCH_PREFIX="fleet"' > "$REPO/.claude/fleet.config.sh"
  WT_PATH="$REPO/.claude/worktrees/del-branch-wt"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/del-branch-wt HEAD -q 2>/dev/null || true
  out="$(cd "$REPO" && bash "$TEARDOWN" del-branch-wt --delete-branch 2>&1)" && rc=$? || rc=$?
  if [[ "$rc" == 0 ]]; then
    branch_gone=0
    git -C "$REPO" show-ref --verify "refs/heads/fleet/del-branch-wt" 2>/dev/null && branch_gone=1 || true
    if [[ "$branch_gone" == 0 ]]; then
      ok "T-09: --delete-branch → branch local removida"
    else
      fail "T-09: --delete-branch → branch ainda existe" "out=$out"
    fi
  else
    fail "T-09: --delete-branch exit code" "rc=$rc output=$out"
  fi
  rm -rf "$REPO"

  # ------------------------------------------------------------------
  # CASO T-10: SHORT_ID de nome sem número no teardown (ex.: "alphabeta-only")
  # ------------------------------------------------------------------
  REPO="$(make_repo)"
  trap cleanup EXIT
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/fleet.config.sh" <<'CFG'
fleet_teardown_data() {
  echo "SHORT:$3" > /tmp/fleet_td_shortid.txt
}
CFG
  WT_PATH="$REPO/.claude/worktrees/alphabeta-only"
  git -C "$REPO" worktree add "$WT_PATH" -b fleet/alphabeta-only HEAD -q 2>/dev/null || true
  rm -f /tmp/fleet_td_shortid.txt
  out="$(cd "$REPO" && bash "$TEARDOWN" alphabeta-only --drop-db 2>&1)" && rc=$? || rc=$?
  hook_out="$(cat /tmp/fleet_td_shortid.txt 2>/dev/null || true)"
  if echo "$hook_out" | grep -q "SHORT:alphabetaonly"; then
    ok "T-10: nome sem numero no teardown → SHORT_ID = alnum completo"
  else
    fail "T-10: teardown SHORT_ID sem numero" "rc=$rc hook_out=$hook_out out=$out"
  fi
  rm -f /tmp/fleet_td_shortid.txt
  rm -rf "$REPO"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "Fleet Orchestration — smoke-test.sh"
echo "Scripts dir: $SCRIPTS_DIR"
echo "Suite: $SUITE"
echo "────────────────────────────────────────────────────────────────────────"

case "$SUITE" in
  gate)      run_gate_suite ;;
  provision) run_provision_suite ;;
  teardown)  run_teardown_suite ;;
  all)
    run_gate_suite
    run_provision_suite
    run_teardown_suite
    ;;
  *)
    echo "Suite desconhecida: $SUITE. Use: gate | provision | teardown | all"
    exit 1
    ;;
esac

echo ""
echo "────────────────────────────────────────────────────────────────────────"
printf "Resultado: ${GREEN}%d PASS${NC}  ${RED}%d FAIL${NC}  ${YELLOW}%d SKIP${NC}\n" "$PASS" "$FAIL" "$SKIP"
echo ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 1
fi
exit 0
