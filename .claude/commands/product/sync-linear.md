# Sincronizar Features com Linear

Sincroniza a documentação de features em `docs/business-context/features/` com o projeto Linear, criando ou atualizando épicos e sub-issues automaticamente.

---

## Fluxo de Execução

### Passo 1: Seleção de Modo

Pergunte ao usuário qual modo de sincronização deseja:

**Opções:**
1. **Completo** - Sincronizar todas as features de todos os módulos
2. **Por Módulo** - Sincronizar apenas um módulo específico (Controladoria, Repasse, Financeiro, Analytics, Cadastros)
3. **Por Escopo** - Sincronizar apenas um escopo específico (MVP, Fase 2, Fase 3)
4. **Preview** - Apenas gerar relatório de diferenças, sem fazer alterações

Use o `AskUserQuestion` para apresentar essas opções.

---

### Passo 2: Análise de Features

Invoque o agente @linear-project-sync para executar a análise:

1. **Ler documentação**: Glob `docs/business-context/features/*.md`
2. **Ignorar arquivos**:
   - `_legacy*`
   - `index.md`
   - `README.md`
3. **Extrair metadata** de cada arquivo:
   - Título (H1)
   - Status, Prioridade, Escopo, Módulo
   - Requisitos Funcionais (RF-XX)

---

### Passo 3: Consultar Linear

Buscar issues existentes no projeto:

```bash
curl -s -X POST https://api.linear.app/graphql \
  -H "Content-Type: application/json" \
  -H "Authorization: $LINEAR_API_KEY" \
  -d '{"query": "query { project(id: \"6f6f88cf-a573-4777-bdb2-ba554716b392\") { issues(first: 200) { nodes { id identifier title state { name } priority labels { nodes { name } } children { nodes { identifier title state { name } } } } } } }"}'
```

---

### Passo 4: Consultar GitHub

Use ferramentas MCP para verificar status de implementação:

- `mcp__github__search_issues` - Buscar issues relacionadas
- `mcp__github__list_pull_requests` - Verificar PRs com "Closes PX-XXX"

---

### Passo 5: Gerar Relatório de Preview

Apresente o relatório de diferenças ao usuário:

```markdown
## 📊 Relatório de Sincronização Linear

### Resumo
| Métrica | Valor |
|---------|-------|
| Features Analisadas | XX |
| Novas (criar) | XX |
| A Atualizar | XX |
| Já Sincronizadas | XX |
| Órfãs no Linear | XX |

### ➕ CRIAR (Novas features sem issue Linear)
| Feature | Módulo | Escopo | Prioridade | Sub-issues |
|---------|--------|--------|------------|------------|
| Processos | Controladoria | MVP | Crítica | 11 RFs |

### 🔄 ATUALIZAR (Features com diferenças)
| Feature | Campo | Atual (Linear) | Novo (Doc) |
|---------|-------|----------------|------------|
| Agenda | Status | Backlog | Em Desenvolvimento |

### ✅ SINCRONIZADAS (Sem alterações necessárias)
- [x] Publicações (PX-XXX)
- [x] Andamentos (PX-YYY)

### ⚠️ ÓRFÃS (Issues Linear sem documentação correspondente)
- PX-ZZZ: [título] - Considerar arquivar?
```

---

### Passo 6: Confirmação

Pergunte ao usuário como proceder:

**Opções:**
- `Executar tudo` - Criar novas e atualizar existentes
- `Apenas criar` - Criar novas, ignorar atualizações
- `Apenas atualizar` - Atualizar existentes, ignorar novas
- `Cancelar` - Não fazer alterações

---

### Passo 7: Execução

Se aprovado, execute as mutations GraphQL:

#### Criar Epic (Issue pai)
```graphql
mutation {
  issueCreate(input: {
    teamId: "c7825da0-f41a-4a79-b472-8d219faa37ea"
    projectId: "6f6f88cf-a573-4777-bdb2-ba554716b392"
    title: "[Feature] Nome da Feature"
    description: "Descrição completa..."
    priority: 1
  }) {
    success
    issue { id identifier url }
  }
}
```

#### Criar Sub-Issue (RF)
```graphql
mutation {
  issueCreate(input: {
    teamId: "c7825da0-f41a-4a79-b472-8d219faa37ea"
    parentId: "id-do-epic"
    title: "RF01 - Título do Requisito"
    description: "Descrição..."
  }) {
    success
    issue { id identifier }
  }
}
```

#### Atualizar Issue
```graphql
mutation {
  issueUpdate(id: "issue-id", input: {
    stateId: "state-id"
    priority: 2
  }) {
    success
  }
}
```

---

### Passo 8: Relatório Final

Após execução, apresente o resultado:

```markdown
## ✅ Sincronização Concluída

### Criados (X issues)
- PX-301: [Feature] Processos - https://linear.app/px-tech/issue/PX-301
  - PX-302: RF01 - Visualização de Lista
  - PX-303: RF02 - Filtros Avançados

### Atualizados (X issues)
- PX-290: Status alterado Backlog → In Progress

### Ignorados (X issues)
- PX-286: Já sincronizado

### Próximos Passos
1. Revisar issues criadas no Linear
2. Atribuir responsáveis às tarefas
3. Adicionar estimativas se necessário
```

---

## Configuração Linear

```
Team ID: c7825da0-f41a-4a79-b472-8d219faa37ea
Project ID: 6f6f88cf-a573-4777-bdb2-ba554716b392
Project URL: https://linear.app/px-tech/project/controladoria-6f6f88cf-a573-4777-bdb2-ba554716b392
```

---

## Mapeamentos

### Status → State
| Doc Status | Linear State |
|------------|--------------|
| Backlog | Backlog |
| Planejado | Todo |
| Em Desenvolvimento | In Progress |
| Concluída | Done |

### Prioridade → Priority
| Doc Prioridade | Linear Priority |
|----------------|-----------------|
| Crítica | 1 (Urgent) |
| Alta | 2 (High) |
| Média | 3 (Medium) |
| Baixa | 4 (Low) |

### Escopo → Label
| Doc Escopo | Linear Label |
|------------|--------------|
| MVP | high-priority |

---

## Regras de Segurança

1. **Sempre preview primeiro** - Nunca executar mutations sem aprovação
2. **Não duplicar** - Verificar existência antes de criar
3. **Não fazer downgrade** - Não mover "In Progress" para "Backlog" automaticamente
4. **Rate limiting** - Esperar 500ms entre chamadas API
5. **Preservar edições manuais** - Não sobrescrever descrições editadas manualmente

---

## Uso

```
/product:sync-linear
```

Ou com argumentos:

```
/product:sync-linear modulo=Controladoria
/product:sync-linear escopo=MVP
/product:sync-linear preview
```
