#!/usr/bin/env bash
#
# fleet-provision.sh — Cortex Fleet · Fase 0 (Provisionamento)
#
# Provisiona UMA worktree isolada para uma issue, pronta para o workflow de engenharia
# do Cortex (warm-up -> start -> plan -> work -> pre-pr -> pr). Idempotente.
#
# Stack-agnostico: o que e especifico do projeto (deps, dados isolados) vem da config
# layer opcional .claude/fleet.config.sh. Ver:
#   .claude/skills/fleet-orchestration/reference/configuration.md
#
# O que faz, por worktree:
#   1. git worktree add em $FLEET_WORKTREE_DIR/<name> (cria branch se nao existir)
#   2. copia arquivos gitignored listados em .worktreeinclude (se existir)
#   3. escreve .env.fleet (API_PORT, se informado)
#   4. instala deps: FLEET_INSTALL_CMD ou auto-detect (pnpm/yarn/bun/npm)
#   5. chama fleet_provision_data() do projeto, se definida (ex.: DB isolado)
#
# Uso:
#   fleet-provision.sh <worktree-name> [--api-port N] [--branch B]
#                      [--no-db] [--no-install] [--dry-run]
# Ex.:
#   fleet-provision.sh px-2621-llm-factory --api-port 3011
#
set -euo pipefail

# ---- args ----------------------------------------------------------------
WT_NAME="${1:-}"
[[ -z "$WT_NAME" ]] && { echo "ERRO: informe o nome da worktree (ex.: px-2621-llm-factory)"; exit 1; }
# nome seguro: evita quebra de quoting/injection no eval e paths inesperados
[[ "$WT_NAME" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "ERRO: nome de worktree invalido — use apenas [A-Za-z0-9._/-]"; exit 1; }
shift || true

API_PORT=""
BRANCH=""
DO_DB=1
DO_INSTALL=1
DRY_RUN=0
need_val() { [[ $# -ge 2 ]] || { echo "ERRO: $1 requer um valor"; exit 1; }; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-port) need_val "$@"; API_PORT="$2"; shift 2;;
    --branch)   need_val "$@"; BRANCH="$2"; shift 2;;
    --no-db)    DO_DB=0; shift;;
    --no-install) DO_INSTALL=0; shift;;
    --dry-run)  DRY_RUN=1; shift;;
    *) echo "flag desconhecida: $1"; exit 1;;
  esac
done

# ---- config layer (opcional) ---------------------------------------------
ROOT="$(git rev-parse --show-toplevel)"

# Resolvido a partir de SCRIPT_DIR mesmo sem haver `cd` antes neste script. Os
# outros tres ja fazem assim depois do bug da v3.10.1: calcular inline funciona
# aqui por acidente — basta alguem inserir um `cd` acima para o mesmo defeito
# ressuscitar so neste arquivo, e de novo em silencio, porque o provision continua
# funcionando sem telemetria. Trava em um dos quatro nao e trava.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_EMIT_LIB="$SCRIPT_DIR/_emit.sh"
if [[ -f "$_EMIT_LIB" ]]; then
  # shellcheck source=/dev/null
  source "$_EMIT_LIB"
else
  # Fail-open, mas NUNCA silencioso. Sem este arquivo a telemetria de PROCESSO da
  # frota desaparece — e desaparece justamente na worktree, que nasce do git: um
  # _emit.sh nao-commitado nunca chega la. E a mesma armadilha do #42, em que o
  # hook da #39 chegou inerte nos consumidores. O que falta em silencio nao e
  # investigado, entao aqui o silencio custa mais que o ruido.
  echo "fleet: _emit.sh ausente em $_EMIT_LIB — telemetria de processo DESLIGADA." >&2
  echo "fleet: se ele existe no checkout principal, precisa ser COMMITADO para chegar na worktree." >&2
  fleet_emit() { :; }
fi
CONFIG="$ROOT/.claude/fleet.config.sh"
# shellcheck source=/dev/null
[[ -f "$CONFIG" ]] && source "$CONFIG"

BASE_REF="${FLEET_BASE_REF:-origin/main}"
WT_BASE_DIR="${FLEET_WORKTREE_DIR:-.claude/worktrees}"
WT_DIR="$ROOT/$WT_BASE_DIR/$WT_NAME"

# prefixo de branch: config > git user.name (slug) > "fleet"
default_prefix() {
  local n; n="$(git config user.name 2>/dev/null || true)"
  n="$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-*//;s/-*$//')"
  printf '%s' "${n:-fleet}"
}
PREFIX="${FLEET_BRANCH_PREFIX:-$(default_prefix)}"
BRANCH="${BRANCH:-$PREFIX/$WT_NAME}"

# id curto (ex.: px-2621-... -> px2621) para hooks do projeto
SHORT_ID="$(printf '%s' "$WT_NAME" | grep -oE '[a-zA-Z]+-?[0-9]+' | head -1 | tr -d '-' || true)"
[[ -z "$SHORT_ID" ]] && SHORT_ID="$(printf '%s' "$WT_NAME" | tr -cd '[:alnum:]')"

say() { printf "  %s\n" "$*"; }
run() { if [[ "$DRY_RUN" == 1 ]]; then echo "    [dry-run] $*"; else eval "$*"; fi; }

# detecta package manager pelo lockfile no diretorio dado
detect_install_cmd() {
  local d="$1"
  if [[ -f "$d/pnpm-lock.yaml" ]]; then echo "pnpm install --frozen-lockfile";
  elif [[ -f "$d/yarn.lock" ]]; then echo "yarn install --frozen-lockfile";
  elif [[ -f "$d/bun.lockb" ]]; then echo "bun install";
  elif [[ -f "$d/package-lock.json" ]]; then echo "npm ci";
  elif [[ -f "$d/package.json" ]]; then echo "npm install";
  else echo ""; fi
}

echo "> Provisionando worktree: $WT_NAME"
say "branch:    $BRANCH (base $BASE_REF)"
say "dir:       $WT_DIR"
say "short_id:  $SHORT_ID"
say "api_port:  ${API_PORT:-<nao definido>}"
if [[ -f "$CONFIG" ]]; then say "config:    $CONFIG"; else say "config:    (nenhum — usando defaults)"; fi
[[ "$DRY_RUN" == 1 ]] && say "MODO DRY-RUN (nada sera executado)"

# ---- 1. worktree ----------------------------------------------------------
run "git -C '$ROOT' fetch origin --quiet || true"
if [[ -d "$WT_DIR" ]]; then
  say "worktree ja existe — pulando criacao"
else
  if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" \
     || git -C "$ROOT" show-ref --verify --quiet "refs/remotes/origin/$BRANCH"; then
    run "git -C '$ROOT' worktree add '$WT_DIR' '$BRANCH'"
  else
    run "git -C '$ROOT' worktree add '$WT_DIR' -b '$BRANCH' '$BASE_REF'"
  fi
fi

# ---- 2. copiar arquivos gitignored (.worktreeinclude) ---------------------
if [[ -f "$ROOT/.worktreeinclude" ]]; then
  while IFS= read -r pattern; do
    [[ -z "$pattern" || "$pattern" == \#* ]] && continue
    if [[ -f "$ROOT/$pattern" ]]; then
      run "mkdir -p '$WT_DIR/$(dirname "$pattern")'"
      run "cp '$ROOT/$pattern' '$WT_DIR/$pattern'"
      say "copiado: $pattern"
    fi
  done < "$ROOT/.worktreeinclude"
fi

# ---- 3. .env.fleet --------------------------------------------------------
if [[ -n "$API_PORT" && "$DRY_RUN" == 0 ]]; then
  {
    echo "# gerado por fleet-provision.sh — nao versionar"
    echo "API_PORT=$API_PORT"
  } > "$WT_DIR/.env.fleet"
  say "escrito: .env.fleet (API_PORT=$API_PORT)"
fi

# ---- 4. deps --------------------------------------------------------------
if [[ "$DO_INSTALL" == 1 ]]; then
  INSTALL_CMD="${FLEET_INSTALL_CMD:-$(detect_install_cmd "$WT_DIR")}"
  if [[ -n "$INSTALL_CMD" ]]; then
    say "install: $INSTALL_CMD"
    run "(cd '$WT_DIR' && $INSTALL_CMD)"
  else
    say "install pulado (sem package.json / sem FLEET_INSTALL_CMD)"
  fi
else
  say "install pulado (--no-install)"
fi

# ---- 5. dados isolados (hook do projeto) ----------------------------------
if [[ "$DO_DB" == 1 ]]; then
  if declare -F fleet_provision_data >/dev/null; then
    say "fleet_provision_data($WT_NAME, $WT_DIR, $SHORT_ID)"
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "    [dry-run] fleet_provision_data '$WT_NAME' '$WT_DIR' '$SHORT_ID'"
    else
      fleet_provision_data "$WT_NAME" "$WT_DIR" "$SHORT_ID"
    fi
  else
    say "sem fleet_provision_data definida — pulando dados isolados"
  fi
else
  say "dados isolados pulados (--no-db)"
fi

fleet_emit fleet.provision --outcome pass --task "${SHORT_ID:-$WT_NAME}"
echo "✔ Worktree '$WT_NAME' pronta."
echo "  cd $WT_DIR && claude"
