# MCP Install — Instalar Novo MCP

Você é responsável por guiar a instalação de um novo MCP (Model Context Protocol) no ambiente do usuário. Este comando pesquisa o MCP oficial, configura credenciais, instala via CLI nativa e sincroniza os agentes.

**Princípio fundamental**: O framework propõe, o humano aprova. NUNCA instalar sem confirmação explícita.

## Entrada

<mcp_name>
$ARGUMENTS
</mcp_name>

Se `$ARGUMENTS` estiver vazio, perguntar ao usuário qual MCP deseja instalar.

## Fase 1: Pesquisar MCP

### 1.1 Consultar Catálogo Interno

Ler `.claude/skills/mcp-manager/references/mcp-catalog.md` e buscar o MCP pelo nome fornecido.

- **Se encontrado**: Extrair pacote, tipo de transporte, env vars, comando de instalação
- **Se NÃO encontrado**: Prosseguir para pesquisa externa (1.2)

### 1.2 Pesquisa Externa (se necessário)

Se o MCP não está no catálogo:

1. Usar WebSearch ou Perplexity para pesquisar: `"{nome} MCP server official npm package"`
2. Verificar fontes confiáveis:
   - https://github.com/modelcontextprotocol/servers
   - npm registry oficial
   - Repositório oficial do serviço
3. Apresentar opções encontradas ao usuário:

```
MCP "{nome}" não encontrado no catálogo interno.

Resultados da pesquisa:
1. @scope/pacote-npm — [descrição] (fonte: npm)
2. URL HTTP — [descrição] (fonte: github)

Qual opção deseja usar? (ou fornecer pacote/URL manualmente)
```

Se nenhum resultado for encontrado, informar o usuário e parar.

### 1.3 Confirmar Detalhes

Apresentar ao usuário as informações do MCP antes de prosseguir:

```
## MCP: {nome}

- Pacote: @scope/pacote-npm
- Tipo: stdio | http | sse | plugin
- Env vars obrigatórias: KEY1, KEY2
- Categoria: research | docs | repository | ...

Prosseguir com instalação? (s/n)
```

## Fase 2: Escolher Escopo

Perguntar ao usuário em qual escopo instalar:

```
Em qual escopo instalar o MCP "{nome}"?

1. Local (Recomendado) — Apenas este projeto, apenas você
   Escopo default da CLI. Seguro para secrets.

2. User — Todos os projetos, apenas você
   Arquivo: ~/.claude/settings.json
   Ideal para MCPs que você usa em todos os projetos.

3. Project — Compartilhado com o time via git
   Arquivo: .mcp.json (raiz do projeto)
   Ideal para MCPs do time (SEM secrets!)
```

**Regra de segurança**: Se o MCP requer env vars com secrets (API keys, tokens) e o usuário escolher escopo `project`, alertar:

```
ATENÇÃO: O escopo "project" armazena configuração em .mcp.json, que é versionado no git.
Secrets (API keys, tokens) NÃO devem ser armazenados em arquivos versionados.

Opções:
1. Usar escopo "local" (recomendado para MCPs com secrets)
2. Continuar com "project" mas usando variáveis de ambiente do sistema
```

## Fase 3: Configurar Credenciais

Se o MCP requer variáveis de ambiente:

1. Listar as env vars necessárias:
   ```
   O MCP "{nome}" requer as seguintes credenciais:

   - GITHUB_PERSONAL_ACCESS_TOKEN: Token de acesso pessoal do GitHub
     Onde obter: https://github.com/settings/tokens

   Por favor, forneça os valores:
   ```

2. Coletar valores do usuário
3. **NUNCA** logar ou exibir valores de secrets após recebê-los
4. Montar flags `--env KEY=valor` para o comando de instalação

Se o MCP não requer env vars, pular esta fase.

## Fase 4: Instalar

### 4.1 Gerar Comando

Montar o comando `claude mcp add` com base nas informações coletadas. Sempre adicionar `--scope <escopo>` ao comando, mesmo que o catálogo não inclua:

**stdio**:
```bash
claude mcp add --transport stdio --scope <escopo> \
  --env KEY=valor \
  <nome> -- npx -y <pacote>
```

**http**:
```bash
claude mcp add --transport http --scope <escopo> \
  <nome> <url>
```

**sse**:
```bash
claude mcp add --transport sse --scope <escopo> \
  <nome> <url>
```

### 4.2 Confirmar e Executar

Mostrar o comando ao usuário com secrets mascarados e pedir confirmação:

```
Comando de instalação:

claude mcp add --transport stdio --scope local \
  --env GITHUB_PERSONAL_ACCESS_TOKEN=ghp_*** \
  github -- npx -y @modelcontextprotocol/server-github

Executar? (s/n)
```

**Ao executar via Bash**: Não incluir o valor real do secret na descrição do comando Bash. Usar descrição genérica como "Instalar MCP {nome} no escopo {escopo}".

Executar via Bash após confirmação.

### 4.3 Verificar Instalação

Executar `claude mcp list` e verificar que o MCP aparece na lista.

- **Se aparece**: Reportar sucesso
- **Se NÃO aparece**: Reportar erro e sugerir debug

## Fase 5: Sincronizar Agentes

Executar a lógica de sincronização para atualizar os agentes com o MCP recém-instalado:

1. Detectar todos os MCPs instalados (incluindo o recém-instalado) via `claude mcp list`
2. Carregar regras de mapeamento de `.claude/skills/mcp-manager/SKILL.md`
3. Para o MCP recém-instalado, identificar sua categoria no registry
   - Se não está no registry, perguntar ao usuário qual categoria atribuir
4. Calcular `mcp_access` proposto para cada agente seguindo as regras de mapeamento por categoria
5. Mostrar preview das mudanças ao usuário
6. Aplicar mudanças nos frontmatters com confirmação (usar Edit, apenas no campo `mcp_access`)

**Regras de exclusão**: Consultar lista de agentes excluídos na skill mcp-manager (branch-*, geração de artefatos, validação interna).

## Fase 6: Relatório Final

```
## MCP Install — Relatório

### MCP Instalado
- Nome: {nome}
- Pacote: {pacote}
- Escopo: {escopo}
- Tipo: {transporte}

### Agentes Atualizados
- {agente1}: mcp_access atualizado com [{nome}]
- {agente2}: mcp_access atualizado com [{nome}]

### Catálogo
Se este MCP não estava no catálogo interno, considere adicioná-lo em:
.claude/skills/mcp-manager/references/mcp-catalog.md
```

## Fase 7: Memory Flush

> **IMPORTANTE**: Todos os caminhos `.claude/memory/` neste comando referem-se a pasta `memory/` dentro do `.claude/` do **projeto atual** (working directory), NUNCA a `~/.claude/memory/` do usuario.

Nao ha nada a escrever manualmente aqui. O registro de uso em
`.claude/memory/evolution/command-usage.jsonl` e garantido pelo hook
(`.claude/scripts/telemetry-hook.py`, registrado no `settings.json`), que roda independente
da janela de contexto. O `command-usage.json` legado esta congelado como historico: nada e
escrito nele.

## Regras Importantes

1. **Human-in-the-Loop obrigatório** — Confirmação em 3 pontos: detalhes do MCP, escopo, comando de instalação
2. **Secrets seguros** — Nunca armazenar secrets em `.mcp.json`. Alertar se usuário escolher escopo project com secrets
3. **Catálogo primeiro** — Sempre consultar catálogo interno antes de pesquisar externamente
4. **Verificar após instalar** — Sempre confirmar que o MCP aparece em `claude mcp list`
5. **Sincronizar agentes** — Sempre executar sync após instalação bem-sucedida
6. **Acentos obrigatórios** — Todo texto gerado deve ter acentuação correta em português
