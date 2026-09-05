---
name: memory-manager
description: "Manage persistent memory layers in .claude/memory/. Use this skill for organizing, pruning, or restructuring project memory files — including distillation of sessions into curated knowledge, decay scanning for stale entries, learning consolidation from sub-agents, conflict detection, and full memory audits."
---

# Memory Manager — Persistent Memory Skill

## ⛔ Bloco HANDOFF — nunca editar

O `MEMORY.md` pode conter um bloco delimitado assim:

```
<!-- HANDOFF:START — gerado por /engineer:handoff, nao editar a mao -->
...
<!-- HANDOFF:END -->
```

Regras **absolutas** para qualquer operação desta skill (destilação, decay scan, consolidação,
reorganização):

1. **Nunca** editar, reescrever, resumir ou remover o conteúdo entre os marcadores.
2. **Nunca** contar essas linhas no limite de 200 linhas do `MEMORY.md` — o limite vale para o
   corpo curado, não para o ponteiro.
3. Ao reescrever o arquivo, preservar o bloco **na íntegra e na posição em que está** (topo).

Motivo: o bloco é o ponteiro para o handoff vivo, e é como o `/engineer:warm-up` encontra o
arquivo. Ele é escrito mecanicamente pelo `handoff-commit.sh` justamente porque a etapa do
ponteiro é a que sempre escapa quando depende de alguém lembrar. Uma destilação que o apague
recria o defeito que o comando existe para eliminar — e o apagaria de forma silenciosa, que é
a pior maneira.

## Visão Geral

Esta skill fornece o conhecimento operacional para gerenciar a memória persistente do projeto em `.claude/memory/`. A memória é organizada em 3 camadas com ciclo de vida definido.

## Arquitetura de 3 Camadas

```
.claude/memory/
├── MEMORY.md                    # CAMADA 3: Conhecimento curado (max 200 linhas)
│                                # Destilado periodicamente das camadas 1 e 2
│                                # Carregado em TODA sessão
│
├── sessions/                    # CAMADA 1: Registros brutos de sessão
│   └── YYYY-MM-DD-slug.md      # Auto-gerado ao final de /work, /pre-pr, etc.
│                                # Max 200 linhas por arquivo
│
├── patterns/                    # CAMADA 2: Padrões detectados
│   ├── decisions.md             # Decisões técnicas recorrentes + justificativas
│   ├── errors.md                # Erros encontrados + soluções aplicadas
│   ├── preferences.md           # Preferências do usuário/equipe detectadas
│   └── agent-learnings.md       # Learning summaries dos sub-agentes
│
└── evolution/                   # Dados para auto-evolução (ADR-008)
    ├── command-usage.jsonl      # Uso de comandos (uma entrada por linha, append O(1))
    ├── command-usage.json       # Legado v2.0 (array) — historico congelado, so leitura
    ├── agent-performance.md     # Performance qualitativa dos agentes
    ├── suggestions.md           # Histórico de propostas (aprovadas/rejeitadas/adiadas)
    └── applied.md               # Registro de mudanças aplicadas
```

## Operações Suportadas

### 1. Destilação (Distillation)

Analisar sessões recentes e promover padrões recorrentes para MEMORY.md.

**Quando executar**: Periodicamente (semanal) ou quando MEMORY.md está desatualizado.

**Pré-condições (não-negociáveis)**:

**a. Sincronizar o checkout antes de ler qualquer sessão.** Sessões vivem em branches até o merge. Destilar de um checkout desatualizado só enxerga as já mergeadas e produz uma rodada incompleta **sem nenhum sinal de erro**.

```bash
git fetch origin <branch-de-integracao> && git status
```

Se o checkout estiver atrás, sincronizar **antes** de prosseguir. Falha real registrada: uma rodada destilou 17 sessões locais; o `pull` seguinte trouxe +12 do mesmo período, escritas por 2 devs em paralelo. O range real era 29 — a rodada cobriu 59% e se declarou completa.

**b. Determinar o range pelo footer, nunca por janela de tempo.** Ler `Última destilação: YYYY-MM-DD` no footer do `MEMORY.md` e destilar **tudo desde essa data**. Se o footer não existir (primeira rodada), destilar tudo que houver em `sessions/`.

Janela fixa perde sessões em silêncio: se a destilação não roda por 3 semanas, o que ficou entre 8 e 21 dias atrás nunca entra em rodada nenhuma. O footer é a única fonte de verdade do ponto de corte — e é o que o `/work` usa para avisar quando há 5+ pendentes.

**Processo**:
1. Ler as sessões em `sessions/` **desde a data da última destilação** (ver pré-condição b)
2. Ler todos os arquivos de padrões em `patterns/`
3. Identificar padrões recorrentes:
   - Decisões feitas 2+ vezes → candidato para MEMORY.md
   - Erros encontrados 2+ vezes → candidato para MEMORY.md
   - Preferências consistentes em 3+ sessões → alta confiança
4. Pontuar cada candidato (mesma escala da self-evolution):
   - **ALTA** (5+ sessões): Padrão confirmado, evidência forte
   - **MÉDIA** (3-4 sessões): Padrão emergente, evidência moderada
   - **BAIXA** (1-2 sessões): Observação inicial, apenas monitorar
5. Propor atualizações ao MEMORY.md
6. Aplicar mudanças aprovadas

### 2. Decay Scan

Identificar e remover memórias obsoletas.

**Regras de decay**:
| Condição | Status | Ação |
|----------|--------|------|
| Referenciado nos últimos 30 dias | ACTIVE | Manter |
| Sem referência há 30-89 dias | STALE | Marcar como `[STALE]` |
| Sem referência há 90+ dias | EXPIRED | Propor remoção |
| Vinculado a ADR | PERMANENT | Nunca decai |

### 3. Consolidação de Learnings

Processar `agent-learnings.md` para extrair insights acionáveis.

**Processo**:
1. Agrupar learnings relacionados por tópico
2. Mesclar duplicatas em entradas consolidadas
3. Identificar learnings que qualificam para promoção ao MEMORY.md (confiança ALTA)
4. Atualizar `agent-learnings.md` com entradas consolidadas

### 4. Detecção de Conflitos

Encontrar contradições entre arquivos de memória e estado atual do projeto.

**Verificar contra**:
- Estrutura atual do projeto (via Glob/Grep)
- ADRs em `docs/specs/technical/adr/`
- CLAUDE.md e critical-rules.md

### 5. Auditoria (Audit)

Health check completo combinando todas as operações:
1. Executar Decay Scan
2. Executar Detecção de Conflitos
3. Verificar tamanhos (MEMORY.md < 200 linhas, sessões < 200 linhas cada)
4. Contar entradas por camada
5. Gerar relatório

## Templates de Arquivo

### Template de Sessão (`sessions/YYYY-MM-DD-slug.md`)

```markdown
# Sessão YYYY-MM-DD — [slug]

## Comando: /[comando]
## Feature: [nome da feature]
## Branch: [nome do branch]

## Resumo
[1-3 parágrafos do que foi feito]

## Decisões Tomadas
- [decisão — justificativa]

## Problemas Encontrados
- [problema → solução aplicada]

## Learning Summaries (sub-agents)
- [agente]: [resumo]

## Próximos Passos
- [ação pendente]

## Confiança: alta | média | baixa
```

### Template de MEMORY.md

```markdown
# Project Memory

> Conhecimento curado de sessões anteriores.
> Max 200 linhas. Destilado periodicamente.

## Padrões Arquiteturais
- [padrão confirmado — fonte: N sessões]

## Preferências da Equipe
- [preferência confirmada — fonte: N sessões]

## Erros Conhecidos
- [erro → solução — fonte: N ocorrências]

## Decisões Técnicas
- [decisão — justificativa — ADR: se aplicável]

---
Última destilação: YYYY-MM-DD
Sessões analisadas: N
Entradas ativas: N | Stale: N | Permanentes: N
```

Para schemas detalhados e exemplos de destilação, consulte: `references/memory-schema.md`

## Anti-Patterns

- **Salvar contexto de sessão específica** — Memória deve conter padrões estáveis, não detalhes temporários
- **Duplicar conteúdo do CLAUDE.md** — Memória complementa, não repete, configuração do projeto
- **Salvar conclusões não verificadas** — Apenas persistir padrões confirmados em 2+ sessões
- **Exceder limite do MEMORY.md** — Manter abaixo de 200 linhas; overflow vai para patterns/
- **Decair decisões vinculadas a ADR** — Decisões ADR são permanentes e nunca expiram
