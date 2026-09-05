# Engineer Fleet

Orquestra worktrees paralelas, uma por issue, sobre o workflow de engenharia do Cortex.

<arguments>
#$ARGUMENTS
</arguments>

Argumentos: IDs de issue do Linear (ex.: `PX-2621 PX-2622 PX-2627`) e flags opcionais
`--auto-plan`, `--max N`, `--dry-run`.

## Acao

Use a skill **`fleet-orchestration`** para conduzir todo o pipeline. A skill carrega o
procedimento completo, os scripts de provisionamento/gate/teardown, a config layer e o
design dos gates. Decisao arquitetural: ADR-013.

Passos de alto nivel (detalhe em `.claude/skills/fleet-orchestration/`):

1. **Fase 0** — para cada issue, resolver o slug via Linear e rodar
   `.claude/skills/fleet-orchestration/scripts/fleet-provision.sh <name> --api-port <base+i>`.
   Transicionar a issue para **In Progress** no Linear (lead, nao subagents).
2. **Fase 1** — `/engineer:warm-up` + `/engineer:start` em cada worktree →
   ⛔ **GATE 1**: aguardar aprovacao humana das arquiteturas (em lote).
3. **Fase 2** — `/engineer:plan` → ⛔ **GATE 2** (`--auto-plan` libera pequenas).
4. **Fase 3** — `/engineer:work` por fase + garantias: `test-engineer` + `code-reviewer`
   + `fleet-gate.sh` (lint/test/custom) + `adr-compliance-checker` STRICT.
5. **Fase 4** — `/engineer:pre-pr` (4 agentes branch-*).
6. **Fase 5** — `/engineer:pr` → transicionar **In Review** → ⛔ **GATE 3**: merge manual
   + merge queue → **Done**.

## Pre-requisitos

- Stack configurada em `.claude/fleet.config.sh` se o projeto precisar de deps/dados
  isolados especificos (senao usa defaults). Ver `reference/configuration.md`.
- Para split-pane: iTerm2 + tmux, Claude Code v2.1.32+ e `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

Telemetria nao se registra por instrucao aqui. Tres vias automaticas cobrem a onda: os
scripts do Fleet emitem o evento de cada fronteira de fase via `telemetry-hook.py --emit`
(`fleet.provision`, `fleet.phase1`, `fleet.phase2`, `fleet.gate`, `fleet.closeout`); o hook
captura o comando que o humano digita; e `PostToolUse[Skill]` captura o comando que o
**agente** executa. Para a terceira funcionar, invoque cada comando de fase pela ferramenta
`Skill` — `Skill(skill="engineer:start")` — e nao lendo o markdown inline. Ver ADR-008.
