---
name: mcp-manager
description: "Manage MCP (Model Context Protocol) servers in Claude Code projects. Use this skill when installing, configuring, syncing, or mapping MCP servers to agents — including detection of installed MCPs, category-based agent mapping, installation guidance, and scope management (user/project/local)."
---

# MCP Manager — Gestao Dinamica de MCPs

## Visao Geral

Esta skill fornece o conhecimento operacional para gerenciar MCPs (Model Context Protocol) no Cortex Framework. MCPs estendem as capacidades dos agentes conectando-os a servicos externos — pesquisa web, documentacao de bibliotecas, gestao de repositorio, project management, entre outros.

**Principio fundamental**: MCPs sao dinamicos. Novos surgem constantemente no ecossistema. O framework trata MCPs como um ecosystem gerenciavel, nao uma lista estatica.

## O que sao MCPs

No Claude Code, MCPs sao servidores que fornecem ferramentas adicionais acessiveis via `mcp__<servidor>__<ferramenta>`. Exemplo:

- `mcp__github__search_issues` — busca issues no GitHub
- `mcp__context7__query-docs` — consulta docs de bibliotecas
- `mcp__plugin_perplexity_perplexity__perplexity_ask` — pesquisa web

MCPs funcionam como plugins que ampliam o que o Claude Code pode fazer. Agentes que declaram `mcp_access` no frontmatter indicam que se beneficiam dessas ferramentas.

## Registry de MCPs Conhecidos

| MCP | Categoria | Tipo | Capacidades Principais |
|-----|-----------|------|----------------------|
| `github` | repository | stdio/http | Issues, PRs, code search, releases, file contents |
| `perplexity` | research | plugin | Busca web, pesquisa profunda, raciocinio com fontes |
| `context7` | docs | stdio | Documentacao atualizada de 1000+ bibliotecas |
| `notionApi` | project-management | stdio | Pages, databases, comments, busca |
| `linear` | project-management | stdio (via mcp-remote) | Issues, projetos, ciclos, time tracking |
| `sentry` | observability | http | Erros de producao, stack traces, metricas |
| `figma` | design | sse | Componentes, design tokens, inspecao de frames |
| `supabase` | database | stdio | Queries SQL, schema, auth, storage |

Para catalogo completo com instrucoes de instalacao: `references/mcp-catalog.md`

## Categorias de MCP

Cada MCP pertence a uma categoria que define quais tipos de agente se beneficiam dele.

| Categoria | Descricao | Exemplo de MCPs |
|-----------|-----------|----------------|
| **research** | Pesquisa web, analise de mercado, investigacao | perplexity |
| **docs** | Documentacao atualizada de bibliotecas e frameworks | context7 |
| **repository** | Operacoes na API do repositorio (PRs, issues, code search) | github |
| **project-management** | Gestao de tarefas, projetos, documentacao externa | linear, notionApi |
| **observability** | Monitoramento, erros de producao, metricas | sentry |
| **design** | Design tokens, componentes visuais, inspecao de layout | figma |
| **database** | Acesso direto a banco de dados, queries, schema | supabase |
| **other** | MCPs que nao se encaixam nas categorias acima | (mapeamento manual) |

## Regras de Mapeamento (Categoria → Agente)

O mapeamento e por CATEGORIA do MCP, nao por MCP individual. Quando um novo MCP de uma categoria e instalado, ele automaticamente beneficia os mesmos agentes.

| Categoria | Agentes Beneficiados | Justificativa |
|-----------|---------------------|---------------|
| **research** | research-agent, self-evolution-engine, fullstack-debugger, prd-interview-specialist | Agentes que investigam, pesquisam solucoes, analisam mercado |
| **docs** | frontend-architect, react-developer, python-developer, test-engineer, docker-orchestrator, code-reviewer, research-agent, fullstack-debugger | Agentes que implementam com bibliotecas externas |
| **repository** | linear-project-sync, delivery-orchestrator | Agentes que interagem com GitHub API |
| **project-management** | linear-project-sync, delivery-orchestrator | Agentes que gerenciam tarefas e projetos |
| **observability** | fullstack-debugger, test-engineer | Agentes que diagnosticam e monitoram |
| **design** | frontend-architect, ux-ui-design-expert | Agentes que trabalham com design visual |
| **database** | python-developer, fullstack-debugger | Agentes que interagem com banco de dados |

**Agentes que NUNCA recebem MCPs**: Agentes branch-* (operam sobre diff local), agentes de geracao de artefatos (docx, pptx, html), agentes de validacao interna (adr-compliance-checker, master-docs-gate-keeper).

## Padroes de Instalacao

### Tipos de transporte

| Tipo | Comando Base | Quando Usar |
|------|-------------|-------------|
| **stdio** | `claude mcp add --transport stdio <nome> -- npx -y <pacote>` | MCPs locais via npm |
| **http** | `claude mcp add --transport http <nome> <url>` | MCPs remotos com HTTP |
| **sse** | `claude mcp add --transport sse <nome> <url>` | MCPs com Server-Sent Events |
| **plugin** | Ativado via `enabledPlugins` em settings.json | MCPs first-party da Anthropic |

### Escopos de configuracao

| Escopo | Arquivo | Compartilhavel | Quando Usar |
|--------|---------|---------------|-------------|
| **local** (default) | `~/.claude/settings.local.json` | Nao | DEFAULT da CLI. MCPs pessoais por projeto, secrets seguros |
| **user** | `~/.claude/settings.json` | Nao | MCPs pessoais persistentes entre todos os projetos |
| **project** | `.mcp.json` (raiz do projeto) | Sim (git) | MCPs compartilhados pelo time (sem secrets!) |

**CLI nativa**:
```bash
claude mcp add     # Adicionar MCP
claude mcp list    # Listar MCPs configurados
claude mcp get     # Detalhes de um MCP
claude mcp remove  # Remover MCP
```

**Regra de seguranca**: NUNCA armazenar secrets (API keys, tokens) em `.mcp.json` (versionado). Usar variaveis de ambiente via `--env` ou configurar no escopo `local` (default, seguro) ou `user`.

## Protocolo de Deteccao

Para detectar MCPs instalados no ambiente:

1. **Metodo primario — CLI nativa**:
   ```bash
   claude mcp list
   ```
   Retorna todos os MCPs de todos os escopos (local, user, project). E o metodo mais confiavel pois consolida automaticamente.

2. **Metodo alternativo — Leitura direta de settings** (quando CLI nao disponivel):
   - `~/.claude/settings.local.json` → `mcpServers` (escopo local, default)
   - `~/.claude/settings.json` → `mcpServers` + `enabledPlugins` (escopo user)
   - `.mcp.json` (raiz do projeto) → `mcpServers` (escopo project)
   - Consolidar sem duplicatas. Prioridade: local > project > user

**Formato mcpServers**:
```json
{
  "mcpServers": {
    "<nome>": {
      "command": "npx",
      "args": ["-y", "<pacote>"],
      "env": { "KEY": "valor" }
    }
  }
}
```

**Formato enabledPlugins** (apenas em settings.json):
```json
{
  "enabledPlugins": {
    "<nome>@<servidor>": true
  }
}
```

## Decision Tree: Quando Usar Cada MCP

```
Preciso pesquisar algo na web?
  SIM → perplexity (research)

Preciso de docs de uma biblioteca/framework?
  SIM → context7 (docs)

Preciso interagir com GitHub (PRs, issues)?
  SIM → github (repository)

Preciso gerenciar tarefas/projetos?
  SIM → linear ou notionApi (project-management)

Preciso investigar erros de producao?
  SIM → sentry (observability)

Preciso de design tokens ou inspecionar UI?
  SIM → figma (design)

Preciso de acesso direto ao banco?
  SIM → supabase (database)

Nenhuma das opcoes acima?
  → Consultar references/mcp-catalog.md ou pesquisar na web
```

## Graceful Degradation

`mcp_access` no frontmatter e uma **declaracao de intencao**, nao uma dependencia obrigatoria.

- Se o MCP esta instalado: agente usa as ferramentas MCP normalmente
- Se o MCP NAO esta instalado: agente opera com capacidades reduzidas, sem erro
- Exemplo: `research-agent` com `mcp_access: [perplexity, context7]` funciona sem Perplexity — usa apenas WebSearch nativo

## Anti-Patterns

1. **Armazenar secrets em .mcp.json** — Arquivo versionado no git. Usar `--env` ou escopo local/user
2. **Mapear MCP a TODOS os agentes** — Cada MCP deve ir apenas para agentes que realmente se beneficiam
3. **Depender de MCP para funcionalidade basica** — Agente deve funcionar sem MCPs (graceful degradation)
4. **Instalar MCP sem verificar credenciais** — MCP sem API key configurada retorna erros nas ferramentas
5. **Ignorar categoria ao mapear** — Usar mapeamento por categoria, nao individual

Para catalogo detalhado de MCPs com instrucoes de instalacao: `references/mcp-catalog.md`
