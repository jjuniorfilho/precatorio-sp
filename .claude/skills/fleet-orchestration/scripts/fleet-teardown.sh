#!/usr/bin/env bash
#
# fleet-teardown.sh — Cortex Fleet · cleanup idempotente de uma worktree
#
# Remove a worktree, (opcionalmente) os dados isolados via fleet_teardown_data(), e a
# branch local. Por seguranca, NUNCA remove a worktree se ela tiver mudancas
# nao-commitadas, a menos que --force seja passado.
#
# Uso:
#   fleet-teardown.sh <worktree-name> [--drop-db] [--delete-branch] [--force] [--dry-run]
# Ex.:
#   fleet-teardown.sh px-2621-llm-factory --drop-db --delete-branch
#
set -euo pipefail

WT_NAME="${1:-}"
[[ -z "$WT_NAME" ]] && { echo "ERRO: informe o nome da worktree"; exit 1; }
[[ "$WT_NAME" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "ERRO: nome de worktree invalido — use apenas [A-Za-z0-9._/-]"; exit 1; }
shift || true

DROP_DB=0; DEL_BRANCH=0; FORCE=0; DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --drop-db) DROP_DB=1; shift;;
    --delete-branch) DEL_BRANCH=1; shift;;
    --force) FORCE=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    *) echo "flag desconhecida: $1"; exit 1;;
  esac
done

ROOT="$(git rev-parse --show-toplevel)"
CONFIG="$ROOT/.claude/fleet.config.sh"
# shellcheck source=/dev/null
[[ -f "$CONFIG" ]] && source "$CONFIG"

WT_BASE_DIR="${FLEET_WORKTREE_DIR:-.claude/worktrees}"
WT_DIR="$ROOT/$WT_BASE_DIR/$WT_NAME"

default_prefix() {
  local n; n="$(git config user.name 2>/dev/null || true)"
  n="$(printf '%s' "$n" | tr '[:upper:]' '[:lower:]' | tr -cs '[:alnum:]' '-' | sed 's/^-*//;s/-*$//')"
  printf '%s' "${n:-fleet}"
}
PREFIX="${FLEET_BRANCH_PREFIX:-$(default_prefix)}"
BRANCH="${FLEET_BRANCH:-$PREFIX/$WT_NAME}"
SHORT_ID="$(printf '%s' "$WT_NAME" | grep -oE '[a-zA-Z]+-?[0-9]+' | head -1 | tr -d '-' || true)"
[[ -z "$SHORT_ID" ]] && SHORT_ID="$(printf '%s' "$WT_NAME" | tr -cd '[:alnum:]')"

run() { if [[ "$DRY_RUN" == 1 ]]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

echo "> Teardown worktree: $WT_NAME"

# guarda: nao destruir trabalho nao-salvo sem --force
if [[ -d "$WT_DIR" && "$FORCE" == 0 ]]; then
  if ! git -C "$WT_DIR" diff --quiet || ! git -C "$WT_DIR" diff --cached --quiet \
     || [[ -n "$(git -C "$WT_DIR" status --porcelain)" ]]; then
    echo "✋ worktree tem mudancas nao-commitadas. Use --force para remover assim mesmo."
    exit 1
  fi
fi

# dados isolados (hook do projeto) — antes de remover a worktree
if [[ "$DROP_DB" == 1 ]]; then
  if declare -F fleet_teardown_data >/dev/null; then
    if [[ "$DRY_RUN" == 1 ]]; then
      echo "  [dry-run] fleet_teardown_data '$WT_NAME' '$WT_DIR' '$SHORT_ID'"
    else
      fleet_teardown_data "$WT_NAME" "$WT_DIR" "$SHORT_ID"
    fi
  else
    echo "  --drop-db passado mas sem fleet_teardown_data definida — pulando"
  fi
fi

if [[ -d "$WT_DIR" ]]; then
  run "git -C '$ROOT' worktree remove '$WT_DIR' $([[ "$FORCE" == 1 ]] && echo --force)"
else
  echo "  worktree nao existe — pulando"
fi

if [[ "$DEL_BRANCH" == 1 ]]; then
  run "git -C '$ROOT' branch -D '$BRANCH' 2>/dev/null || true"
fi

echo "✔ Teardown de '$WT_NAME' concluido."
