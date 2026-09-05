# Engineer Fleet — Autonomo

Orquestra worktrees paralelas, uma por issue, do comeco ao PR **sem os gates humanos de
arquitetura e plano**. No lugar deles, o lead faz **verificacao adversarial** e so escala ao
humano nas tres classes de freio (produto · arquitetura nova · irreversivel/producao).

<arguments>
#$ARGUMENTS
</arguments>

Argumentos: IDs de issue do Linear (ex.: `PX-2621 PX-2622 PX-2627`) e flags opcionais
`--merge` (libera auto-merge + fechamento; SEM ela para no PR aberto), `--max N`,
`--max-agents N` (teto de AGENTES vivos; default `floor((RAM_GB-10)/2.5)`, conservador 4),
`--dry-run`.

> ⚠️ **Default = ATE O PR.** Sem `--merge` (ou GO explicito do humano na conversa), o comando
> entrega os PRs abertos e PARA. O merge remoto e o ultimo ponto barato de controle humano.

> ⚠️ **Cap de RAM (agentes vivos) e OBRIGATORIO.** Em 24 GB o teto e 4 agentes → pre-PR roda
> 1 worktree por vez; Fase 3 e Fase 4 sao serializadas. Ver `SKILL.md §Cap de concorrencia`.

## Acao

Use a skill **`fleet-orchestration`** em **modo autonomo**. Leia
`.claude/skills/fleet-orchestration/reference/autonomous-mode.md` (o "como" deste modo) alem
do `pipeline.md` (infra, 5 garantias, RAM). Decisao arquitetural: ADR-013 (+ adendo do modo
autonomo).

> ⚠️ **Invoque cada comando de fase pela ferramenta `Skill`** — `Skill(skill="engineer:start")`
> — em vez de ler o markdown do comando e executar inline. Duas razoes, ambas medidas:
>
> 1. **A execucao inline sai parcial.** A issue #40 mediu `architecture.md` presente em 0/6
>    PRs de frota contra 4/4 no fluxo manual, com o `start.md` byte-a-byte identico. Ler um
>    comando longo e executa-lo inline, com a janela ja carregada da orquestracao, e o mesmo
>    mecanismo que fazia o Memory Flush ser pulado no fim do `/work`.
> 2. **So a invocacao deixa rastro.** `PostToolUse[Skill]` registra o comando com
>    `source: "agent"`; o markdown lido inline nao produz evento nenhum. Sem isso a cadeia
>    start > plan > work > pre-pr > pr fica inauditavel no modo autonomo, que e justamente o
>    modo que roda em escala e sem gate humano.

Passos de alto nivel:

1. **Fase 0** — resolver o slug via Linear + `fleet-provision.sh <name> --api-port <base+i>`
   por issue. `save_issue(id, "In Progress")` para cada uma ao soltar.
2. **Fases 1-2 (autonomas, SEM Gate 1/Gate 2)** — `/engineer:warm-up` + `/engineer:start` +
   `/engineer:plan`. Ao detectar **decisao de produto** ou **nova decisao arquitetural**,
   PARAR aquela issue e escalar ao humano (freio de mao).

   **Gate de artefatos (nao-pulavel, issue #40)** — o autonomo dispensa os GATES HUMANOS,
   nunca os ARTEFATOS. Rodar por worktree, exit 2 BLOQUEIA o avanco:

   ```bash
   scripts/fleet-phase-gate.sh --phase 1   # apos /start:  context.md + architecture.md
   scripts/fleet-phase-gate.sh --phase 2   # apos /plan:   + plan.md
   ```

   Se bloquear, **voltar ao comando da fase e completar** — nunca seguir para a Fase 3.
   Medido em producao: `architecture.md` presente em 0/6 PRs de frota contra 4/4 no fluxo
   manual, com o `start.md` identico. Sem ele a Verificacao Cruzada de Consistencia (marcada
   OBRIGATORIA no `start.md`) nao roda, e o freio de "nova decisao arquitetural" — que e o
   racional do Gate 1 preservado — passa a operar sem o insumo que o fundamenta.
3. **Fase 3** — `/engineer:work` por fase + garantias nao-pulaveis: `fleet-gate.sh`
   (lint/test/custom) + `adr-compliance-checker` STRICT + `code-reviewer`.
4. **Fase 4** — `/engineer:pre-pr` (4 branch-*, 1 worktree por vez).
5. **VERIFICACAO ADVERSARIAL DO LEAD** (substitui o gate de qualidade): rode o teste do ALVO
   tocado isolado + leia o diff + **exercite o comportamento real com evidencia** (via
   `/verify`). Nao confiar no relatorio do subagent; se ele nao formalizar, verificar direto.
6. **Fase 5** — `/engineer:pr` → **abre o PR** e `In Review` no tracker. **PARA aqui** salvo
   `--merge`/GO.
7. **Fechamento** (so com `--merge`/GO) — `scripts/fleet-closeout.sh <name> <pr#> --drop-db
   --delete-branch` (merge serial em colisao de arquivo) → tracker `Done` → docs.

Telemetria nao se registra por instrucao aqui: os proprios scripts do Fleet emitem o evento
de cada fronteira de fase via `telemetry-hook.py --emit`, e os hooks `SubagentStart`/
`SubagentStop` registram cada agente que a onda abre. Ver ADR-008.
