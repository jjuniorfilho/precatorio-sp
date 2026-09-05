# Catalogo de MCPs — Referencia de Instalacao

> Catalogo extensivel de MCPs populares para uso com Claude Code.
> Cada entrada inclui: pacote oficial, comando de instalacao, env vars, capabilities e agentes recomendados.
> Atualizar este catalogo ao descobrir novos MCPs relevantes.

---

## 1. GitHub

| Campo | Valor |
|-------|-------|
| **Identificador** | `github` |
| **Categoria** | repository |
| **Tipo** | stdio ou http |
| **Pacote** | `@modelcontextprotocol/server-github` |
| **URL HTTP** | `https://api.githubcopilot.com/mcp/` |

**Instalacao (stdio)**:
```bash
claude mcp add --transport stdio github \
  --env GITHUB_PERSONAL_ACCESS_TOKEN=ghp_xxx \
  -- npx -y @modelcontextprotocol/server-github
```

**Instalacao (http)**:
```bash
claude mcp add --transport http github https://api.githubcopilot.com/mcp/
```

**Env vars**: `GITHUB_PERSONAL_ACCESS_TOKEN` (obrigatorio para stdio)

**Capabilities**: search_issues, search_code, search_pull_requests, list_commits, get_file_contents, create_pull_request, create_issue, list_branches, list_releases, merge_pull_request, entre outros.

**Agentes recomendados**: linear-project-sync, delivery-orchestrator

---

## 2. Perplexity

| Campo | Valor |
|-------|-------|
| **Identificador** | `perplexity` |
| **Categoria** | research |
| **Tipo** | plugin |
| **Plugin ID** | `perplexity@perplexity-mcp-server` |

**Instalacao**: Ativado como plugin no Claude Code. Configurado via `enabledPlugins` em `~/.claude/settings.json`:

```json
{
  "enabledPlugins": {
    "perplexity@perplexity-mcp-server": true
  }
}
```

**Env vars**: API key gerenciada pelo plugin

**Capabilities**: perplexity_ask (Q&A rapido), perplexity_search (busca web), perplexity_research (pesquisa profunda), perplexity_reason (raciocinio step-by-step)

**Agentes recomendados**: research-agent, self-evolution-engine, fullstack-debugger, prd-interview-specialist

---

## 3. Context7

| Campo | Valor |
|-------|-------|
| **Identificador** | `context7` |
| **Categoria** | docs |
| **Tipo** | stdio |
| **Pacote** | `@upstash/context7-mcp` |

**Instalacao**:
```bash
claude mcp add --transport stdio context7 \
  -- npx -y @upstash/context7-mcp
```

**Env vars**: Nenhuma obrigatoria (API publica)

**Capabilities**: resolve-library-id (busca ID de biblioteca), query-docs (consulta documentacao atualizada com code snippets). Suporta 1000+ bibliotecas populares.

**Agentes recomendados**: frontend-architect, react-developer, python-developer, test-engineer, docker-orchestrator, code-reviewer, research-agent, fullstack-debugger

---

## 4. Notion

| Campo | Valor |
|-------|-------|
| **Identificador** | `notionApi` |
| **Categoria** | project-management |
| **Tipo** | stdio |
| **Pacote** | `@notionhq/notion-mcp-server` |

**Instalacao**:
```bash
claude mcp add --transport stdio notionApi \
  --env OPENAPI_MCP_HEADERS='{"Authorization":"Bearer ntn_xxx","Notion-Version":"2022-06-28"}' \
  -- npx -y @notionhq/notion-mcp-server
```

**Env vars**: `OPENAPI_MCP_HEADERS` (obrigatorio — contém Bearer token e Notion-Version)

**Capabilities**: search, create_page, update_page, get_page, query_database, create_database, list_comments, create_comment

**Agentes recomendados**: linear-project-sync, delivery-orchestrator

---

## 5. Linear

| Campo | Valor |
|-------|-------|
| **Identificador** | `linear` |
| **Categoria** | project-management |
| **Tipo** | remote (mcp-remote) |
| **URL** | `https://mcp.linear.app/mcp` |

**Instalacao**:
```bash
claude mcp add --transport stdio linear \
  -- npx -y mcp-remote https://mcp.linear.app/mcp
```

**Env vars**: Autenticacao via OAuth no navegador (mcp-remote gerencia)

**Capabilities**: list_issues, create_issue, update_issue, list_projects, list_teams, search_issues, list_issue_statuses, create_comment

**Agentes recomendados**: linear-project-sync, delivery-orchestrator

---

## 6. Sentry

| Campo | Valor |
|-------|-------|
| **Identificador** | `sentry` |
| **Categoria** | observability |
| **Tipo** | http |
| **URL** | `https://mcp.sentry.dev/mcp` |

**Instalacao**:
```bash
claude mcp add --transport http sentry https://mcp.sentry.dev/mcp
```

**Env vars**: Autenticacao via OAuth no navegador

**Capabilities**: list_issues, get_issue_details, list_projects, search_errors, get_stacktrace. Ideal para debug de erros em producao.

**Agentes recomendados**: fullstack-debugger, test-engineer

---

## 7. Figma

| Campo | Valor |
|-------|-------|
| **Identificador** | `figma` |
| **Categoria** | design |
| **Tipo** | sse (via Dev Mode MCP server local) |
| **Pacote** | Figma Dev Mode MCP Server (aplicativo desktop) |

**Instalacao**:
```bash
claude mcp add --transport sse figma http://127.0.0.1:3845/sse
```

**Pre-requisito**: Figma Dev Mode MCP Server deve estar rodando localmente (porta 3845).

**Env vars**: Nenhuma (autenticacao via app Figma local)

**Capabilities**: Inspecao de componentes, design tokens, propriedades de frames, assets. Integrado com "Code to Canvas" (fev 2026).

**Agentes recomendados**: frontend-architect, ux-ui-design-expert, ux-mockup-architect

---

## 8. Supabase

| Campo | Valor |
|-------|-------|
| **Identificador** | `supabase` |
| **Categoria** | database |
| **Tipo** | stdio |
| **Pacote** | `@supabase/mcp-server-supabase` |

**Instalacao**:
```bash
claude mcp add --transport stdio supabase \
  --env SUPABASE_ACCESS_TOKEN=sbp_xxx \
  -- npx -y @supabase/mcp-server-supabase
```

**Env vars**: `SUPABASE_ACCESS_TOKEN` (obrigatorio)

**Capabilities**: Queries SQL diretas, exploracao de schema, gestao de auth, storage, edge functions. Acesso completo ao projeto Supabase.

**Agentes recomendados**: python-developer, fullstack-debugger

---

## Como Adicionar Novos MCPs ao Catalogo

Ao descobrir um novo MCP relevante, adicione uma entrada seguindo o formato:

```markdown
## N. Nome do MCP

| Campo | Valor |
|-------|-------|
| **Identificador** | `nome-kebab-case` |
| **Categoria** | research | docs | repository | project-management | observability | design | database | other |
| **Tipo** | stdio | http | sse | plugin |
| **Pacote** | `@scope/pacote-npm` ou URL |

**Instalacao**:
[comando claude mcp add]

**Env vars**: [variaveis necessarias]

**Capabilities**: [lista de ferramentas fornecidas]

**Agentes recomendados**: [agentes Cortex que se beneficiam]
```

**Fontes para descobrir novos MCPs**:
- https://github.com/modelcontextprotocol/servers — repositorio oficial
- https://glama.ai — diretorio de servidores MCP
- https://claudetory.com/mcps — catalogo da comunidade
- `claude mcp add-from-claude-desktop` — importar do Claude Desktop
