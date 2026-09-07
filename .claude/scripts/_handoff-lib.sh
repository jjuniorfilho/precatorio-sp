#!/usr/bin/env bash
#
# _handoff-lib.sh — Cortex · base compartilhada do /engineer:handoff (sourced, nao executar)
#
# Existe para que `handoff-measure.sh` e `handoff-commit.sh` resolvam a branch principal e a
# config pelo MESMO caminho. Duplicar isso seria convidar o pior defeito ja encontrado neste
# comando: `origin/HEAD` da o NOME `main`, a branch local `main` pode nao existir num clone
# comum, e uma copia local desatualizada faz o gap de producao sair ZERO sob rotulo MEDIDO.
# O measure ja foi endurecido contra isso; o commit precisa herdar, nao reimplementar — o
# gate "recusa fora da main" compara contra exatamente a mesma referencia.
#
# Contrato: quem sourceia ja fez `cd` para a raiz do repo e definiu ROOT.
#
# shellcheck disable=SC2034
# (MAIN_NAME/MAIN_REF/MAIN_WHY/MAIN_ATRASO/CONFIG_AVISO sao a saida desta lib — consumidas
#  por quem a sourceia, e o shellcheck nao enxerga alem do arquivo.)

# ── helpers de status ─────────────────────────────────────────────────────────
first_line() { printf '%s' "${1%%$'\n'*}"; }

# Uma ref so pode entrar num range depois de resolver. Sem isto, `rev-list A..B` com B
# inexistente sai vazio com status 0 e o chamador declara "nada" com confianca.
ref_ok() { git rev-parse --verify --quiet "${1}^{commit}" >/dev/null 2>&1; }

# ── config layer ──────────────────────────────────────────────────────────────
# A config e codigo de terceiro, e sourcea-la no shell principal nao tem modo seguro: um
# `exit` (copy-paste comum) mataria o script e produziria ZERO saida.
#
# Nenhuma validacao estatica resolve isso. `bash -n` valida GRAMATICA, nao usabilidade:
# medido no bash 3.2.57, `if [ -z "$X" ; then echo a; fi` passa com rc=0 E stderr vazio, e
# explode em runtime. E `source` devolve o status do ULTIMO COMANDO do arquivo, nao do
# carregamento — config valida terminando em condicional falsa "falharia".
#
# Entao a config roda num SUBSHELL e so o resultado atravessa. Se ela morrer, morre sozinha.
# ATENCAO: este bloco roda NO CORPO da lib, nao dentro de uma funcao, e isso e deliberado.
#
# `declare` dentro de funcao cria variavel LOCAL — entao `eval "$(declare -p ...)"` num
# `handoff_load_config()` produzia variaveis que morriam ao retornar, e a config chegava
# vazia ao chamador (a secao FRONTEIRA_TOCADA passou a dizer "HANDOFF_BOUNDARY_PATHS vazio"
# com a config preenchida). `declare -g` resolveria, mas so existe do bash 4.2 em diante e o
# macOS roda 3.2. Sourcear no corpo faz o eval acontecer no top-level de quem sourceia, que
# e exatamente onde as variaveis precisam existir.
_HANDOFF_ENV_DIR="${HANDOFF_DIR:-}"
_HANDOFF_ENV_MEM="${HANDOFF_MEMORY_FILE:-}"
_HANDOFF_ENV_MAIN="${HANDOFF_MAIN_BRANCH:-}"
_HANDOFF_ENV_WF="${HANDOFF_DEPLOY_WORKFLOW:-}"
_HANDOFF_ENV_REF="${HANDOFF_PROD_REF:-}"

HANDOFF_DIR="docs/handoffs"
HANDOFF_MEMORY_FILE=".claude/memory/MEMORY.md"
HANDOFF_DEPLOY_WORKFLOW=""
HANDOFF_PROD_REF=""
HANDOFF_MAIN_BRANCH=""
HANDOFF_BOUNDARY_PATHS=()
CONFIG_AVISO=""

_HANDOFF_CFG="$ROOT/.claude/handoff.config.sh"
if [[ -f "$_HANDOFF_CFG" ]]; then
  _HANDOFF_ERRFILE="$(mktemp -t handoffcfg.XXXXXX 2>/dev/null || echo "/tmp/handoffcfg.$$")"
  _HANDOFF_DUMP="$(
    set +u
    # shellcheck source=/dev/null
    source "$_HANDOFF_CFG" >/dev/null 2>"$_HANDOFF_ERRFILE"
    declare -p HANDOFF_DIR HANDOFF_MEMORY_FILE HANDOFF_DEPLOY_WORKFLOW \
               HANDOFF_PROD_REF HANDOFF_MAIN_BRANCH HANDOFF_BOUNDARY_PATHS 2>/dev/null
  )"
  _HANDOFF_STDERR="$(cat "$_HANDOFF_ERRFILE" 2>/dev/null)"
  rm -f "$_HANDOFF_ERRFILE"

  if [[ -z "$_HANDOFF_DUMP" ]]; then
    CONFIG_AVISO="config .claude/handoff.config.sh NAO completou (exit, erro fatal ou sintaxe) — usando defaults"
    [[ -n "$_HANDOFF_STDERR" ]] && CONFIG_AVISO="${CONFIG_AVISO}: $(first_line "$_HANDOFF_STDERR")"
  else
    # `declare -p` produz atribuicoes ja quotadas pelo proprio bash — mesmo threat model
    # do fleet.config.sh: arquivo dev-owned, confianca equivalente a dos scripts do repo.
    eval "$_HANDOFF_DUMP"
    [[ -n "$_HANDOFF_STDERR" ]] && \
      CONFIG_AVISO="config .claude/handoff.config.sh carregou COM ERROS (aplicada parcialmente): $(first_line "$_HANDOFF_STDERR")"
  fi
fi

# env precede config
[[ -n "$_HANDOFF_ENV_DIR" ]]  && HANDOFF_DIR="$_HANDOFF_ENV_DIR"
[[ -n "$_HANDOFF_ENV_MEM" ]]  && HANDOFF_MEMORY_FILE="$_HANDOFF_ENV_MEM"
[[ -n "$_HANDOFF_ENV_MAIN" ]] && HANDOFF_MAIN_BRANCH="$_HANDOFF_ENV_MAIN"
[[ -n "$_HANDOFF_ENV_WF" ]]   && HANDOFF_DEPLOY_WORKFLOW="$_HANDOFF_ENV_WF"
[[ -n "$_HANDOFF_ENV_REF" ]]  && HANDOFF_PROD_REF="$_HANDOFF_ENV_REF"

# Config pode ter apagado o array. Sob `set -u`, expandir array nao-declarado aborta no
# bash 3.2 do macOS — a guarda real e testar `${#arr[@]}` antes de qualquer `"${arr[@]}"`.
if ! declare -p HANDOFF_BOUNDARY_PATHS >/dev/null 2>&1; then
  HANDOFF_BOUNDARY_PATHS=()
fi

# ── branch principal ──────────────────────────────────────────────────────────
# MAIN_NAME = nome curto (comparar com branch de worktree / branch atual)
# MAIN_REF  = ref que resolve (usar em ranges). Sao coisas diferentes.
MAIN_NAME=""
MAIN_REF=""
MAIN_WHY=""
MAIN_ATRASO=""

# origin/<nome> VENCE a copia local quando ambas resolvem: a local pode estar dias atras sem
# que ninguem note, e ai o gap de producao sai ZERO com rotulo MEDIDO. O que interessa e o
# que o time ve, nao o que este checkout baixou por ultimo.
_handoff_escolher_ref() {
  local nome="$1" atras
  if ref_ok "origin/$nome"; then
    MAIN_REF="origin/$nome"
    if ref_ok "$nome"; then
      atras="$(git rev-list --count "${nome}..origin/${nome}" 2>/dev/null)" || atras=""
      [[ -n "$atras" && "$atras" != "0" ]] && \
        MAIN_ATRASO="a copia local de '$nome' esta $atras commit(s) atras de origin/$nome — medindo por origin/"
    fi
    return 0
  fi
  if ref_ok "$nome"; then MAIN_REF="$nome"; return 0; fi
  return 1
}

handoff_resolver_main() {
  local cand ref
  if [[ -n "${HANDOFF_MAIN_BRANCH:-}" ]]; then
    MAIN_NAME="$HANDOFF_MAIN_BRANCH"
    _handoff_escolher_ref "$MAIN_NAME" && return 0
    MAIN_WHY="HANDOFF_MAIN_BRANCH='$MAIN_NAME' nao resolve nem local nem em origin/"
    MAIN_NAME=""; return 1
  fi

  ref="$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"
  if [[ -n "$ref" ]]; then
    MAIN_NAME="${ref#refs/remotes/origin/}"
    _handoff_escolher_ref "$MAIN_NAME" && return 0
  fi

  for cand in main master trunk; do
    if _handoff_escolher_ref "$cand"; then MAIN_NAME="$cand"; return 0; fi
  done

  MAIN_WHY="sem origin/HEAD e sem main/master/trunk que resolvam — defina HANDOFF_MAIN_BRANCH"
  MAIN_NAME=""; MAIN_REF=""; return 1
}

# ── branch atual ──────────────────────────────────────────────────────────────
# `git rev-parse --abbrev-ref HEAD` num repo sem commits ecoa "HEAD" no stdout E sai !=0,
# entao `|| echo '?'` concatenaria os dois e quebraria o cabecalho em duas linhas.
handoff_branch_atual() {
  local b sha
  b="$(git symbolic-ref --short --quiet HEAD 2>/dev/null)" || b=""
  if [[ -n "$b" ]]; then printf '%s' "$b"; return 0; fi
  if sha="$(git rev-parse --short --verify --quiet HEAD 2>/dev/null)" && [[ -n "$sha" ]]; then
    printf '(detached em %s)' "$sha"; return 0
  fi
  printf '(repo sem commits)'
}
