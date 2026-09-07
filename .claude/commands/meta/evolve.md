# Evolve — Auto-Evolução do Framework

Você é responsável por executar o ciclo de auto-evolução do Cortex Framework (ADR-008). Este comando analisa dados de uso acumulados pelos comandos do framework, identifica padrões e propõe melhorias concretas ao humano para aprovação.

**Princípio fundamental**: O framework propõe, o humano aprova. NUNCA aplicar mudanças sem confirmação explícita.

> **IMPORTANTE**: Todos os caminhos `.claude/memory/` neste comando referem-se a pasta `memory/` dentro do `.claude/` do **projeto atual** (working directory), NUNCA a `~/.claude/memory/` do usuario.

## Fase 1: Verificar Dados de Evolução

Antes de qualquer análise, verificar se há dados suficientes.

### 1.1 Verificar command-usage (JSONL + legado)

Ler `.claude/memory/evolution/command-usage.jsonl` (**uma entrada por linha**) **e** o legado `command-usage.json` (array em `entries`), concatenando na ordem cronologica. O `.json` fica congelado como historico — nada e migrado nem descartado. Linha corrompida no `.jsonl` custa **uma entrada**: pular e seguir.

- **Se arquivo não existir ou estiver vazio**:
  ```
  ⚠️ Nenhum dado de evolução coletado ainda.

  O ciclo de evolução depende de dados coletados automaticamente pelos comandos do framework.
  Execute /work, /pre-pr, /discover, /collect, /spec ou /bug-collect para acumular dados.

  Cada execução registra: comando usado, agentes invocados, issues encontradas e padrões detectados.
  ```
  **Parar aqui.** Não prosseguir sem dados.

- **Se existir**: Contar número de entradas.

### 1.2 Verificar agent-performance.md

Ler `.claude/memory/evolution/agent-performance.md`.

- Se não existir: registrar "sem dados qualitativos" mas continuar (a telemetria de comandos é suficiente).

### 1.3 Verificar Volume Mínimo

Contar sessões distintas registradas nos dados.

- **Se < 3 sessões**:
  ```
  ⚠️ Apenas N sessões registradas (mínimo recomendado: 3).

  Com poucas sessões, os padrões detectados têm confiança baixa.
  Recomendamos acumular pelo menos 3 sessões antes de analisar padrões.

  Deseja prosseguir mesmo assim? (os padrões terão score Baixa ou Média)
  ```
  Se o usuário quiser prosseguir, continuar. Se não, parar.

- **Se >= 3 sessões**: Reportar resumo e prosseguir.
  ```
  ✅ Dados de evolução encontrados.
  - Entradas de telemetria (jsonl + legado): N
  - Sessões distintas: N
  - Dados qualitativos: Sim/Não

  Iniciando análise de padrões...
  ```

## Fase 2: Invocar self-evolution-engine

Invocar o agente `self-evolution-engine` passando a seguinte instrução:

```
Analise os dados de evolução do framework e gere propostas de melhoria.

Dados disponíveis:
- .claude/memory/evolution/command-usage.jsonl (canônico) + command-usage.json (legado
  congelado) — ler os dois e concatenar em ordem cronológica
- .claude/memory/evolution/agent-performance.md
- .claude/memory/patterns/decisions.md
- .claude/memory/patterns/errors.md
- .claude/memory/sessions/ (últimas 10 sessões)

Execute o protocolo de análise completo:
1. Carregar todos os dados de evolução
2. Identificar padrões por categoria (architecture, debugging, preferences, performance)
3. Calcular score de confiança para cada padrão
4. Gerar propostas (max 5) para padrões com confiança Média ou Alta
5. Registrar padrões de confiança Baixa para monitoramento

Retorne o relatório completo no formato definido no Output Format do agente.
```

Aguardar o retorno do agente com o relatório de análise.

## Fase 3: Apresentar Propostas ao Humano

### 3.1 Se Nenhuma Proposta Gerada

```
## Resultado da Análise de Evolução

📊 Sessões analisadas: N
🔍 Padrões identificados: N (todos com confiança Baixa)

Nenhuma proposta gerada nesta execução.

Padrões registrados para monitoramento em `.claude/memory/evolution/suggestions.md`.
Continue usando o framework — com mais sessões, os padrões ganharão confiança.
```

Registrar padrões de confiança Baixa em `.claude/memory/evolution/suggestions.md` e parar.

### 3.2 Se Há Propostas

Apresentar cada proposta individualmente ao humano:

```
## Propostas de Evolução

📊 Sessões analisadas: N | Propostas: N

---

### Proposta 1/N: [Título]

- **Score**: Alta (7 sessões) | Média (4 sessões)
- **Categoria**: architecture | debugging | preferences | performance
- **Evidência**: [sessões onde foi observado]
- **Estado atual**: [como funciona hoje]
- **Mudança proposta**: [descrição clara da alteração]
- **Impacto**: [agentes/comandos afetados]
- **Reversibilidade**: git revert do commit

**Decisão**: Aprovar (a) | Rejeitar (r) | Pular (s)
```

Para cada proposta, aguardar decisão do humano antes de apresentar a próxima.

## Fase 4: Aplicar e Registrar

### 4.1 Para Cada Proposta APROVADA

1. **Aplicar a mudança** no arquivo indicado
2. **Registrar** em `.claude/memory/evolution/suggestions.md`:
   ```markdown
   ### YYYY-MM-DD — [título] — APROVADA ✅

   **Confiança**: [score — N sessões]
   **Categoria**: [tipo]
   **Arquivos modificados**: [lista]
   **Evidência**: [sessões fonte]
   ```
3. **Registrar** em `.claude/memory/evolution/applied.md`:
   ```markdown
   ### YYYY-MM-DD — [título]

   **Categoria**: [tipo]
   **Mudança**: [descrição resumida]
   **Arquivos**: [lista de arquivos modificados]
   **Monitorar**: Verificar impacto nas próximas 3 sessões
   ```

### 4.2 Para Cada Proposta REJEITADA

Registrar em `.claude/memory/evolution/suggestions.md`:
```markdown
### YYYY-MM-DD — [título] — REJEITADA ❌

**Confiança**: [score — N sessões]
**Categoria**: [tipo]
**Motivo**: [motivo dado pelo humano]
```

### 4.3 Para Cada Proposta PULADA

Registrar em `.claude/memory/evolution/suggestions.md`:
```markdown
### YYYY-MM-DD — [título] — ADIADA ⏸️

**Confiança**: [score — N sessões]
**Categoria**: [tipo]
**Nota**: Adiada para revisão futura
```

### 4.4 Padrões de Confiança Baixa (Monitoramento)

Para padrões detectados mas com score Baixa (1-2 sessões), registrar em `.claude/memory/evolution/suggestions.md`:
```markdown
### YYYY-MM-DD — [título] — MONITORANDO 👀

**Confiança**: Baixa (N sessões)
**Categoria**: [tipo]
**Nota**: Aguardando mais evidência para propor
```

## Fase 5: Relatório Final

Apresentar resumo consolidado:

```markdown
## Relatório de Evolução — YYYY-MM-DD

### Resumo
- Sessões analisadas: N
- Padrões identificados: N
- Propostas apresentadas: N
- Aprovadas: N | Rejeitadas: N | Adiadas: N
- Monitoramento: N padrões registrados

### Propostas Aprovadas
- [título 1] → arquivo(s) modificado(s)
- [título 2] → arquivo(s) modificado(s)

### Próximos Passos
- Mudanças aplicadas serão monitoradas nas próximas sessões
- Padrões em monitoramento serão reavaliados na próxima execução
- Commit das mudanças: usar `evolve(escopo): descrição` para cada alteração

**Nota**: As mudanças foram aplicadas nos arquivos mas NÃO foram commitadas.
Use `/pre-pr` ou commite manualmente com o formato: `evolve(escopo): descrição`
```

## Regras Importantes

1. **Human-in-the-Loop obrigatório** — Toda proposta requer decisão explícita do humano
2. **Máximo 5 propostas** — Evitar overwhelm. Priorizar por confiança e impacto
3. **Escopo limitado a `.claude/`** — Nunca propor mudanças em código de aplicação
4. **Dados são pré-requisito** — Sem dados de evolução, o comando para na Fase 1
5. **Registrar tudo** — Aprovadas, rejeitadas, adiadas e monitoradas. O histórico é auditável
6. **Não commitar automaticamente** — O commit fica com o humano ou com o `/pre-pr`
7. **Acentos obrigatórios** — Todo texto gerado deve ter acentuação correta em português
