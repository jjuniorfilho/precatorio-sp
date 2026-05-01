# 🔍 Guia do Sistema de Discovery (`/discover`)

> **Novidade v2.0**: Discovery automático de projeto com carregamento seletivo de contexto

---

## 📋 Índice

- [O que é `/discover`](#o-que-é-discover)
- [Quando Usar](#quando-usar)
- [Como Funciona](#como-funciona)
- [Saída Gerada](#saída-gerada)
- [Integração com Outros Comandos](#integração-com-outros-comandos)
- [Exemplos Práticos](#exemplos-práticos)
- [Troubleshooting](#troubleshooting)

---

## O que é `/discover`

O comando `/discover` é o **ponto de entrada do Context Enhancement System** do Cortex v2.0. Ele analisa automaticamente seu projeto e gera um briefing modular estruturado que otimiza o uso de contexto em todas as fases de desenvolvimento.

**Propósito**:
- Eliminar sobrecarga de contexto
- Permitir carregamento seletivo de ADRs
- Mapear integrações frontend-backend
- Preparar "terreno" para abordagem proativa

---

## Quando Usar

### ✅ SEMPRE usar `/discover` quando o projeto possui:

1. **ADRs (Architecture Decision Records)** documentadas
   - Em `docs/technical-context/adr/`
   - Ou qualquer localização com decisões arquiteturais formais

2. **Frontend gerado com Lovable**
   - Com mock data que precisa ser integrado ao backend
   - Componentes React com dados hardcoded

3. **Convenções arquiteturais múltiplas**
   - Múltiplos padrões de design
   - Regras de organização de código
   - Constraints técnicas documentadas

4. **Projetos legados com documentação extensa**
   - Muitos docs técnicos
   - Histórico de decisões
   - Múltiplos contribuidores

### ❌ NÃO precisa usar `/discover` quando:

- Projeto sem ADRs formais
- Projeto muito simples (< 5 endpoints)
- Protótipo descartável
- Projeto sem frontend Lovable

---

## Como Funciona

### Fluxo de Execução

```
/discover
    ↓
1. Busca ADRs em docs/technical-context/adr/
    ↓
2. Analisa cada ADR e extrai regras críticas
    ↓
3. Consolida ADRs por categoria (DB, API, Security, etc)
    ↓
4. Busca frontend em apps/frontend/ ou frontend/
    ↓
5. Se encontrar Lovable: invoca @lovable-backend-mapper
    ↓
6. Mapeia todos os mocks do frontend
    ↓
7. Gera contratos de API necessários
    ↓
8. Cria briefing modular estruturado
    ↓
9. Salva em docs/technical-context/briefing/
```

### Agentes Acionados

1. **`@adr-compliance-checker`**
   - Analisa ADRs
   - Extrai regras obrigatórias
   - Categoriza por domínio
   - Gera `adrs-summary.md` e `critical-rules.md`

2. **`@lovable-backend-mapper`** (se frontend Lovable detectado)
   - Escaneia componentes React
   - Identifica padrões de mock data
   - Extrai contratos de API
   - Gera `frontend-lovable.md` com mapeamento completo

---

## Saída Gerada

### Estrutura de Arquivos

```
docs/technical-context/
├── project-briefing.md              # Índice mestre (~150 linhas)
│   └── Links para todos os briefings modulares
│
└── briefing/
    ├── critical-rules.md            # Regras não-negociáveis (~80 linhas)
    │   └── ADRs críticas extraídas e formatadas
    │
    ├── adrs-summary.md              # ADRs consolidadas por categoria
    │   ├── Database & Persistence
    │   ├── API Design
    │   ├── Code Organization
    │   ├── Testing
    │   └── Security
    │
    ├── backend-conventions.md       # Convenções de código backend
    │   ├── Estrutura de pastas
    │   ├── Naming conventions
    │   └── Padrões arquiteturais
    │
    ├── frontend-lovable.md          # Mapeamento de mocks (se aplicável)
    │   ├── Mock #1: User List
    │   ├── Mock #2: Dashboard Stats
    │   └── ... (todos os mocks identificados)
    │
    └── tech-stack.md                # Stack tecnológico
        ├── Backend: Node.js, Prisma, etc
        ├── Frontend: React, Tailwind, etc
        └── Infraestrutura: Docker, CI/CD, etc
```

### Conteúdo de `project-briefing.md`

```markdown
# Project Briefing

Índice mestre do contexto do projeto gerado automaticamente.

## 📚 Briefings Disponíveis

### ⚠️ Regras Críticas (Leitura Obrigatória)
- [critical-rules.md](./briefing/critical-rules.md) (~80 linhas)
  ADRs não-negociáveis que DEVEM ser seguidas

### 📖 ADRs por Categoria
- [adrs-summary.md](./briefing/adrs-summary.md)
  ADRs organizadas por domínio para carregamento seletivo

### 💻 Convenções de Código
- [backend-conventions.md](./briefing/backend-conventions.md)
  Padrões de organização e nomenclatura

### 🎨 Frontend Integration
- [frontend-lovable.md](./briefing/frontend-lovable.md)
  Mapeamento completo de mocks → endpoints

### 🛠️ Stack Tecnológico
- [tech-stack.md](./briefing/tech-stack.md)
  Tecnologias, versões e dependencies

## 🎯 Como Usar

1. **/start**: Carrega `critical-rules.md` + ADRs relevantes seletivamente
2. **/plan**: Lê `frontend-lovable.md` para Mock Removal
3. **/work**: Consulta ADRs ANTES de implementar
```

### Conteúdo de `critical-rules.md`

```markdown
# ⚠️ Regras Críticas do Projeto

Regras arquiteturais NÃO-NEGOCIÁVEIS extraídas das ADRs.

## Database & Persistence

### ADR-001: PostgreSQL como Database Principal
**Regra**: NUNCA usar outro banco sem aprovação arquitetural
**Razão**: Consistência, features necessárias, expertise do time

### ADR-002: Prisma como ORM
**Regra**: Todo acesso ao banco DEVE usar Prisma
**Razão**: Type-safety, migrations, dev experience

## Architecture Patterns

### ADR-007: Repository Pattern Obrigatório
**Regra**: Services NUNCA acessam Prisma diretamente
**Razão**: Isolamento de lógica de dados, testabilidade

**Implementação correta**:
```typescript
// ✅ CORRETO
class UserService {
  constructor(private userRepo: UserRepository) {}
  async getUser(id: string) {
    return this.userRepo.findById(id);
  }
}

// ❌ ERRADO
class UserService {
  async getUser(id: string) {
    return prisma.user.findUnique({ where: { id } });
  }
}
```

## Code Organization

### ADR-003: Shared Types Location
**Regra**: ENUMs e types compartilhados em `/shared/enums/` e `/shared/types/`
**Razão**: Evitar duplicação, facilitar refatoração

... (todas as ADRs críticas)
```

### Conteúdo de `frontend-lovable.md`

```markdown
# 🎨 Frontend Lovable - Mapeamento de Mocks

Identificação automática de mocks e endpoints necessários.

## 📊 Resumo

- **Componentes escaneados**: 42
- **Mocks identificados**: 8
- **Endpoints necessários**: 12

---

## Mock #1: User List

**Componente**: `apps/frontend/src/components/UserList.tsx:15-20`

**Mock Atual**:
```typescript
const [users] = useState([
  { id: 1, name: "Alice", email: "alice@example.com", role: "admin" },
  { id: 2, name: "Bob", email: "bob@example.com", role: "user" }
]);
```

**Endpoint Necessário**:
```
GET /api/users
Response: User[]

interface User {
  id: number;
  name: string;
  email: string;
  role: "admin" | "user";
}
```

**Checklist de Implementação**:

**Backend**:
- [ ] Criar UserRepository
- [ ] Criar UserService.getAll()
- [ ] Criar endpoint GET /api/users
- [ ] Testes de integração

**Frontend**:
- [ ] Remover mock de UserList.tsx:15-20
- [ ] Substituir por useFetch('/api/users')
- [ ] Adicionar loading state
- [ ] Adicionar error handling
- [ ] Teste com MSW

---

## Mock #2: Dashboard Stats

... (todos os mocks identificados)
```

---

## Integração com Outros Comandos

### `/start` - Context Enhancement

**ANTES do `/discover`**:
```bash
/start "user-authentication"
# Gera context.md básico sem ADRs
```

**DEPOIS do `/discover`**:
```bash
/start "user-authentication"

# Comando pergunta automaticamente:
# 1. Esta feature envolve frontend Lovable? (s/n)
# 2. Áreas do backend impactadas:
#    [ ] API/Controllers
#    [ ] Database/ORM
#    [ ] Autenticação/Autorização
#    ...

# Carrega apenas ADRs relevantes
# Enriquece context.md com:
# - ⚠️ Regras Críticas do Projeto (critical-rules.md copiado)
# - 📚 ADRs Relevantes (links para seções específicas)
# - 🎨 Frontend Integration (resumo de mocks, se aplicável)
```

### `/plan` - Mock Removal

**COM `/discover` executado**:
```bash
/plan

# Lê frontend-lovable.md
# Inclui automaticamente fases de Mock Removal:

## FASE X: Integração Frontend

### Remover Mock #1: User List
[Checklist completo gerado automaticamente]

### Remover Mock #2: Dashboard Stats
[Checklist completo gerado automaticamente]
```

### `/work` - Abordagem Proativa

**COM briefing do `/discover`**:
```bash
/work "sessions/user-authentication"

# Fluxo interno:
# 1. Lê "⚠️ Regras Críticas" do context.md
# 2. Identifica ADR-007: Repository Pattern
# 3. Planeja: Criar UserRepository ANTES de UserService
# 4. Implementa conforme ADRs
# 5. Valida: @adr-compliance-checker confirma 100%
```

---

## Exemplos Práticos

### Exemplo 1: Projeto Greenfield com Lovable

```bash
# Dia 1: Setup inicial
/discover

# Resultado:
# ✅ ADRs não encontradas (projeto novo)
# ✅ Frontend Lovable detectado
# ✅ 8 mocks identificados
# ✅ 12 endpoints mapeados
# ✅ Briefing gerado em 30 segundos

# Dia 2-4: Desenvolver backend
/start "api-implementation"
# Pergunta: Envolve frontend Lovable? s
# Carrega: frontend-lovable.md

/plan
# Inclui fases de Mock Removal automaticamente

/work "sessions/api-implementation"
# Implementa endpoints conforme contratos do Lovable

# Dia 5: Integração
/work "sessions/frontend-integration"
# Segue checklists de Mock Removal
```

### Exemplo 2: Projeto Legacy com 50 ADRs

```bash
# Setup único
/discover

# Resultado:
# ✅ 50 ADRs analisadas
# ✅ 15 regras críticas extraídas
# ✅ ADRs consolidadas por 8 categorias
# ✅ Briefing gerado em 2 minutos

# Feature 1
/start "add-payment-module"
# Pergunta: Áreas impactadas?
# [x] API/Controllers
# [x] Database/ORM
# [x] Security

# Carrega APENAS ADRs relevantes:
# - Seção "API Design" de adrs-summary.md
# - Seção "Database & Persistence"
# - Seção "Security"
# Total: ~200 linhas ao invés de 5000+

# Economia: 60% de tokens
```

### Exemplo 3: Feature Simples (sem Discovery)

```bash
# Projeto sem ADRs, sem Lovable
# Pular /discover completamente

/start "fix-typo-on-homepage"
/plan
/work "sessions/fix-typo"

# Workflow tradicional preservado 100%
```

---

## Troubleshooting

### Problema: "/discover não encontra ADRs"

**Sintomas**:
```
/discover
✅ Projeto escaneado
❌ Nenhuma ADR encontrada
⚠️  Briefing gerado sem ADRs
```

**Causas possíveis**:
1. ADRs não estão em `docs/technical-context/adr/`
2. ADRs não seguem formato esperado
3. Pasta ADR vazia

**Soluções**:
```bash
# Verificar localização
ls docs/technical-context/adr/

# Se ADRs estão em outro lugar, mover:
mv docs/adr docs/technical-context/adr

# Re-executar
/discover
```

---

### Problema: "Frontend Lovable não detectado"

**Sintomas**:
```
/discover
✅ ADRs analisadas
❌ Frontend não detectado
⚠️  frontend-lovable.md não gerado
```

**Causas possíveis**:
1. Frontend não está em `apps/frontend/` ou `frontend/`
2. Não é projeto Lovable (não tem padrões reconhecíveis)

**Soluções**:
```bash
# Verificar estrutura
ls apps/frontend/src/components/

# Se frontend está em outro lugar:
# Invocar agente manualmente
@lovable-backend-mapper

# Especificar caminho custom (se agente suportar)
```

---

### Problema: "Briefing gerado está incompleto"

**Sintomas**:
- `critical-rules.md` vazio
- `adrs-summary.md` com poucas ADRs
- Categorias faltando

**Causas possíveis**:
1. ADRs mal formatadas
2. ADRs sem palavras-chave reconhecíveis
3. Bug no parser de ADRs

**Soluções**:
```bash
# Verificar formato de uma ADR
cat docs/technical-context/adr/001-database-choice.md

# Formato esperado:
# # ADR-001: Database Choice
# ## Context
# ## Decision
# ## Consequences

# Se formato estiver incorreto, padronizar ADRs

# Re-executar /discover
```

---

### Problema: "Context Enhancement não funciona no /start"

**Sintomas**:
```bash
/start "new-feature"
# Não pergunta sobre áreas impactadas
# Não carrega briefing
# context.md não contém regras críticas
```

**Causas possíveis**:
1. `/discover` não foi executado
2. Briefing não existe em `docs/technical-context/project-briefing.md`

**Soluções**:
```bash
# Verificar se briefing existe
ls docs/technical-context/project-briefing.md

# Se não existe, executar /discover primeiro
/discover

# Depois executar /start
/start "new-feature"
```

---

## Métricas de Sucesso

### Antes do `/discover` (v1.x)

- **Tokens por feature**: 10.000-15.000
- **Violações de ADR**: ~15 por feature
- **Tempo de correção**: 2-3 horas
- **Retrabalho**: ~30%

### Depois do `/discover` (v2.0)

- **Tokens por feature**: 4.000-6.000 (60% economia)
- **Violações de ADR**: ~1 por feature (edge cases)
- **Tempo de correção**: <30 min
- **Retrabalho**: <5%

### ROI

```
Projeto com 10 features:
- Economia de tokens: 60.000 tokens salvos
- Economia de tempo: 20-25 horas
- Qualidade de código: 95% conformidade vs 70%
```

---

## Próximos Passos

Após executar `/discover` com sucesso:

1. ✅ Revise o briefing gerado
2. ✅ Ajuste `critical-rules.md` se necessário
3. ✅ Valide mapeamento de mocks (se Lovable)
4. ✅ Execute `/start` para primeira feature
5. ✅ Observe Context Enhancement em ação

---

## Recursos Relacionados

- [adr-proactive-approach.md](./adr-proactive-approach.md) - Como usar ADRs proativamente
- [COMMANDS.md](../COMMANDS.md) - Referência de todos os comandos
- [WORKFLOWS.md](../WORKFLOWS.md) - Workflows por cenário

---

**Última atualização**: 2025-01-26
**Versão**: 2.0.0
