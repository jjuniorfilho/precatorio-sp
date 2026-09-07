---
name: self-evolution
description: "Evolve the framework based on usage patterns. Use this skill when analyzing collected evolution data, proposing framework improvements with confidence scores, running the /evolve cycle, or understanding the 4-phase auto-evolution architecture (Collection, Analysis, Proposal, Application)."
---

# Self-Evolution — Auto-Evolução Auditável

## Visão Geral

Esta skill implementa o ciclo de auto-evolução do Cortex Framework (ADR-008). O framework aprende com padrões de uso reais e propõe melhorias concretas — novos agentes, refinamentos de comandos, otimizações de workflow — com score de confiança baseado em evidência.

**Princípio fundamental**: O framework propõe, o humano aprova. NUNCA modificar automaticamente sem confirmação explícita.

## Ciclo de 4 Fases

### Fase 1: Coleta (Automática)

Ao final de cada comando com Memory Flush, registrar automaticamente em `.claude/memory/evolution/`:

**command-usage.jsonl** — Dados estruturados, uma entrada por linha (append O(1)). O legado `command-usage.json` (array) permanece como historico e deve ser lido junto:
```json
{
  "entries": [
    {
      "date": "2026-03-05",
      "command": "/work",
      "branch": "feat/auth",
      "agents_used": ["test-engineer", "code-reviewer"],
      "duration_phases": 3,
      "issues_found": { "critica": 0, "major": 2, "minor": 5 },
      "patterns_detected": ["repository-pattern", "jwt-auth"],
      "user_corrections": ["renamed variable X to Y"],
      "confidence": "alta"
    }
  ]
}
```

**agent-performance.md** — Dados qualitativos:
```markdown
### YYYY-MM-DD — /[comando] — [branch]
- **Agentes eficazes**: [agentes que produziram valor]
- **Agentes com problemas**: [agentes com issues ou output fraco]
- **Padrões recorrentes**: [padrões que aparecem em múltiplas sessões]
- **Sugestões do usuário**: [correções ou preferências expressas]
```

### Fase 2: Análise

O comando `/evolve` lê os dados acumulados e identifica oportunidades:

1. **Padrões de uso**: Quais comandos são mais usados? Quais agentes?
2. **Instruções repetidas**: O usuário corrige a mesma coisa repetidamente?
3. **Agentes com baixo desempenho**: Agentes que consistentemente produzem issues?
4. **Gaps**: Tarefas manuais recorrentes que poderiam ser automatizadas?

### Fase 3: Proposta

Gerar propostas classificadas por score de confiança:

| Score | Critério | Ação |
|-------|----------|------|
| **Alta** (5+ sessões) | Padrão confirmado com forte evidência | Propor com recomendação de aplicar |
| **Média** (3-4 sessões) | Padrão emergente, evidência moderada | Propor para consideração |
| **Baixa** (1-2 sessões) | Observação inicial, evidência fraca | Registrar para monitoramento |

**Formato de proposta**:
```markdown
### Proposta: [Título]
- **Score**: Alta | Média | Baixa
- **Categoria**: architecture | debugging | preferences | performance
- **Evidência**: [sessões onde o padrão foi observado]
- **Estado atual**: [como funciona hoje]
- **Mudança proposta**: [o que deveria mudar]
- **Impacto**: [agentes/comandos/workflows afetados]
- **Reversibilidade**: [como reverter se necessário]
```

### Fase 4: Aplicação

Aplicar mudanças aprovadas pelo humano:

1. Implementar a mudança nos arquivos do framework
2. Commit semântico: `evolve(escopo): descrição`
3. Registrar aplicação em `evolution/applied.md`
4. Monitorar impacto nas sessões seguintes

## 4 Categorias de Evolução

### 1. Architecture
Mudanças em padrões arquiteturais dos agentes ou comandos.
- Ex: "Adicionar validação Zod como padrão do agente backend"
- Impacto: agentes, templates, convenções

### 2. Debugging
Prevenção de erros recorrentes.
- Ex: "Adicionar verificação de NaN ao agente de transformação de dados"
- Impacto: agentes específicos, checklists

### 3. Preferences
Adaptação às preferências da equipe.
- Ex: "Sempre usar functional components (nunca class components)"
- Impacto: MEMORY.md, instruções dos agentes

### 4. Performance
Otimizações de workflow e eficiência.
- Ex: "Paralelizar agentes X e Y no /pre-pr (são independentes)"
- Impacto: comandos, orquestração

## 7 Regras de Ouro

1. **Human-in-the-Loop** — Toda mudança requer aprovação humana explícita
2. **Confidence-Gated** — Só propor mudanças com score Média ou Alta
3. **Reversível** — Toda mudança deve ser reversível (git revert)
4. **Evidência obrigatória** — Nunca propor baseado em especulação
5. **Commit semântico** — Usar `evolve(escopo): descrição` para rastreabilidade
6. **Monitorar impacto** — Acompanhar se a mudança melhorou nas sessões seguintes
7. **Nunca auto-aplicar** — Mesmo com confiança Alta, aguardar aprovação

## Dados de Evolução

### Localização

```
.claude/memory/evolution/
├── command-usage.jsonl      # Uso de comandos (uma entrada por linha, append O(1))
├── command-usage.json       # Legado v2.0 (array) — historico congelado, so leitura
├── agent-performance.md     # Performance qualitativa (append)
├── suggestions.md           # Propostas geradas pelo /evolve
└── applied.md               # Registro de mudanças aplicadas
```

### Retenção

| Categoria | Retenção | Justificativa |
|-----------|----------|---------------|
| command-usage.jsonl | Sem teto | Append O(1) dispensa truncagem; a serie alimenta a auditoria de tendencia |
| agent-performance.md | Últimos 90 dias | Alinhar com decay scan |
| suggestions.md | Permanente | Histórico de evolução |
| applied.md | Permanente | Auditoria de mudanças |

Para schemas detalhados e exemplos, consulte: `references/evolution-schema.md`

## Formato de Commit Semântico

```
evolve(architecture): adicionar Clean Architecture como padrão do backend
evolve(debugging): prevenir NaN em transformações de dados
evolve(preferences): configurar functional components como padrão React
evolve(performance): paralelizar agentes no /pre-pr
```

## Anti-Patterns

- **Evolução especulativa** — Nunca propor baseado em necessidades teóricas. Toda proposta deve ter evidência de uso real.
- **Breaking changes sem migração** — Nunca remover capabilities sem path de migração claro.
- **Auto-aplicação** — Nunca modificar o framework sem aprovação humana, mesmo com confiança Alta.
- **Dados insuficientes** — Não propor com score Baixa. Registrar para monitoramento e aguardar mais evidência.
- **Ignorar monitoramento** — Após aplicar uma mudança, monitorar impacto. Se piorou, reverter.
