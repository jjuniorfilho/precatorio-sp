#!/usr/bin/env bash
#
# fleet-phase-gate.sh — Cortex Fleet · gate de artefatos de fase (nao-pulavel)
#
# Verifica que os artefatos obrigatorios da fase existem ANTES de deixar a frota
# avancar. Mesmo contrato do fleet-gate.sh: SAI COM CODIGO 2 e o stderr volta como
# feedback para o agente corrigir.
#
# Por que existe (issue #40): no modo autonomo o /engineer:start produzia context.md
# e parava antes do architecture.md — 0/6 nos PRs de frota contra 4/4 no fluxo manual,
# com o start.md byte-a-byte identico entre os repos. O modo autonomo remove os GATES
# HUMANOS, nao os ARTEFATOS; sem architecture.md a Verificacao Cruzada de Consistencia
# (obrigatoria no start.md) nao roda, e o freio de mao de "nova decisao arquitetural"
# passa a operar sem o insumo que o fundamenta.
#
# Instrucao no fim de um comando longo depende do agente lembrar com a janela cheia.
# Checagem de filesystem nao depende de nada disso.
#
# Uso:
#   fleet-phase-gate.sh --phase 1 [--slug px-4123]   # exige context.md + architecture.md
#   fleet-phase-gate.sh --phase 2 [--slug px-4123]   # exige tambem plan.md
#   fleet-phase-gate.sh --phase 1 --dry-run          # so reporta, nao bloqueia
#
# Sem --slug, deriva da branch atual (px-4123-... / issue-39-... / feat/algo).
#
set -uo pipefail

# Resolver ANTES de qualquer `cd`. Com `${BASH_SOURCE[0]}` relativo — que e como a
# doc manda invocar (`scripts/fleet-phase-gate.sh --phase 1`) — calcular isto depois
# do `cd "$ROOT"` faz o dirname virar a raiz do repo, o _emit.sh nunca ser achado e a
# telemetria de processo morrer. O gate continua bloqueando, entao a perda era invisivel.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "fleet-phase-gate: nao e um repositorio git" >&2; exit 2; }
cd "$ROOT" || { echo "fleet-phase-gate: nao foi possivel entrar em $ROOT" >&2; exit 2; }

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

# Registra o veredito da fase. E o unico sinal de que a fase ACONTECEU que nao
# depende do agente lembrar de registrar — e, por ser o gate, prova mais que uma
# invocacao de comando: so passa com o artefato presente E commitado.
gate_emit() {
  [[ "${DRY_RUN:-0}" == 1 ]] && return 0     # dry-run reporta, nao decide
  local cmd="/engineer:start"
  [[ "${PHASE:-}" == "2" ]] && cmd="/engineer:plan"
  local args=("fleet.phase${PHASE:-0}" --outcome "$1" --command "$cmd")
  [[ -n "${SLUG:-}" ]] && args+=(--task "$SLUG")
  fleet_emit "${args[@]}"
}

PHASE=""
SLUG=""
DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --phase)
      # validar presenca do valor antes de shift 2 evita "unbound variable" sob set -u
      [[ $# -ge 2 ]] || { echo "fleet-phase-gate: --phase exige um valor" >&2; exit 2; }
      PHASE="$2"; shift 2 ;;
    --slug)
      [[ $# -ge 2 ]] || { echo "fleet-phase-gate: --slug exige um valor" >&2; exit 2; }
      SLUG="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    *) echo "fleet-phase-gate: argumento desconhecido '$1'" >&2; exit 2 ;;
  esac
done

[[ "$PHASE" =~ ^[12]$ ]] || { echo "fleet-phase-gate: --phase deve ser 1 ou 2" >&2; exit 2; }

# Allowlist de charset: o slug vira componente de path.
if [[ -n "$SLUG" ]]; then
  [[ "$SLUG" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "fleet-phase-gate: slug invalido '$SLUG'" >&2; exit 2; }
else
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  TAIL="${BRANCH##*/}"
  if [[ "$TAIL" =~ ([Pp][Xx]-[0-9]{2,6}) ]]; then
    SLUG="${BASH_REMATCH[1]}"
  elif [[ "$TAIL" =~ (issue-[0-9]+) ]]; then
    SLUG="${BASH_REMATCH[1]}"
  else
    SLUG="$TAIL"
  fi
  [[ "$SLUG" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "fleet-phase-gate: nao foi possivel derivar slug da branch '$BRANCH'" >&2; exit 2; }
fi

SESSIONS="$ROOT/.claude/sessions"
DIR=""
if [[ -d "$SESSIONS" ]]; then
  # match case-insensitive: as convencoes variam (PX-4123, px-4123-nome)
  shopt -s nocasematch 2>/dev/null || true
  for d in "$SESSIONS"/*/; do
    [[ -d "$d" ]] || continue          # guarda contra glob nao-expandido
    name="$(basename "$d")"
    if [[ "$name" == "$SLUG" || "$name" == *"$SLUG"* ]]; then DIR="${d%/}"; break; fi
  done
  shopt -u nocasematch 2>/dev/null || true
fi

REQUIRED=("context.md" "architecture.md")
[[ "$PHASE" == "2" ]] && REQUIRED+=("plan.md")

if [[ -z "$DIR" ]]; then
  {
    echo ""
    echo "⛔ FLEET PHASE GATE bloqueou a Fase $PHASE"
    echo "Nenhuma pasta de sessao encontrada para '$SLUG' em .claude/sessions/."
    echo "Rode /engineer:start antes de avancar — ele cria a pasta e os artefatos."
  } >&2
  gate_emit blocked
  [[ "$DRY_RUN" == 1 ]] && exit 0
  exit 2
fi

MISSING=()
for f in "${REQUIRED[@]}"; do
  [[ -s "$DIR/$f" ]] || MISSING+=("$f")
done

REL="${DIR#"$ROOT"/}"

# Existir nao basta: o artefato precisa estar COMMITADO. No modo autonomo a sessao
# nasce dentro da worktree, e o `git worktree remove` do teardown leva junto tudo que
# nunca virou commit — o gate passava, a frota entregava, e o rastro morria com a
# worktree. Medido no repo px-agents: 23 PRs de codigo mergeados numa janela de 7 dias
# com ZERO commit em .claude/sessions/ e a ultima pasta de sessao sendo de uma onda
# anterior. Nada em .gitignore explicava — os artefatos so nunca foram commitados.
#
# A checagem e por HEAD (nao por `git ls-files`) porque arquivo apenas staged tambem
# desaparece no remove. Complementa o guard do fleet-teardown.sh, que recusa remover
# worktree com mudanca nao-commitada: la o alvo e a modificacao, aqui e o arquivo.
#
# Exigir commit AQUI, e nao no fechamento, e o que preserva a ordem: o plano entra no
# historico antes do primeiro commit de codigo. Commitado no fim, o rastro existiria
# mas com o plano DEPOIS do codigo — retroativo, que e um sinal pior do que a ausencia.
UNCOMMITTED=()
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  for f in "${REQUIRED[@]}"; do
    [[ -s "$DIR/$f" ]] || continue          # ausente ja e reportado em MISSING
    git cat-file -e "HEAD:$REL/$f" 2>/dev/null || UNCOMMITTED+=("$f")
  done
fi

if [[ ${#MISSING[@]} -gt 0 ]]; then
  {
    echo ""
    echo "⛔ FLEET PHASE GATE bloqueou a Fase $PHASE — artefato obrigatorio ausente"
    echo "Sessao: $REL"
    for f in "${MISSING[@]}"; do echo "  ✗ $f"; done
    echo ""
    if [[ " ${MISSING[*]} " == *" architecture.md "* ]]; then
      echo "architecture.md e obrigatorio tambem no modo autonomo. O autonomo dispensa os"
      echo "GATES HUMANOS, nao os ARTEFATOS: sem ele a Verificacao Cruzada de Consistencia"
      echo "nao roda e o freio de 'nova decisao arquitetural' fica sem insumo."
      echo "Volte ao /engineer:start e complete a Estruturacao Arquitetural."
    fi
    if [[ " ${MISSING[*]} " == *" plan.md "* ]]; then
      echo "plan.md ausente: rode /engineer:plan antes de iniciar a implementacao."
    fi
  } >&2
  gate_emit blocked
  [[ "$DRY_RUN" == 1 ]] && exit 0
  exit 2
fi

if [[ ${#UNCOMMITTED[@]} -gt 0 ]]; then
  {
    echo ""
    echo "⛔ FLEET PHASE GATE bloqueou a Fase $PHASE — artefato existe mas NAO esta commitado"
    echo "Sessao: $REL"
    for f in "${UNCOMMITTED[@]}"; do echo "  ✗ $f (fora do HEAD)"; done
    echo ""
    echo "No modo autonomo a sessao vive dentro da worktree, e o teardown remove tudo que"
    echo "nunca virou commit. Sem commit AGORA, a frota entrega o PR e o rastro morre junto"
    echo "com a worktree — o gate teria passado e a main ficaria sem prova de que houve plano."
    echo ""
    echo "Commite antes de avancar (e antes do primeiro commit de codigo, para o plano nao"
    echo "ficar registrado DEPOIS da implementacao):"
    echo "  git add $REL && git commit -m 'docs(sessao): ${REL##*/} — artefatos de ${REQUIRED[*]}'"
  } >&2
  gate_emit blocked
  [[ "$DRY_RUN" == 1 ]] && exit 0
  exit 2
fi

gate_emit pass
echo "✔ fleet-phase-gate: Fase $PHASE completa e commitada em $REL (${REQUIRED[*]})"
exit 0
