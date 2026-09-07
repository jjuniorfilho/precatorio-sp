# Orchestration Patterns — Exemplos Concretos

> Exemplos reais de comandos multi-agente do Cortex Framework.
> Carregado sob demanda quando o agente precisa de referência para criar novos comandos.

---

## Exemplo 1: /pre-pr — 4 Agentes em Paralelo

**Padrão**: Paralelo (agentes independentes)
**Agentes**: 4

```markdown
## Orquestração Multi-Agente

Invoque os 4 agentes abaixo em paralelo:

1. `branch-master-docs-checker` — Verificar alinhamento com master docs
2. `branch-code-reviewer` — Revisar código para qualidade e bugs
3. `branch-documentation-writer` — Atualizar documentação do projeto
4. `branch-test-planner` — Planejar/escrever testes faltantes

### Learning Summary Format
[bloco padrão]

## Consolidação
1. Lidar com feedback — fazer mudanças conforme necessário
2. Consolidar Learning Summaries — unificar os 4
3. Verificar padrões recorrentes contra agent-learnings.md

## Persistência
Append em .claude/memory/patterns/agent-learnings.md

## Memory Flush
Sessão em .claude/memory/sessions/YYYY-MM-DD-pre-pr.md
```

**Por que paralelo?**
- Nenhum agente depende do output de outro
- Cada um analisa a branch de forma independente
- Execução mais rápida (4x ao invés de 1x)

---

## Exemplo 2: /work — 2 Agentes Sequenciais + Feedback Loop

**Padrão**: Sequencial com feedback loop
**Agentes**: 2 (test-engineer, code-reviewer)

```markdown
## Validação Multi-Agente (após implementação de cada fase)

### Passo 1: Invocar test-engineer
- Escrever/validar testes para código implementado
- Reportar: testes escritos, cobertura, falhas

### Passo 2: Invocar code-reviewer
- Revisar código implementado
- Classificar issues: CRÍTICA, MAJOR, MINOR
- Produzir Learning Summary

### Passo 3: Feedback Loop (max 2 iterações)
- Se CRÍTICAS encontradas:
  1. Corrigir issues
  2. Re-invocar test-engineer
  3. Re-invocar code-reviewer
  4. Max 2 loops
- Se apenas MAJOR/MINOR: reportar ao usuário
```

**Por que sequencial?**
- test-engineer precisa rodar primeiro (escrever testes)
- code-reviewer analisa tanto código quanto testes
- Feedback loop corrige issues críticas antes de pedir validação humana

---

## Exemplo 3: /collect — Agentes Condicionais

**Padrão**: Condicional (baseado no tipo de coleta)
**Agentes**: Variável

```markdown
## Coleta Baseada em Contexto

### Verificação
- Se coleta de ideias: usar abordagem exploratória
- Se coleta de bugs: invocar agente de investigação forense
- Sempre: persistir em .claude/memory/
```

**Por que condicional?**
- O tipo de coleta determina quais agentes são relevantes
- Evita invocar agentes desnecessários

---

## Decision Tree: Qual Padrão Usar?

```
Os agentes dependem do output um do outro?
├── NÃO → PARALELO
│   └── Todos executam simultaneamente
│   └── Consolidar resultados ao final
│
└── SIM → O output do agente A alimenta o agente B?
    ├── SIM → SEQUENCIAL
    │   └── Há correções que precisam ser re-validadas?
    │       ├── SIM → SEQUENCIAL + FEEDBACK LOOP
    │       └── NÃO → SEQUENCIAL simples
    │
    └── DEPENDE DO CONTEXTO → CONDICIONAL
        └── Verificar condições antes de invocar
```

---

## Tratamento de Falhas de Sub-Agentes

### Cenário 1: Agente não produz output

```markdown
Se agente X não retornar output:
1. Verificar se o agente foi invocado corretamente
2. Reportar falha ao usuário
3. Continuar com os demais agentes (não bloquear)
4. Marcar no relatório: "[agente-x]: FALHA — sem output"
```

### Cenário 2: Agente produz output incompleto

```markdown
Se agente X retornar output sem Learning Summary:
1. Registrar warning: "[agente-x]: Learning Summary ausente"
2. Usar o output disponível para consolidação
3. Não re-invocar apenas por falta de Learning Summary
```

### Cenário 3: Agentes com resultados conflitantes

```markdown
Se agente A diz "X está correto" e agente B diz "X está errado":
1. Priorizar o agente mais especializado no domínio em questão
2. Reportar o conflito ao usuário com contexto
3. Não resolver automaticamente — escalar para decisão humana
```

---

## Checklist: Validar Novo Comando Multi-Agente

Antes de finalizar um novo comando multi-agente, verificar:

- [ ] Cada agente tem tarefa claramente definida
- [ ] Padrão de execução justificado (paralelo/sequencial/condicional)
- [ ] Learning Summary Format incluído
- [ ] Consolidação de resultados definida
- [ ] Persistência de learnings definida (onde salvar)
- [ ] Memory Flush definido (sessão + patterns)
- [ ] Limite de feedback loop definido (max 2)
- [ ] Tratamento de falhas considerado
- [ ] Máximo 4-5 agentes (não fragmentar demais)
