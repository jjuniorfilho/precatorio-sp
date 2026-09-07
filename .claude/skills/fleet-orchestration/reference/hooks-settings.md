# Fleet v2 — hooks nao-pulaveis (opt-in, em `.claude/settings.json`)

> **Opt-in por design.** Estes hooks NAO sao ligados por default no `settings.json`
> distribuido pelo Cortex, porque dependem de Agent Teams (feature experimental). Mescle
> o bloco abaixo manualmente no `.claude/settings.json` do seu projeto quando quiser
> garantias nao-pulaveis. Requer Claude Code v2.1.32+ e `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`.

## Como funciona

- **`TaskCompleted`** roda quando uma task/fase vai ser marcada como concluida.
  `exit 2` **impede** a conclusao e devolve o stderr ao agente como feedback.
- **`TeammateIdle`** roda quando um teammate vai ficar ocioso. `exit 2` o **mantem
  trabalhando** (corrigir antes de parar).
- O `fleet-gate.sh` e **fail-closed**: falha de tooling = bloqueio, nao passagem.

## Bloco a mesclar

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "hooks": {
    "TaskCompleted": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.claude/skills/fleet-orchestration/scripts/fleet-gate.sh\""
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"$(git rev-parse --show-toplevel)/.claude/skills/fleet-orchestration/scripts/fleet-gate.sh\""
          }
        ]
      }
    ]
  }
}
```

## Notas de calibracao

- **Escopo por velocidade:** o gate roda os labels de `FLEET_GATE_CMDS` (ou `lint,test`
  no auto-detect). Para feedback rapido, exporte `FLEET_GATE_SCOPE=lint` no ambiente da
  worktree (via `.env.fleet`).
- **Granularidade:** preferir `TaskCompleted` (boundary de fase) a `Stop` (dispara a cada
  resposta) — rodar a suite de testes em todo `Stop` seria caro demais.
- **ADR STRICT (parte LLM):** o `adr-compliance-checker` em modo STRICT roda dentro de
  `/work` e `/pre-pr` (e um agente, nao script). O hook cobre a parte deterministica. As
  duas camadas juntas = garantia de ADR.
- **Teste antes de confiar:** simule um teste vermelho numa worktree e confirme que o
  `TaskCompleted` bloqueia (a task nao fecha) antes de rodar a frota inteira.
