#!/usr/bin/env bash
#
# _emit.sh — Cortex Fleet · telemetria de PROCESSO (sourced, nao executar)
#
# Por que os scripts emitem, e nao um hook:
#
# Contar comando nao mede frota. Medido em 2026-07-26 sobre 47 entradas nos repos
# px-agents e controladoria: ZERO com source "agent". O teste decisivo foi uma
# frota autonoma real com 5 worktrees que registrou apenas o humano digitando
# `/engineer:fleet-autonomous` — nenhum start, plan ou work de agente. O Cortex e
# prompt-driven (ADR-001): o lead LE o markdown do comando e executa as instrucoes
# inline, sem disparar comando que hook nenhum consiga ver.
#
# Estes scripts, ao contrario, rodam em TODA fronteira de fase, sao deterministicos
# e ja sabem issue, branch e fase. Sao a instrumentacao mais confiavel do processo,
# e a unica que nao depende do que o agente lembra de fazer — o mesmo argumento que
# tirou a telemetria de comando de dentro dos prompts na issue #39.
#
# Emite no root do repositorio ONDE O EVENTO ACONTECEU. Numa worktree isso e a
# propria worktree, e o passo de absorcao do fleet-closeout.sh traz para a main.
#
# Fail-open sempre: telemetria nunca derruba o fluxo de quem esta trabalhando.

fleet_emit() {
  local root hook
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ -n "$root" ]] || return 0
  hook="$root/.claude/scripts/telemetry-hook.py"
  [[ -f "$hook" ]] || return 0
  python3 "$hook" --emit "$@" --cwd "$root" >/dev/null 2>&1 || true
  return 0
}
