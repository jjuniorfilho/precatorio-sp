# MCP Sync — Sincronizar MCPs com Agentes

Você é responsável por detectar MCPs instalados no ambiente e sincronizar o campo `mcp_access` nos frontmatters dos agentes do Cortex Framework. Este comando garante que agentes declarem corretamente quais MCPs estão disponíveis para eles.

**Princípio fundamental**: O framework propõe, o humano aprova. NUNCA modificar frontmatters sem confirmação explícita.

## Entrada

<options>
$ARGUMENTS
</options>

Se `$ARGUMENTS` estiver vazio, executar sync completo para todos os agentes.
Se um nome de agente for fornecido, sincronizar apenas esse agente.

## Fase 1: Detectar MCPs Instalados

### 1.1 Método Primário — CLI

Executar via Bash:
```bash
claude mcp list
```

Parsear a saída para extrair nomes dos MCPs configurados em todos os escopos (local, user, project).

### 1.2 Método Alternativo — Leitura Direta

Se a CLI não estiver disponível, ler os settings files diretamente:

1. `~/.claude/settings.local.json` → campo `mcpServers` (escopo local, default)
2. `~/.claude/settings.json` → campos `mcpServers` + `enabledPlugins` (escopo user)
3. `.mcp.json` na raiz do projeto → campo `mcpServers` (escopo project)

Consolidar lista única de MCPs, sem duplicatas.

### 1.3 Reportar MCPs Detectados

```
MCPs detectados no ambiente:
- github (repository)
- perplexity (research)
- context7 (docs)
- ...

Total: N MCPs em N escopos
```

Se nenhum MCP for detectado, informar o usuário e sugerir `/mcp-install`.

## Fase 2: Carregar Regras de Mapeamento

Ler a skill `mcp-manager` para obter as regras de mapeamento:

1. Ler `.claude/skills/mcp-manager/SKILL.md`
2. Extrair a tabela "Regras de Mapeamento (Categoria → Agente)"
3. Extrair a tabela "Registry de MCPs Conhecidos" para identificar categorias

Para cada MCP detectado na Fase 1:
- Identificar sua **categoria** na tabela de registry (research, docs, repository, project-management, observability, design, database, other)
- Se o MCP não estiver no registry, perguntar ao usuário qual categoria atribuir

## Fase 3: Ler Frontmatters dos Agentes

Ler todos os agentes em `.claude/agents/*.md`:

1. Para cada arquivo `.md`, extrair o frontmatter YAML
2. Obter o campo `mcp_access` atual (array de strings)
3. Obter o campo `name` para identificação
4. Armazenar mapeamento: `{nome: string, mcp_access_atual: string[]}`

Se `$ARGUMENTS` contém um nome de agente, filtrar apenas esse agente.

## Fase 4: Calcular Mapeamento Proposto

Para cada agente, calcular o `mcp_access` ideal:

1. Consultar as regras de mapeamento (Fase 2)
2. Para cada categoria de MCP detectado, verificar se o agente aparece na coluna "Agentes Beneficiados"
3. Se sim, incluir o MCP no `mcp_access` proposto do agente
4. Gerar diff: comparar `mcp_access_atual` vs `mcp_access_proposto`

**Regras de exclusão** (consultar lista completa na skill mcp-manager):
- Agentes `branch-*` NUNCA recebem MCPs (operam sobre diff local)
- Agentes de geração de artefatos (executive-report-generator, ux-mockup-architect, lovable-*) NUNCA recebem MCPs
- Agentes de validação interna (adr-compliance-checker, master-docs-gate-keeper) NUNCA recebem MCPs
- Se um MCP já está no `mcp_access` atual e deveria continuar, manter

## Fase 5: Preview — Mostrar Mudanças Propostas

Apresentar tabela de mudanças ao usuário ANTES de qualquer edição:

```
## MCP Sync — Preview de Mudanças

MCPs detectados: github, perplexity, context7, ...

| Agente | mcp_access Atual | mcp_access Proposto | Status |
|--------|-----------------|-------------------|--------|
| research-agent | [] | [perplexity, context7] | + ADICIONAR |
| frontend-architect | [] | [context7] | + ADICIONAR |
| memory-manager | [] | [] | = SEM MUDANÇA |
| ... | ... | ... | ... |

Agentes a modificar: N
Agentes sem mudança: N

Aplicar mudanças? (s/n)
```

Aguardar confirmação do usuário. Se rejeitar, parar aqui.

## Fase 6: Aplicar Mudanças

Para cada agente com mudanças propostas:

1. Ler o arquivo `.claude/agents/{nome}.md`
2. Localizar o campo `mcp_access:` no frontmatter YAML
3. Substituir o valor atual pelo proposto
   - Exemplo: `mcp_access: []` → `mcp_access: [perplexity, context7]`
4. Salvar o arquivo (usar Edit, não Write — preservar conteúdo)

**Cuidados**:
- SOMENTE modificar o campo `mcp_access` — nenhuma outra mudança no arquivo
- Manter formatação YAML consistente: `mcp_access: [item1, item2]`
- Não adicionar espaços extras ou quebras de linha

## Fase 7: Relatório e Memory Flush

### 7.1 Relatório

Apresentar resumo do que foi alterado:

```
## MCP Sync — Relatório

### MCPs Detectados
- github (repository)
- perplexity (research)
- context7 (docs)

### Agentes Atualizados
- research-agent: [] → [perplexity, context7]
- frontend-architect: [] → [context7]

### Agentes Sem Mudança
- memory-manager: [] (sem MCPs aplicáveis)
- branch-code-reviewer: [] (categoria excluída)

### Resumo
- Agentes atualizados: N
- Agentes sem mudança: N
- MCPs mapeados: N
```

### 7.2 Memory Flush

> **IMPORTANTE**: Todos os caminhos `.claude/memory/` neste comando referem-se a pasta `memory/` dentro do `.claude/` do **projeto atual** (working directory), NUNCA a `~/.claude/memory/` do usuario.

Nao ha nada a escrever manualmente aqui. O registro de uso em
`.claude/memory/evolution/command-usage.jsonl` e garantido pelo hook
(`.claude/scripts/telemetry-hook.py`, registrado no `settings.json`), que roda independente
da janela de contexto. O `command-usage.json` legado esta congelado como historico: nada e
escrito nele.

## Regras Importantes

1. **Human-in-the-Loop obrigatório** — Preview (Fase 5) requer confirmação antes de aplicar
2. **Apenas mcp_access** — Nunca modificar outros campos do frontmatter
3. **Mapeamento por categoria** — Usar regras da skill mcp-manager, não mapeamento ad-hoc
4. **MCPs desconhecidos** — Se um MCP não está no registry, perguntar categoria ao usuário
5. **Idempotente** — Executar múltiplas vezes deve produzir o mesmo resultado
6. **Acentos obrigatórios** — Todo texto gerado deve ter acentuação correta em português
