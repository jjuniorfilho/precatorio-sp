---
name: fleet-orchestration
description: >-
  Orquestra worktrees paralelas (uma por issue) dirigindo o workflow de engenharia
  do Cortex (warm-up → start → plan → work → pre-pr → pr) com gates humanos e
  garantias programaticas nao-pulaveis. Use SEMPRE que o usuario pedir para "rodar
  a frota", "tocar varias issues em paralelo", "abrir N worktrees", "orquestrar o
  desenvolvimento paralelo", "/engineer:fleet", ou mencionar provisionar/limpar
  worktrees por issue. Garante funcionalidade, aderencia a ADRs, seguranca, padroes
  e testes via test-engineer, code-reviewer, adr-compliance-checker (STRICT) e os
  agentes branch-*. Stack-agnostico: provisiona infra isolada por worktree via
  config layer (.claude/fleet.config.sh), sem subir uma stack por worktree. Tem dois
  modos: gate-based (`/engineer:fleet`, 3 paradas humanas) e AUTONOMO
  (`/engineer:fleet-autonomous`, "toca do comeco ao PR sem me parar") — use o autonomo
  quando o usuario pedir "rodar 100% autonomo", "modo frota autonomo", "fechar tudo
  sozinho": o lead substitui os gates por verificacao adversarial e so escala nos freios
  (produto · arquitetura nova · irreversivel/producao). Ver reference/autonomous-mode.md.
---

# Fleet Orchestration — Cortex

Provisiona e dirige **N worktrees em paralelo**, uma por issue, sobre o workflow de
engenharia do Cortex. Nao e fire-and-forget: **separa julgamento humano de garantia
programatica** e enfileira cada tipo. O lead aprova em 3 checkpoints uma fila de N
branches; tudo entre os checkpoints e garantido por maquina.

> Decisao arquitetural: ADR-013 (no cortex-framework: `docs/specs/technical/adr/ADR-013-fleet-orchestration.md`).
> Os scripts shell sao **camada de automacao/infra** (como `bin/cli.js`) — nao implementam
> logica de agente. O *como* do pipeline vive aqui (markdown declarativo).

## Configuracao padrao

- **Gate de plano:** `--auto-plan` auto-aprova issues pequenas (≤3 fases, sem nova
  decisao arquitetural, sem mudanca de schema); arquitetura e merge ficam SEMPRE humanos.
- **ADR enforcement:** `adr-compliance-checker` em **modo STRICT** (violacao bloqueia a fase).
- **Host:** iTerm2 + tmux (split-pane do Agent Teams). Requer Claude Code v2.1.32+ e
  `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`. Funciona tambem em modo fila headless. Setup
  passo-a-passo do terminal + settings.json em [`reference/terminal-setup.md`](reference/terminal-setup.md).
- **Stack:** configurada por projeto em `.claude/fleet.config.sh` — ver
  [`reference/configuration.md`](reference/configuration.md). Sem config, usa defaults
  (auto-detect de package manager e de lint/test).

## Pre-condicoes

1. Infra compartilhada de pe, se o projeto precisar (NUNCA uma stack por worktree).
   O que subir e definido pelo projeto na config (`fleet_provision_data`).
2. `tmux` ativo (`echo $TMUX` nao-vazio) se for usar split-pane.
3. `.worktreeinclude` na raiz do repo, se houver arquivos gitignored a copiar (ex.: `.env`).
4. Branch base (`main`) limpa.

## Dois modos: gate-based vs autonomo

Esta skill serve dois comandos. O pipeline, a infra (config layer), o cap de RAM e as 5
garantias sao os MESMOS; muda quem decide entre as fases.

| | `/engineer:fleet` (gate-based) | `/engineer:fleet-autonomous` |
|---|---|---|
| Gate 1 (arquitetura) | ⛔ humano aprova | lead segue; **escala so se detectar decisao arquitetural nova** |
| Gate 2 (plano) | ⛔ humano (`--auto-plan` libera pequenas) | autonomo |
| Qualidade | garantias + relatorios dos agentes | garantias + **verificacao adversarial do lead** (teste do alvo isolado + `/verify` real + diff; nao confia no relatorio) |
| Gate 3 (merge) | ⛔ humano | **default = para no PR**; auto-merge so com `--merge`/GO |
| Freio de mao | (todos os gates sao humanos) | para e escala em **produto · arquitetura nova · irreversivel/producao** |

Mudancas com gate MECANICO proprio (uma checagem no `fleet-gate.sh` + adr STRICT) nao viram
freio humano no modo autonomo. O "como" completo, com o padrao de verificacao adversarial, o
discovery-first e o ciclo de fechamento, esta em
[`reference/autonomous-mode.md`](reference/autonomous-mode.md) + o script
[`scripts/fleet-closeout.sh`](scripts/fleet-closeout.sh).

## Pipeline (3 gates humanos)

Design completo, diagrama e mapa das garantias em [`reference/pipeline.md`](reference/pipeline.md).
Resumo:

| Fase | Tipo | O que roda |
|---|---|---|
| 0 · Provisionamento | autonomo | `scripts/fleet-provision.sh <name> --api-port N` por issue |
| 1 · Discovery+Arquitetura | autonomo → **GATE 1** | `/engineer:warm-up` + `/engineer:start`; humano aprova arquitetura em lote. Artefatos garantidos por `scripts/fleet-phase-gate.sh --phase 1` (exit 2 BLOQUEIA) |
| 2 · Planejamento | autonomo → **GATE 2** | `/engineer:plan`; `--auto-plan` libera pequenas. `scripts/fleet-phase-gate.sh --phase 2` (exit 2 BLOQUEIA) |

O gate de fase exige que os artefatos **existam e estejam commitados**. Existir nao basta: a
sessao nasce dentro da worktree e o teardown remove tudo que nunca virou commit — o gate
passava, a frota entregava, e o rastro morria junto. Exigir o commit aqui, e nao no
fechamento, e o que preserva a ordem: o plano entra no historico antes do primeiro commit de
codigo. Commitado no fim, ele existiria mas DEPOIS do codigo, que e um sinal pior do que a
ausencia (plano retroativo = processo simulado).
| 3 · Implementacao | autonomo + garantias | `/engineer:work` + `test-engineer`/`code-reviewer` + `fleet-gate.sh` (lint/test/custom) + ADR-STRICT |
| 4 · Pre-PR | autonomo | `/engineer:pre-pr` (4 agentes branch-*) |
| 5 · PR | autonomo → **GATE 3** | `/engineer:pr`; merge manual + merge queue |

## Status do Linear (transicao OBRIGATORIA do lead)

O lead — NAO os subagents — mantem o status da issue no Linear sincronizado com a fase.
Esquecer isso ja causou issues ficarem em Backlog enquanto eram implementadas. Checklist:

- **Fase 0/1 (ao soltar os times):** `save_issue(id, state: "In Progress")` para CADA issue
  da onda — inclusive sub-issues criadas no meio. Fazer JUNTO com o provisionamento.
- **Fase 5 (PR aberto):** `In Progress → In Review`.
- **Pos-merge (GATE 3):** `In Review → Done`.
- Rebaixou/cancelou uma issue? Reflita no Linear na hora (priority + state).

## Como invocar

Disparada pelo comando `/engineer:fleet PX-2621 PX-2622 ...` (entrypoint fino) ou
diretamente quando o usuario descreve a intencao.

### Fase 0 — provisionar (por issue)

1. Resolver o slug via Linear (`get_issue`) → nome `<id>-<slug>`; reusar branch de
   `origin` se existir.
2. Atribuir `API_PORT` por offset, se o projeto bootar API (ex.: `3010 + i`).
3. Rodar o script:
   ```bash
   .claude/skills/fleet-orchestration/scripts/fleet-provision.sh px-2621-llm-factory --api-port 3011
   ```
   Cria worktree em `$FLEET_WORKTREE_DIR/<name>`, copia env via `.worktreeinclude`,
   roda a instalacao de deps (auto-detect ou `FLEET_INSTALL_CMD`) e o hook
   `fleet_provision_data` do projeto (ex.: DB isolado). Idempotente; aceita
   `--dry-run`, `--no-db`, `--no-install`.

### Cleanup (pos-merge)

```bash
.claude/skills/fleet-orchestration/scripts/fleet-teardown.sh px-2621-llm-factory --drop-db --delete-branch
```
Recusa remover worktree com mudancas nao-commitadas, salvo `--force`.

Prefira o `fleet-closeout.sh`, que roda a guarda de rastro e preserva a telemetria da
worktree ANTES de chamar este script. O teardown direto e destrutivo e nao verifica nada
disso — a worktree e o unico lugar onde a pasta de sessao e a telemetria da frota existem.

## Registro (auto-evolucao, ADR-008)

**Automatico — nao ha nada para o lead lembrar de escrever.** Tres vias independentes
gravam em `.claude/memory/evolution/command-usage.jsonl`:

| Evento | Quem emite | `outcome` |
|---|---|---|
| `fleet.provision` | `fleet-provision.sh` | `pass` |
| `fleet.phase1` / `fleet.phase2` | `fleet-phase-gate.sh` | `pass` \| `blocked` |
| `fleet.gate` | `fleet-gate.sh` | `pass` \| `fail` |
| `fleet.closeout` | `fleet-closeout.sh` | `pass` |
| `subagent.start` / `subagent.stop` | hooks do harness, com `agent_type` | — |
| o comando em si (`/engineer:start`, …) | `PostToolUse[Skill]`, com `source: "agent"` | — |

A ultima linha existe desde a v3.10.0 e corrige um erro de diagnostico: a v3.9.0 concluiu
que a frota nao produzia evento observavel, porque o hook procurava uma ferramenta chamada
`SlashCommand`. **Ela chama-se `Skill`.** O matcher nunca casava, e a ausencia de dado foi
lida como ausencia de mecanismo — 61 invocacoes reais estavam nos transcripts o tempo todo.

Para essa via funcionar, **invoque cada comando de fase por `Skill(skill="engineer:start")`**,
nao lendo o markdown inline. Executar inline nao deixa rastro e, pela issue #40, tende a sair
parcial. As outras duas vias seguem valendo como rede: elas nao dependem de como o lead
executa. Numa worktree o evento e gravado la, e o passo 4 do close-out traz para o checkout
principal. Detalhe em [ADR-008](../../../docs/specs/technical/adr/ADR-008-auto-evolution-cycle.md).

## Garantias — onde cada uma e enforcada

| Garantia | Enforca em | Como |
|---|---|---|
| Funcionalidade | Fase 3/4 | `test-engineer` + `branch-test-planner` + gate `test` |
| Aderencia a ADRs | Fase 3/4 | `adr-compliance-checker` STRICT + `branch-master-docs-checker` + gate custom |
| Seguranca | Fase 3/4 | `code-reviewer` + `branch-code-reviewer` (CRITICAL bloqueia) |
| Padroes | Fase 3 | `adr-compliance-checker` + `code-reviewer` + gate `lint` |
| Testes | Fase 4 | `branch-test-planner` (+30-40% edge cases) + gate de cobertura |

> **v1 (passos do lead):** as garantias rodam como passos explicitos do lead.
> **v2 (nao-pulavel):** mover para hooks `TaskCompleted`/`TeammateIdle` (`exit 2`) via
> `fleet-gate.sh` — ver [`reference/hooks-settings.md`](reference/hooks-settings.md).
