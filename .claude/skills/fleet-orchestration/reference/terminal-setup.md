# Fleet — manual de setup e operação (terminal + ondas + checkpoints)

> Como configurar o terminal para rodar o Fleet em **split-pane** (Agent Teams) e como
> **operá-lo**: planejar ondas (o que paralelizar) e fazer checkpoint de sessão para
> continuar depois. Vale para os dois modos: `/engineer:fleet` (gate-based) e
> `/engineer:fleet-autonomous` (autônomo). Referência da skill
> [`fleet-orchestration`](../SKILL.md) (ADR-013). Onboarding humano em docs/guides:
> [`fleet-quickstart.md`](../../../../docs/guides/fleet-quickstart.md).

O Fleet **funciona sem nada disto** — cai no modo fila headless. Este documento é para quem
quer o **split-pane visual** (uma pane por teammate) e as **garantias não-puláveis**.

---

## Mapa rápido

| Você quer... | Precisa de |
|--------------|-----------|
| Rodar a frota em fila (headless) | nada além do repo git |
| Split-pane visual (uma pane por agente) | iTerm2 + tmux + Claude Code v2.1.32+ + `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` |
| Garantias **não-puláveis** (modo autônomo) | tudo acima **+** hooks `TaskCompleted`/`TeammateIdle` no settings.json |

A infra é **idêntica** nos dois modos (mesmos scripts, mesmo cap de RAM, mesmas 5 garantias).
O que muda é **quem decide entre as fases** — ver [`pipeline.md`](pipeline.md) e
[`autonomous-mode.md`](autonomous-mode.md).

---

## Passo 0 — Verificar o ambiente

Rode este bloco **antes de configurar nada**. Ele diz o que falta e qual é o seu cap de agentes.

```bash
# Claude Code — precisa ser >= 2.1.32
claude --version

# tmux instalado?
tmux -V || echo "instale: brew install tmux"

# iTerm2 instalado? (pode estar em /Applications ou ~/Applications)
mdfind "kMDItemCFBundleIdentifier == 'com.googlecode.iterm2'" | head -1 \
  || echo "instale: brew install --cask iterm2"

# Está DENTRO de uma sessão tmux? (precondição do split-pane)
[ -n "$TMUX" ] && echo "tmux: ATIVO" || echo "tmux: fora de sessão — rode 'tmux'"

# Agent Teams ligado?
echo "AGENT_TEAMS=${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-<não setado>}"

# RAM → cap de agentes vivos = floor((RAM_GB - 10) / 2.5)
RAM_GB=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
echo "RAM: ${RAM_GB} GB → cap agentes: $(( (RAM_GB - 10) * 10 / 25 )) (use conservador 4 em 24 GB)"
```

**Referência de cap por RAM** (agentes **vivos**, não worktrees):

| RAM | Cap teórico `floor((RAM-10)/2.5)` | Recomendado | O que serializa |
|-----|-----------------------------------|-------------|-----------------|
| 16 GB | 2 | 2 | Fases 3 e 4 uma worktree por vez |
| 24 GB | 5 | **4** | pre-PR 1 worktree/vez; nunca misturar impl (fg) e branch-* (bg) |
| 32 GB | 8 | 6–8 | folga para 2–3 worktrees em impl simultânea |
| 64 GB+ | 21+ | teto por bom senso | limitado por I/O antes de RAM |

O cap se aplica a **agentes vivos**, não a worktrees. Ajuste com `--max-agents N`.

---

## Passo 1 — iTerm2 + tmux

### 1.1 Instalar

```bash
brew install --cask iterm2   # se ainda não tiver
brew install tmux            # 3.x
```

> Se o iTerm2 estiver em `~/Applications`, funciona igual — só garanta que é ele que você abre
> para rodar a frota (o Terminal.app padrão do macOS também serve, mas o iTerm2 lida melhor com
> panes e cores do Agent Teams).

### 1.2 Config mínima de tmux (opcional, recomendado)

Crie/edite `~/.tmux.conf` — melhora navegação entre panes e scrollback do split-pane:

```tmux
set -g mouse on                 # clicar/rolar entre panes
set -g history-limit 50000      # scrollback longo (logs dos teammates)
set -g default-terminal "tmux-256color"
setw -g aggressive-resize on    # panes reflow ao redimensionar a janela
```

Recarregue: `tmux source-file ~/.tmux.conf` (ou reabra a sessão).

### 1.3 Entrar numa sessão tmux

O split-pane **só aparece se o `claude` for lançado de dentro do tmux**:

```bash
tmux new -s fleet     # cria a sessão "fleet"
# (dentro dela)
cd ~/seu-projeto
claude                # agora a frota pode abrir panes por teammate
```

Reconectar depois: `tmux attach -t fleet`.

---

## Passo 2 — Ligar o Agent Teams

O split-pane depende de `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (feature experimental).
Três lugares possíveis — escolha **um**:

| Onde | Como | Quando usar |
|------|------|-------------|
| **settings.json** (recomendado) | bloco `"env"` (Passo 3) | liga para todo projeto/usuário; declarativo e versionável |
| **shell** | `export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` no `~/.zshrc` | liga global na sua máquina, fora do repo |
| **inline** | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 claude` | teste pontual, uma sessão só |

Confirme depois de setar: `echo $CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` deve imprimir `1`.

---

## Passo 3 — `settings.json` base (modo frota)

Bloco mínimo para o **split-pane** e a autonomia que a frota espera. Mescle no
`.claude/settings.json` do projeto (ou no `~/.claude/settings.json` global):

```json
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "defaultMode": "acceptEdits",
  "permissions": {
    "allow": [
      "Bash(git worktree:*)",
      "Bash(git checkout:*)",
      "Bash(git branch:*)"
    ],
    "deny": [
      "Bash(git push --force:*)",
      "Bash(git push -f:*)",
      "Bash(git reset --hard:*)",
      "Bash(rm -rf /:*)",
      "Bash(docker system prune:*)"
    ]
  }
}
```

- **`env`** liga o Agent Teams (Passo 2, opção declarativa).
- **`defaultMode: acceptEdits`** dá à frota a autonomia de editar sem prompt a cada arquivo.
- **`git worktree:*` no allow** evita prompt de permissão a cada provisionamento.
- **`deny`** é o **freio de mão mecânico** do modo autônomo: ações irreversíveis (force
  push, reset hard, prune) ficam bloqueadas por política, não por julgamento. Um `deny` bem
  calibrado é o que torna o modo autônomo seguro.

### 🔒 Segurança — NUNCA hardcode secrets no settings.json

Se você configura MCP servers (GitHub, Context7, etc.) com token, **não** coloque o valor
literal no JSON — ele acaba em backup, dotfiles repo ou screen-share. Use expansão `${VAR}`:

```json
{
  "mcpServers": {
    "github": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-github"],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "${GITHUB_PAT}"
      }
    }
  }
}
```

E o valor real fica fora do JSON, no seu shell:

```bash
# ~/.zshrc
export GITHUB_PAT="ghp_..."     # ou puxe do keychain: $(security find-generic-password ...)
```

> Se um token já foi commitado/exposto alguma vez, **rotacione-o** (revogar + gerar novo) —
> mover para `${VAR}` não desfaz uma exposição passada.

---

## Passo 4 — Hooks não-puláveis (reforço do modo autônomo)

No modo autônomo as garantias precisam ser **não-puláveis**. Os hooks abaixo fazem o
`fleet-gate.sh` rodar (lint/test/custom) e **bloquear** (`exit 2`) quando uma task/fase vai
fechar vermelha. **Opt-in** — não vem ligado por default (depende de Agent Teams).

```json
{
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

- **`TaskCompleted`** roda ao fechar uma fase; `exit 2` **impede** a conclusão e devolve o
  stderr ao agente como feedback.
- **`TeammateIdle`** roda quando um teammate vai ficar ocioso; `exit 2` o **mantém
  trabalhando** (corrigir antes de parar).
- O `fleet-gate.sh` é **fail-closed**: falha de tooling = bloqueio, não passagem.

Bloco canônico e notas de calibração: [`hooks-settings.md`](hooks-settings.md).

---

## Passo 5 — Config layer por projeto (opcional)

Sem config, o Fleet usa **defaults** (auto-detect de package manager e de `lint`/`test`).
Para customizar instalação de deps, isolamento de dados ou gates:

```bash
cp .claude/skills/fleet-orchestration/fleet.config.example.sh .claude/fleet.config.sh
# edite FLEET_INSTALL_CMD, FLEET_GATE_CMDS, fleet_provision_data, fleet_teardown_data...
```

Arquivos gitignored que cada worktree precisa (ex.: `.env`) — liste em `.worktreeinclude`
na raiz do repo (uma path por linha):

```
.env
config/local.json
```

Detalhes de cada variável/hook: [`configuration.md`](configuration.md).

---

## Passo 6 — Validar antes de confiar

```bash
# smoke test dos scripts (zero dependência externa)
bash .claude/skills/fleet-orchestration/scripts/smoke-test.sh

# provisionamento em dry-run (nada é executado de verdade)
.claude/skills/fleet-orchestration/scripts/fleet-provision.sh demo --dry-run

# confirmar que o gate BLOQUEIA com teste vermelho (deve sair exit 2)
FLEET_GATE_SCOPE=test .claude/skills/fleet-orchestration/scripts/fleet-gate.sh; echo "exit=$?"
```

Se ligou os hooks do Passo 4: simule um teste vermelho numa worktree e confirme que o
`TaskCompleted` **não deixa a task fechar** — antes de rodar a frota inteira.

---

## Passo 7 — Rodar

```bash
# GATE-BASED — 3 paradas humanas (arquitetura · plano · merge)
/engineer:fleet PX-2621 PX-2622 PX-2627
/engineer:fleet PX-2621 --auto-plan        # auto-aprova plano de issues pequenas

# AUTÔNOMO — conduz até o PR sem gates; lead faz verificação adversarial
/engineer:fleet-autonomous PX-2621 PX-2622  # default: PARA no PR aberto
/engineer:fleet-autonomous PX-2621 --merge  # libera auto-merge + fechamento
/engineer:fleet-autonomous PX-2621 --max-agents 4   # respeita o cap de RAM
```

| | `/engineer:fleet` | `/engineer:fleet-autonomous` |
|---|---|---|
| Gate 1 (arquitetura) | ⛔ humano aprova | segue; escala só se detectar decisão arquitetural nova |
| Gate 2 (plano) | ⛔ humano (`--auto-plan` libera pequenas) | autônomo |
| Qualidade | relatórios dos agentes | **verificação adversarial do lead** (teste do alvo isolado + `/verify` real + diff) |
| Gate 3 (merge) | ⛔ humano | default = **para no PR**; auto-merge só com `--merge`/GO |
| Freio de mão | (todos os gates são humanos) | para em **produto · arquitetura nova · irreversível/produção** |

---

## Passo 8 — Planejar ondas: o que paralelizar

Antes de lançar a frota, o lead analisa o conjunto de issues e as agrupa em **ondas**. A
regra que decide tudo: **duas issues na MESMA onda não podem tocar o mesmo arquivo, boundary
ou schema.** Quem colide vai para ondas diferentes, ou faz **merge serial** (rebase entre os
merges). É a análise que você pede com *"quais dessas issues dá pra rodar em paralelo?"* — a
saída é um plano de ondas + colisões + ordem de merge.

**Como o lead monta as ondas:**

1. **Independência de arquivos (o corte principal).** Para cada issue, estimar quais
   arquivos/módulos ela toca. Issues com interseção vazia → mesma onda. Interseção não-vazia
   → ondas separadas ou merge serial. Verificar contra o **código real**, não confiar no
   "pronto" da issue — já aconteceu de uma wave aprovada ser **revogada por colisão** quando
   só 1 de 4 issues "prontas" estava de fato coberta.
2. **Dependência (contract-first).** A issue que produz o contrato/fundação (schema, tipo
   compartilhado, endpoint) vai numa onda **anterior**; as dependentes empilham (stacked
   branch) ou entram na onda seguinte. Nunca paralelizar o consumidor com o produtor do
   contrato.
3. **Migrations com timestamps distintos.** Pré-atribuir timestamps **diferentes** às
   migrations de cada worktree ANTES de lançar (ex.: `140000`/`140100`/`140200`) — os agentes
   propõem o mesmo timestamp se não orientados, e isso quebra a ordenação.
4. **`prisma generate` (ou gerador equivalente) serializado por worktree.** Um `generate` de
   uma worktree sobrescreve o cliente compartilhado em `node_modules` — rodar serializado, não
   em paralelo, para não uma worktree ver tipos que a outra criou.
5. **Cap de agentes por RAM.** Mesmo issues independentes só rodam de fato em paralelo até o
   teto `floor((RAM_GB-10)/2.5)` (Passo 0). Acima disso, a onda serializa sozinha.

> Colisão de arquivo entre issues da mesma onda **não impede** paralelizar a implementação —
> impede o **merge simultâneo**. O padrão é: implementa em paralelo, **mergeia em série** com
> rebase entre um PR e o próximo.

---

## Passo 9 — Checkpoint de sessão: pausar e retomar a frota

No fim de uma frota, ou de uma sessão muito longa, gere um **checkpoint** — um doc de sessão
que congela o estado para a frota **continuar depois** exatamente de onde parou. É o que você
pede com *"faz um checkpoint pra continuar amanhã"*. O `warm-up` da próxima sessão lê os
`sessions/` e retoma sem re-descobrir nada.

**Onde:** `.claude/memory/sessions/AAAA-MM-DD-fleet-<id>-checkpoint.md` (e
`...-concluida.md` quando a onda fecha de vez).

**Estrutura (validada em produção no px-agents):**

```markdown
# Checkpoint — frota <ID> (<nome>), pausa a pedido do <humano>

## Estado (<data>, ~<hora>)
<1 parágrafo: o que está ENTREGUE/VERIFICADO/pushado e o que ainda não>

| Branch | Estado |
|---|---|
| <branch> (HEAD <sha>) | <o que foi feito + gotchas> |

## e2e / integração (se houver, em curso/PAUSADO)
- Worktree, porta, DB isolado, `.env.*`, seeds, credenciais (onde estão)
- **BLOQUEIO da pausa**: o que travou, o que foi morto (processos), o que falta

## Passos da retomada
1. <comando exato para re-subir o ambiente>
2. <próximo passo com comando>
...

## Watchouts
- <gotchas que mordem na retomada>
```

**Por que cada bloco importa:**

- **Tabela Branch|Estado com o HEAD commit** — a próxima sessão sabe exatamente em que commit
  cada worktree parou (não confiar em `git status` de agente idle, que fica STALE).
- **Estado do e2e (portas/DB/env/credenciais)** — retomar verificação real exige re-subir o
  MESMO ambiente isolado; sem isso, você re-descobre portas e re-seeda do zero.
- **Passos da retomada com comandos** — transformam "continuar a frota" num replay, não numa
  re-investigação.
- **Watchouts** — instabilidades e dívidas que já morderam ficam avisadas (ex.: subagents que
  caem e voltam com `SendMessage`; dívida ambiental resolvida só numa branch).

> Regra: o checkpoint é **do lead**, não dos subagents. Processos de run longo/pago são do
> lead (sobrevivem a turnos); ao pausar, o lead mata o que está rodando e registra no bloco de
> bloqueio o que precisa voltar.

---

## Troubleshooting

| Sintoma | Causa provável | Solução |
|---------|----------------|---------|
| Frota não abre panes, roda em fila | `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` não setado, ou `claude` lançado fora do tmux | Passo 2 + `tmux new -s fleet` antes do `claude` |
| Split-pane some ao redimensionar | tmux sem `aggressive-resize` | adicione a config do Passo 1.2 |
| Máquina engasga com N worktrees | cap de RAM estourado (agentes vivos) | `--max-agents 4` (24 GB); serialize pre-PR |
| Gate sai 0 mas "nenhum gate detectado" | sem `package.json` com `lint`/`test` e sem `FLEET_GATE_CMDS` | defina `FLEET_GATE_CMDS` em `fleet.config.sh` |
| `FLEET_GATE_CMDS=(...) fleet-gate.sh` não tem efeito | arrays bash não passam por prefixo de env | declare em `.claude/fleet.config.sh` (sourced) |
| `teardown` recusa remover worktree | mudanças não-commitadas (guard de segurança) | commite/descarte, ou use `--force` |
| Token de MCP vazando em backup | secret hardcoded no settings.json | Passo 3 §Segurança — mova para `${VAR}` e **rotacione** |

---

## Referências

- [`fleet-quickstart.md`](../../../../docs/guides/fleet-quickstart.md) — onboarding do comando e uso
- [`../SKILL.md`](../SKILL.md) — capacidade, garantias, cap de RAM
- [`pipeline.md`](pipeline.md) — design dos 3 gates + diagrama
- [`autonomous-mode.md`](autonomous-mode.md) — verificação adversarial + freio de mão
- [`hooks-settings.md`](hooks-settings.md) — hooks não-puláveis (opt-in)
- [`configuration.md`](configuration.md) — config layer stack-agnóstica
- [ADR-013](../../../../docs/specs/technical/adr/ADR-013-fleet-orchestration.md) — decisão arquitetural
