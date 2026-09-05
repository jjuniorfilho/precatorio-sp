#!/usr/bin/env bash
#
# fleet-gate.sh — Cortex Fleet · gate de garantia nao-pulavel
#
# Roda as checagens mecanicas que materializam as garantias do Fleet e SAI COM CODIGO 2
# se qualquer uma falhar. Pensado para ser disparado por hooks do Claude Code
# (TaskCompleted / TeammateIdle): exit 2 IMPEDE o agente de marcar a fase como concluida
# e devolve o stderr como feedback para ele corrigir.
#
# Stack-agnostico: os comandos vem de FLEET_GATE_CMDS na config layer
# (.claude/fleet.config.sh). Sem config, auto-detecta "lint" e "test" do package.json.
# A parte LLM do ADR (adr-compliance-checker STRICT) roda dentro de /work e /pre-pr.
#
# Uso (manual ou via hook):
#   fleet-gate.sh                          # roda todos os gates configurados
#   FLEET_GATE_SCOPE=lint fleet-gate.sh    # so o gate "lint"
#   FLEET_GATE_SCOPE=lint,test fleet-gate.sh
#
# Roda na raiz da WORKTREE atual (git rev-parse), entao funciona em qualquer worktree.
#
set -uo pipefail

# Resolver ANTES de qualquer `cd`. Com `${BASH_SOURCE[0]}` relativo — que e como a
# doc manda invocar (`scripts/fleet-gate.sh`) — calcular isto depois do `cd "$ROOT"`
# faz o dirname virar a raiz do repo, o _emit.sh nunca ser achado e a telemetria de
# processo morrer. O gate continua passando, entao a perda era invisivel.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "fleet-gate: nao e um repositorio git" >&2; exit 2; }
cd "$ROOT" || { echo "fleet-gate: nao foi possivel entrar em $ROOT" >&2; exit 2; }

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

# detecta o runner do package manager
detect_runner() {
  if [[ -f "$ROOT/pnpm-lock.yaml" ]]; then echo "pnpm";
  elif [[ -f "$ROOT/yarn.lock" ]]; then echo "yarn";
  elif [[ -f "$ROOT/bun.lockb" ]]; then echo "bun run";
  else echo "npm run"; fi
}

# monta FLEET_GATE_CMDS por auto-detect se nao veio da config
if [[ -z "${FLEET_GATE_CMDS+x}" || ${#FLEET_GATE_CMDS[@]} -eq 0 ]]; then
  FLEET_GATE_CMDS=()
  if [[ -f "$ROOT/package.json" ]]; then
    RUN="$(detect_runner)"
    grep -qE '"lint"[[:space:]]*:' "$ROOT/package.json" && FLEET_GATE_CMDS+=("lint:$RUN lint")
    grep -qE '"test"[[:space:]]*:' "$ROOT/package.json" && FLEET_GATE_CMDS+=("test:$RUN test")
  fi
fi

if [[ ${#FLEET_GATE_CMDS[@]} -eq 0 ]]; then
  echo "✔ fleet-gate: nenhum gate configurado nem detectado — nada a verificar"
  exit 0
fi

SCOPE="${FLEET_GATE_SCOPE:-}"   # vazio = todos
in_scope() { [[ -z "$SCOPE" ]] && return 0; [[ ",$SCOPE," == *",$1,"* ]]; }
log() { printf "  • %s\n" "$*" >&2; }

# ── procedencia do log ────────────────────────────────────────────────────────
# O caminho derivava so do ROTULO (`lint`, `test`), entao duas worktrees da mesma frota — ou
# dois PROJETOS na mesma maquina — escreviam no MESMO arquivo, com `>` truncando: a ultima
# escrita vencia. Relatado por um consumidor em 2026-07-31, com caso real: um agente leu o log
# e recebeu a saida de outro projeto. Ele percebeu porque o conteudo era obviamente alheio; o
# modo perigoso e o contrario — dois checkouts do MESMO repo em branches diferentes produzem
# logs plausiveis, e nada no arquivo diz de onde ele veio.
#
# Isso importa porque o log e o insumo de uma decisao binaria que o modo autonomo toma sozinho:
# "esta falha e minha ou e pre-existente?". Ler a arvore errada leva a diagnostico confiante e
# errado nos dois sentidos — engolir regressao real como herdada, ou reverter trabalho bom.
#
# O log fica em /tmp (nao dentro da worktree) DE PROPOSITO: post-mortem de gate acontece depois
# do teardown, e este projeto ja gastou duas versoes investigando rastro que morria junto com a
# worktree (v3.8.0 e v3.9.0, ambas retratadas).
# Substituicao de parametro, nao `tr`: o `tr -c` converte tambem o newline final do pipe e
# produzia um hifen a mais no nome do arquivo.
WT_SLUG="$(basename "$ROOT")"
WT_SLUG="${WT_SLUG//[^A-Za-z0-9._-]/-}"
GATE_LOG_DIR="${FLEET_GATE_LOG_DIR:-/tmp}"
gate_log_path() { printf '%s/fleet-gate-%s-%s.log' "$GATE_LOG_DIR" "$WT_SLUG" "$1"; }

# Sem cabecalho, um log correto e um log alheio sao indistinguiveis.
gate_log_header() {
  local f="$1" label="$2" cmd="$3"
  {
    echo "# fleet-gate [$label]"
    echo "# worktree : $ROOT"
    echo "# branch   : $(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
    echo "# commit   : $(git rev-parse --short HEAD 2>/dev/null || echo '?')"
    echo "# quando   : $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "# comando  : $cmd"
    echo "# ---"
  } > "$f"
}

# ── integridade: o gate NAO pode alterar a arvore que julga ───────────────────
# `eslint --fix`, `prettier --write`, `ruff --fix`, `gofmt -w` — configurados sem querer no
# FLEET_GATE_CMDS, transformam o gate num pe-de-cabra silencioso: ele reescreve arquivos fora
# do escopo da issue, e quem nao roda `git status` depois commita mudanca de terceiro junto com
# a sua. O gate e a ultima coisa antes do commit, entao conferir depois dele e justamente o
# habito que ninguem tem. Relatado com 5 ocorrencias documentadas num consumidor.
#
# E fere o contrato: um gate que altera o objeto medido nao e fail-closed — ele pode
# transformar vermelho em verde escrevendo no codigo.
# A marca da arvore vem de `git stash create`, nao de um hash do `git status`.
#
# A primeira versao disto comparava `git status --porcelain`, e tinha dois furos, ambos
# reproduzidos: (1) arquivo JA modificado que o gate reescreve mantem o mesmo status ` M`, entao
# a mutacao passava com o gate imprimindo "verde" — e esse e o caso DOMINANTE, porque o dev
# esta editando justamente os arquivos que o `--fix` vai reescrever; (2) `shasum` ausente fazia
# a funcao devolver vazio e a guarda desligava a deteccao em silencio, que e exatamente a classe
# de defeito que a ADR-008 registra quatro vezes.
#
# `git stash create` produz um commit-objeto do conteudo real (sem tocar no stash stack nem na
# arvore), entao muda quando o CONTEUDO muda. E nao depende de ferramenta externa nenhuma.
#
# Ele ignora untracked, entao a lista de untracked entra na marca a parte — um gate que CRIA
# arquivo tambem esta mutando.
#
# A marca e o TREE do commit-objeto, nao o commit. `git stash create` estampa
# author/committer date no commit, entao duas chamadas com conteudo IDENTICO
# devolvem SHAs diferentes quando atravessam a fronteira do segundo — e qualquer
# gate que leve >=1s com a arvore suja era acusado de mutar (delta vazio, porque
# o `git diff` entre os dois nao encontrava arquivo nenhum). Fail-closed com
# falso positivo bloqueia o pipeline inteiro. O tree e conteudo-puro: mesma
# arvore, mesmo SHA, independente do relogio. A deteccao real fica intacta.
arvore_marca() {
  local s rc unt
  s="$(git stash create 2>/dev/null)"; rc=$?
  if [[ "$rc" -ne 0 ]]; then
    printf 'INDETERMINADO'
    return 1
  fi
  # arvore sem modificacao em tracked: `stash create` nao produz objeto — o HEAD serve de marca
  if [[ -n "$s" ]]; then
    s="$(git rev-parse --verify --quiet "$s^{tree}" 2>/dev/null || printf '%s' "$s")"
  else
    s="$(git rev-parse --verify --quiet 'HEAD^{tree}' 2>/dev/null || printf 'SEM-HEAD')"
  fi
  unt="$(git status --porcelain 2>/dev/null | grep '^??' | sort | tr '\n' '|')"
  printf '%s::%s' "$s" "$unt"
}
arvore_ref() { printf '%s' "${1%%::*}"; }

# Os arquivos que o gate realmente tocou: diff entre os dois commit-objetos (tracked) mais os
# untracked que apareceram. Listar o `git status` inteiro mostraria sujeira pre-existente, e
# acusar o gate por trabalho alheio mina a confianca na mensagem que precisa ser acreditada.
mutacao_delta() {
  local ra="$1" rb="$2" ua="$3" ub="$4"
  if [[ "$ra" != "SEM-HEAD" && "$rb" != "SEM-HEAD" ]]; then
    git diff --name-only "$ra" "$rb" 2>/dev/null | sed 's/^/   M /'
  fi
  printf '%s' "$ub" | tr '|' '\n' | grep -v '^$' | while IFS= read -r l; do
    printf '%s' "$ua" | tr '|' '\n' | grep -qxF "$l" || printf '  %s\n' "$l"
  done
}

FAILED=()
MUTANTES=()
MUTACAO_DELTA=""
MEDICAO_FALHOU=0
RAN=0
for item in "${FLEET_GATE_CMDS[@]}"; do
  label="${item%%:*}"
  cmd="${item#*:}"
  in_scope "$label" || continue
  RAN=1
  safe_label="${label//\//-}"   # label pode virar nome de arquivo de log
  gate_log="$(gate_log_path "$safe_label")"
  log "gate [$label]: $cmd"

  marca_antes="$(arvore_marca)" || MEDICAO_FALHOU=1
  gate_log_header "$gate_log" "$label" "$cmd"
  if ! bash -c "$cmd" >>"$gate_log" 2>&1; then
    FAILED+=("$label")
    log "[$label] FALHOU — ver $gate_log"
  fi

  marca_depois="$(arvore_marca)" || MEDICAO_FALHOU=1
  if [[ "$marca_antes" != "INDETERMINADO" && "$marca_depois" != "INDETERMINADO" \
        && "$marca_antes" != "$marca_depois" ]]; then
    MUTANTES+=("$label")
    # Acumula (nao sobrescreve): com dois gates mutantes, atribuir apagava o delta
    # do primeiro e o relatorio culpava so o ultimo — diagnostico incompleto no
    # exato momento em que o pipeline parou.
    _delta="$(mutacao_delta "$(arvore_ref "$marca_antes")" "$(arvore_ref "$marca_depois")" \
                            "${marca_antes#*::}" "${marca_depois#*::}")"
    [[ -n "$_delta" ]] && MUTACAO_DELTA="${MUTACAO_DELTA}${MUTACAO_DELTA:+$'\n'}[$label]"$'\n'"$_delta"
    log "[$label] MUTOU a arvore de trabalho"
  fi
done

if [[ "$RAN" == 0 ]]; then
  echo "✔ fleet-gate: nenhum gate no escopo '$SCOPE'"
  exit 0
fi

# Nunca imprimir verde limpo sobre uma verificacao que nao aconteceu: o rotulo e o produto.
if [[ "$MEDICAO_FALHOU" == "1" && ${#MUTANTES[@]} -eq 0 ]]; then
  {
    echo ""
    echo "⚠️  fleet-gate: NAO foi possivel verificar se algum gate mutou a arvore"
    echo "   (repositorio sem commit inicial, ou 'git stash create' indisponivel)."
    echo "   Os gates rodaram; a checagem de integridade NAO. Confira 'git status' a mao."
  } >&2
fi

if [[ ${#MUTANTES[@]} -gt 0 ]]; then
  if [[ "${FLEET_GATE_ALLOW_MUTATION:-0}" == "1" ]]; then
    {
      echo ""
      echo "⚠️  gate [${MUTANTES[*]}] MUTOU a arvore — permitido por FLEET_GATE_ALLOW_MUTATION=1."
      echo "Alterado pelo gate:"
      printf '%s\n' "${MUTACAO_DELTA:-  (delta vazio)}" | sed 's/^/  /'
      echo "Rode 'git status' antes de commitar: pode haver mudanca fora do escopo da issue."
    } >&2
    # Registra o uso do escape: saber com que frequencia ele e acionado e o dado que decide
    # se ele deve continuar existindo (ADR-008).
    fleet_emit fleet.gate --outcome mutacao-permitida --command /engineer:work
  else
    {
      echo ""
      echo "⛔ FLEET GATE BLOQUEOU: o gate [${MUTANTES[*]}] MUTOU a arvore de trabalho."
      echo ""
      echo "Um gate que reescreve o codigo que esta julgando nao e fail-closed: ele pode"
      echo "transformar vermelho em verde escrevendo no arquivo, e deixa mudanca fora do"
      echo "escopo da issue para alguem commitar sem perceber."
      echo ""
      echo "Alterado PELO GATE (delta antes/depois, nao o git status inteiro):"
      printf '%s\n' "${MUTACAO_DELTA:-  (delta vazio: mudanca de conteudo sem mudar o status)}" | sed 's/^/  /' >&2
      echo ""
      echo "Causa tipica: --fix / --write no comando do gate (eslint --fix, prettier --write,"
      echo "ruff --fix, gofmt -w). Aponte o gate para a variante de CHECAGEM:"
      echo "  lint:npm run lint:check     (em vez de  lint:npm run lint  com --fix)"
      echo ""
      echo "Se a mutacao for deliberada: FLEET_GATE_ALLOW_MUTATION=1"
    } >&2
    fleet_emit fleet.gate --outcome fail --command /engineer:work
    exit 2
  fi
fi

if [[ ${#FAILED[@]} -gt 0 ]]; then
  {
    echo ""
    echo "⛔ FLEET GATE BLOQUEOU esta fase: falhou em [${FAILED[*]}]."
    echo "Corrija e rode novamente antes de marcar a task/fase como concluida."
    echo "Logs (com worktree, branch e commit no cabecalho):"
    for _l in "${FAILED[@]}"; do echo "  $(gate_log_path "${_l//\//-}")"; done
  } >&2
  fleet_emit fleet.gate --outcome fail --command /engineer:work
  exit 2
fi

fleet_emit fleet.gate --outcome pass --command /engineer:work
echo "✔ fleet-gate: verde"
exit 0
