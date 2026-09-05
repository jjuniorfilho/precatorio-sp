#!/usr/bin/env bash
#
# fleet-closeout.sh — Cortex Fleet · fechamento de uma issue (modo autonomo)
#
# Orquestra a CAUDA repetitiva do modo autonomo, DEPOIS que o humano autorizou o merge
# (--merge ou GO explicito): guarda de rastro → merge remoto opcional → sincroniza a
# branch base → preserva a telemetria da worktree → teardown da worktree → imprime o
# checklist do que o LEAD ainda faz via tracker/edicoes (issue → Done, nota na doc
# canonica, memoria de sessao). O script NAO toca o tracker nem edita docs — isso e
# julgamento/estado do lead; ele so automatiza git + gh + teardown e lembra do resto.
# Requer o GitHub CLI (`gh`) para o passo de merge.
#
# O teardown e destrutivo por natureza e a worktree e o unico lugar onde o rastro da
# frota existe: pasta de sessao e telemetria nascem la. Por isso os passos 1 e 4 rodam
# antes dele — um recusa fechar sem rastro commitado, o outro traz a telemetria para o
# checkout principal. Sem os dois, cada onda entregava PRs e apagava a prova de como
# foram feitos.
#
# Rode do repositorio PRINCIPAL (nao de dentro da worktree-alvo).
#
# Uso:
#   fleet-closeout.sh <worktree-name> [<pr#>] [--merge] [--drop-db] [--delete-branch] \
#       [--no-teardown] [--force] [--skip-trace-guard] [--dry-run]
# Ex.:
#   fleet-closeout.sh px-2621-llm-factory 231 --merge --drop-db --delete-branch
#
# Guarda de seguranca: com --merge, so mergeia se o PR estiver MERGEABLE + CLEAN.
# Nunca forca o merge de um PR sujo/conflitado (salvo --force).
#
set -euo pipefail

WT_NAME="${1:-}"
[[ -z "$WT_NAME" ]] && { echo "ERRO: informe o nome da worktree"; exit 1; }
[[ "$WT_NAME" =~ ^[A-Za-z0-9._/-]+$ ]] || { echo "ERRO: nome de worktree invalido — use apenas [A-Za-z0-9._/-]"; exit 1; }
shift || true

PR_NUM=""; DO_MERGE=0; DROP_DB=0; DEL_BRANCH=0; NO_TEARDOWN=0; FORCE=0; DRY_RUN=0
SKIP_TRACE=0
need_val() { [[ $# -ge 2 ]] || { echo "ERRO: $1 requer um valor"; exit 1; }; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --merge) DO_MERGE=1; shift;;
    --pr) need_val "$@"; PR_NUM="$2"; shift 2;;
    --drop-db) DROP_DB=1; shift;;
    --delete-branch) DEL_BRANCH=1; shift;;
    --no-teardown) NO_TEARDOWN=1; shift;;
    --force) FORCE=1; shift;;
    --skip-trace-guard) SKIP_TRACE=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    [0-9]*) PR_NUM="$1"; shift;;              # 2o posicional numerico = pr#
    *) echo "flag desconhecida: $1"; exit 1;;
  esac
done

# PR_NUM (via --pr ou 2o posicional) deve ser numerico — evita quebra de quoting no eval do gh
[[ -z "$PR_NUM" || "$PR_NUM" =~ ^[0-9]+$ ]] || { echo "ERRO: numero de PR invalido: '$PR_NUM'"; exit 1; }

# config layer do projeto (branch base, etc.)
_TL="$(git rev-parse --show-toplevel 2>/dev/null || true)"
CONFIG="${_TL:+$_TL/.claude/fleet.config.sh}"
# shellcheck source=/dev/null
[[ -n "$CONFIG" && -f "$CONFIG" ]] && source "$CONFIG"

# main worktree = 1a linha de `git worktree list` (roda de qualquer cwd)
MAIN_ROOT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_REF="${FLEET_BASE_REF:-origin/main}"     # ex.: origin/main
BASE_REMOTE="${BASE_REF%%/*}"                 # origin
BASE_BRANCH="${BASE_REF##*/}"                 # main
# `|| true` obrigatorio: sob `set -euo pipefail`, um WT_NAME sem digito faz o grep
# sair 1, o pipefail propaga e o script MORRE aqui — antes do banner, antes de
# qualquer aviso, com zero stderr. Exit 1 e silencio total num script cuja tese e
# que falha silenciosa e o pior defeito possivel. O fleet-provision.sh ja protegia
# o pipeline analogo (:92); o closeout era o unico sem a guarda.
ISSUE_ID="$(printf '%s' "$WT_NAME" | grep -oiE '[a-z]+-?[0-9]+' | head -1 | tr 'a-z' 'A-Z' | sed -E 's/^([A-Z]+)-?/\1-/' || true)"
if [[ -z "$ISSUE_ID" ]]; then
  echo "fleet-closeout: nao consegui derivar um ID de issue de '$WT_NAME' (sem digito)." >&2
  echo "fleet-closeout: seguindo com o nome da worktree como identificador." >&2
  ISSUE_ID="$WT_NAME"
fi
WT_DIR="$MAIN_ROOT/${FLEET_WORKTREE_DIR:-.claude/worktrees}/$WT_NAME"
TEL_REL=".claude/memory/evolution/command-usage.jsonl"

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

run() { if [[ "$DRY_RUN" == 1 ]]; then echo "  [dry-run] $*"; else eval "$*"; fi; }

echo "> Close-out: $WT_NAME${PR_NUM:+ (PR #$PR_NUM)}"

# 1. Guarda de rastro: a sessao precisa estar commitada ANTES do merge
#
# Roda antes do passo 2 de proposito. Depois do `gh pr merge --squash --delete-branch`
# a branch nao existe mais, e um rastro commitado ali viraria commit solto na main, fora
# do PR que ele documenta. Aqui ainda da para o agente commitar e o rastro entrar na
# entrega. Delega ao fleet-phase-gate.sh rodado DE DENTRO da worktree: uma regra, uma
# implementacao — o mesmo gate que liberou a Fase 2 e o que autoriza o fechamento.
#
# O escape e `--skip-trace-guard`, NAO `--force`, de proposito. `--force` ja significa
# outras duas coisas (mergear PR nao-CLEAN e remover worktree suja) e acaba virando
# habito; pendurar a durabilidade do rastro nele reconstruiria o mesmo buraco silencioso
# que este guard existe para fechar. Perder rastro tem que ser uma escolha explicita.
if [[ -d "$WT_DIR" && "$SKIP_TRACE" == 0 ]]; then
  if _gate_out="$(cd "$WT_DIR" && "$SCRIPT_DIR/fleet-phase-gate.sh" --phase 2 2>&1)"; then
    echo "  rastro de sessao: commitado ✔"
  else
    {
      echo ""
      echo "✋ Rastro de sessao ausente ou nao-commitado em $WT_NAME."
      echo "$_gate_out"
      echo ""
      echo "Commite a pasta .claude/sessions/<issue>/ na worktree e rode o close-out de novo."
      echo "Sem isso o teardown apaga o unico registro de que houve discovery e plano."
      echo "Use --skip-trace-guard para fechar assim mesmo (o rastro sera perdido)."
    } >&2
    exit 1
  fi
elif [[ "$SKIP_TRACE" == 1 ]]; then
  echo "  ⚠ guarda de rastro pulada por --skip-trace-guard"
else
  echo "  (worktree ja removida — pulando a guarda de rastro)"
fi

# 2. Merge remoto (opt-in, fail-closed em PR nao-limpo)
if [[ "$DO_MERGE" == 1 ]]; then
  [[ -z "$PR_NUM" ]] && { echo "✋ --merge exige o numero do PR (2o argumento ou --pr N)"; exit 1; }
  command -v gh >/dev/null || { echo "✋ --merge requer o GitHub CLI (gh) instalado"; exit 1; }
  state="$(gh pr view "$PR_NUM" --json mergeable,mergeStateStatus --jq '.mergeable+"/"+.mergeStateStatus' 2>/dev/null || echo "UNKNOWN/UNKNOWN")"
  echo "  PR #$PR_NUM: $state"
  if [[ "$state" != "MERGEABLE/CLEAN" && "$FORCE" == 0 ]]; then
    echo "✋ PR nao esta MERGEABLE/CLEAN. Reveja os checks/conflitos ou use --force. Abortando o merge."
    exit 1
  fi
  run "gh pr merge '$PR_NUM' --squash --delete-branch"
else
  echo "  (sem --merge — assumindo que o PR ja foi mergeado; so sincroniza e faz teardown)"
fi

# 3. Sincroniza a branch base
run "git -C '$MAIN_ROOT' checkout '$BASE_BRANCH'"
run "git -C '$MAIN_ROOT' pull '$BASE_REMOTE' '$BASE_BRANCH' --quiet"
echo "  $BASE_BRANCH: $(git -C "$MAIN_ROOT" rev-parse --short HEAD 2>/dev/null || echo '?')"

# 4. Telemetria da worktree para o checkout principal, antes do teardown
#
# O telemetry-hook resolve `mem` a partir do cwd do agente (.claude/memory/evolution do
# CWD), entao tudo que a frota registrou vive dentro da worktree e some no `worktree
# remove`. O arquivo nao esta em .gitignore — ele so nunca chega na main. Sintoma medido
# no px-agents: /work e /pre-pr com 83 e 26 execucoes no historico e ZERO na janela de
# uma onda de 23 PRs, o que faz a auditoria ler "processo pulado" onde houve processo.
#
# Merge por linha, deduplicado, preservando ordem — barato porque desde a v3.7.0 o
# formato e JSONL (uma entrada por linha). Idempotente: rodar o close-out de novo nao
# duplica nada.
#
# A copia da worktree e removida DEPOIS de provar que cada linha chegou na main. Nao e
# limpeza cosmetica: o arquivo nao esta em .gitignore, entao ele deixa toda worktree
# permanentemente suja, e o fleet-teardown.sh recusa remover worktree suja. Na pratica
# isso obrigava a passar --force sempre, o que desligava justamente a guarda que protege
# trabalho nao-commitado. Absorvendo a telemetria, aquele guard volta a significar algo.
if [[ -f "$WT_DIR/$TEL_REL" ]]; then
  if [[ "$DRY_RUN" == 1 ]]; then
    echo "  [dry-run] merge de telemetria: $WT_DIR/$TEL_REL -> $MAIN_ROOT/$TEL_REL"
  else
    mkdir -p "$(dirname "$MAIN_ROOT/$TEL_REL")"
    touch "$MAIN_ROOT/$TEL_REL"
    _tel_tmp="$(mktemp)"
    # Comparar por FILENAME, nao pelo idioma NR==FNR: com o arquivo da main VAZIO
    # (primeira onda do repo) o awk nunca processa registro no 1o passe, entao
    # NR==FNR continua verdadeiro no 2o e TODA linha da worktree e classificada
    # como ja-vista. O merge devolvia zero em silencio exatamente na estreia.
    if awk -v main="$MAIN_ROOT/$TEL_REL" \
           'FILENAME==main{seen[$0]=1;next} !seen[$0]++' \
           "$MAIN_ROOT/$TEL_REL" "$WT_DIR/$TEL_REL" > "$_tel_tmp"; then
      _tel_n="$(wc -l < "$_tel_tmp" | tr -d ' ')"
      [[ "${_tel_n:-0}" -gt 0 ]] && cat "$_tel_tmp" >> "$MAIN_ROOT/$TEL_REL"
      # nunca apagar a unica copia sem provar que a outra existe
      _tel_left="$(awk -v main="$MAIN_ROOT/$TEL_REL" \
                   'FILENAME==main{seen[$0]=1;next} !($0 in seen)' \
                   "$MAIN_ROOT/$TEL_REL" "$WT_DIR/$TEL_REL" | wc -l | tr -d ' ')"
      if [[ "${_tel_left:-1}" -ne 0 ]]; then
        echo "  ⚠ telemetria: ${_tel_left} linha(s) nao confirmada(s) na main — copia da worktree mantida"
      elif git -C "$WT_DIR" ls-files --error-unmatch -- "$TEL_REL" >/dev/null 2>&1; then
        # versionado neste repo: apagar seria alterar o conteudo da branch, nao limpar
        # residuo. A sujeira que sobra e uma mudanca real e o teardown deve mesmo barrar.
        echo "  telemetria: +${_tel_n:-0} entrada(s) preservada(s); copia versionada mantida"
      else
        rm -f "$WT_DIR/$TEL_REL"
        echo "  telemetria: +${_tel_n:-0} entrada(s) preservada(s); copia da worktree absorvida"
      fi
    else
      echo "  ⚠ telemetria: merge falhou — copia da worktree mantida intacta"
    fi
    rm -f "$_tel_tmp"
  fi
fi

fleet_emit fleet.closeout --outcome pass --command /engineer:pr --task "${ISSUE_ID:-$WT_NAME}"

# 5. Teardown da worktree (delega ao script canonico + hook fleet_teardown_data)
if [[ "$NO_TEARDOWN" == 0 ]]; then
  td_flags=""
  [[ "$DROP_DB" == 1 ]] && td_flags+=" --drop-db"
  [[ "$DEL_BRANCH" == 1 ]] && td_flags+=" --delete-branch"
  [[ "$FORCE" == 1 ]] && td_flags+=" --force"
  [[ "$DRY_RUN" == 1 ]] && td_flags+=" --dry-run"
  run "'$SCRIPT_DIR/fleet-teardown.sh' '$WT_NAME'$td_flags"
fi

# 6. Checklist do que o LEAD ainda faz (fora do alcance do script)
#
# A telemetria saiu daqui: virou o passo 4. Item de checklist depende do humano lembrar
# depois que a worktree ja foi apagada — era pedir a prova sem o lugar onde ela vivia.
cat <<EOF

> Falta o lead fechar (tracker / edicoes — NAO automatizado):
  [ ] Tracker ${ISSUE_ID:-<issue>} → Done   (ex.: mcp save_issue state:"Done")
  [ ] Doc canonica do repo: nota, se a mudanca for estrutural
  [ ] .claude/memory/sessions/<data>-<slug>.md  (+ handoff, se houver continuacao)
✔ Close-out de '$WT_NAME' concluido.
EOF
