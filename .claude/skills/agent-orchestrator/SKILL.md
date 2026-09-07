---
name: agent-orchestrator
description: "Orchestrate multi-agent workflows for commands. Use this skill when designing new commands that invoke multiple agents, choosing between parallel vs sequential execution, implementing feedback loops, and consolidating results with Learning Summaries."
---

# Agent Orchestrator — Multi-Agent Workflow Skill

## Visão Geral

Esta skill fornece templates operacionais para criar e manter comandos multi-agente no Cortex Framework. Cada comando que invoca 2+ agentes deve seguir os padrões aqui definidos.

## Padrões de Execução

### 1. Paralelo — Agentes Independentes

Quando os agentes NÃO dependem do output um do outro.

```markdown
## Orquestração Multi-Agente

Invoque os N agentes abaixo **em paralelo**:

1. Invoque o agente `agente-a` para [tarefa A]
2. Invoque o agente `agente-b` para [tarefa B]
3. Invoque o agente `agente-c` para [tarefa C]

### Learning Summary Format

Instrua cada agente a incluir ao final do seu output:

## Learning Summary
- **Padrões detectados**: [...]
- **Decisões tomadas**: [...]
- **Warnings**: [...]
- **Sugestão para memória**: [...]
```

**Quando usar**: Review, validação, análise independente (ex: /pre-pr com 4 agentes).

### 2. Sequencial — Agentes com Dependência

Quando o output do agente anterior alimenta o próximo.

```markdown
## Validação Multi-Agente

### Passo 1: Invocar [agente-a]
[tarefa do agente A — produz output X]

### Passo 2: Invocar [agente-b]
[tarefa do agente B — usa output X como input]

### Passo 3: Feedback Loop (max N iterações)
- Se [agente-b] encontra issues CRÍTICAS:
  1. Corrigir as issues
  2. Re-invocar [agente-a] para validar correções
  3. Re-invocar [agente-b] para confirmar resolução
  4. Máximo N loops — após N iterações, reportar ao usuário
- Se apenas issues MAJOR/MINOR: Reportar ao usuário sem loop
```

**Quando usar**: Implementação + testes + review (ex: /work com test-engineer → code-reviewer).

### 3. Condicional — Agentes Baseados em Contexto

Quando a invocação depende de condições do projeto.

```markdown
## Agentes Condicionais

### Verificação de Contexto
- Se [condição A]: Invocar `agente-x` para [tarefa]
- Se [condição B]: Invocar `agente-y` para [tarefa]
- Sempre: Invocar `agente-z` para [tarefa base]
```

**Quando usar**: Comandos que se adaptam ao contexto (ex: /collect invocando agentes diferentes baseado no tipo de coleta).

## Learning Summary — Formato Obrigatório

Todo agente invocado em orquestração multi-agente DEVE produzir um Learning Summary com 4 campos:

```markdown
## Learning Summary
- **Padrões detectados**: [padrões arquiteturais ou de código encontrados]
- **Decisões tomadas**: [escolhas feitas e justificativas]
- **Warnings**: [riscos ou problemas potenciais identificados]
- **Sugestão para memória**: [1-2 frases para persistir em .claude/memory/patterns/]
```

**Regras**:
- Cada agente produz seu próprio Learning Summary
- O orquestrador consolida todos os summaries após recebê-los
- Padrões recorrentes (já apareceram em sessões anteriores) marcados com `[RECORRENTE]`
- Summaries consolidados são persistidos em `.claude/memory/patterns/agent-learnings.md`

## Feedback Loop — Threshold e Limites

### Classificação de Issues

| Severidade | Definição | Ação |
|-----------|-----------|------|
| CRÍTICA | Bugs, segurança, quebra de contrato | Loop automático (corrigir + re-validar) |
| MAJOR | Design, performance, manutenibilidade | Reportar ao usuário (ele decide) |
| MINOR | Estilo, sugestões, melhorias opcionais | Reportar ao usuário (baixa prioridade) |

### Limite de Iterações

- **Máximo 2 loops** de feedback (implementar → revisar → corrigir → re-revisar)
- Após 2 iterações, issues restantes são reportadas ao usuário para decisão manual
- NUNCA fazer loop infinito

## Consolidação de Resultados

Após receber outputs de todos os agentes:

```markdown
## Relatório Multi-Agente — [Comando] — [Contexto]

### [agente-a]
- Resultado: [resumo]
- Issues: [N] CRÍTICAS, [N] MAJOR, [N] MINOR

### [agente-b]
- Resultado: [resumo]
- Issues: [N] CRÍTICAS, [N] MAJOR, [N] MINOR

### Feedback Loop
- Iterações: [0-2]
- Issues resolvidas: [lista]
- Issues pendentes: [lista]

### Learning Summaries Consolidados
- **Padrões**: [consolidação de todos os agentes]
- **Warnings**: [consolidação de todos os agentes]
- **Sugestões**: [consolidação de todos os agentes]
```

## Template: Criar Novo Comando Multi-Agente

Use este template como base para criar novos comandos que invocam múltiplos agentes:

```markdown
# [Nome do Comando]

[Descrição do propósito do comando]

## Orquestração Multi-Agente

Invoque os agentes abaixo [em paralelo | sequencialmente]:

1. Invoque o agente `[nome]` para [tarefa]
   - Input: [o que o agente recebe]
   - Output esperado: [o que o agente deve produzir]

2. Invoque o agente `[nome]` para [tarefa]
   - Input: [o que o agente recebe]
   - Output esperado: [o que o agente deve produzir]

### Learning Summary Format
[Incluir o bloco padrão de Learning Summary]

## Consolidação
[Como combinar os outputs dos agentes]

## Persistência
[Onde salvar os Learning Summaries]

## Memory Flush
[Sessão + patterns a persistir]
```

Para exemplos concretos de comandos multi-agente existentes, consulte: `references/orchestration-patterns.md`

## Anti-Patterns

- **Misturar paralelo e sequencial sem justificativa** — Se agentes são independentes, use paralelo. Se há dependência, use sequencial. Nunca misture sem motivo claro.
- **Ignorar Learning Summaries** — Summaries são obrigatórios. Nunca descartar silenciosamente.
- **Loop infinito de feedback** — Máximo 2 iterações. Após isso, escalar para o usuário.
- **Agentes demais em um comando** — Máximo 4-5 agentes por comando. Mais do que isso fragmenta demais.
- **Não consolidar resultados** — Sempre apresentar relatório unificado ao final.
- **Invocar agente errado** — Cada agente é ultra-especialista. Verificar se a tarefa corresponde ao domínio do agente.
