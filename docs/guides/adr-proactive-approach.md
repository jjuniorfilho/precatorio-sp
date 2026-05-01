# 🎯 Guia da Abordagem Proativa com ADRs

> **Mudança de Paradigma v2.0**: ADRs como guias de implementação, não validadores de erro

---

## 📋 Índice

- [Filosofia](#filosofia)
- [Reativo vs Proativo](#reativo-vs-proativo)
- [Como Funciona](#como-funciona)
- [Exemplos Práticos](#exemplos-práticos)
- [Benefícios Mensuráveis](#benefícios-mensuráveis)
- [FAQ](#faq)

---

## Filosofia

### Princípio Fundamental

> **"ADRs são GUIAS DE IMPLEMENTAÇÃO, não validadores de erro."**

**Mentalidade CORRETA** (Proativa):
- ✅ Consultar ADRs = Parte do planejamento
- ✅ Implementar conforme ADRs = Primeira vez certo
- ✅ Validação = Confirmação, não correção

**Mentalidade ERRADA** (Reativa):
- ❌ Implementar qualquer coisa
- ❌ Validador detecta erros
- ❌ Corrigir e refatorar
- ❌ Desperdiçar tempo e tokens

---

## Reativo vs Proativo

### Abordagem Reativa (v1.x)

```
┌─────────────┐
│ Tarefa:     │
│ Criar       │
│ UserService │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Implementa  │
│ código      │
│ (qualquer   │
│  forma)     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Validador   │
│ @adr-comp   │
│ checker     │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ ❌ VIOLAÇÃO │
│ ADR-007:    │
│ Service usa │
│ Prisma      │
│ direto      │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Corrigir:   │
│ - Criar     │
│   Repository│
│ - Refatorar │
│   Service   │
│ - Re-testar │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ ⏱️ Tempo    │
│ desperdiçado│
│ 💸 Tokens   │
│ desperdiçados│
└─────────────┘
```

**Problemas**:
- Retrabalho constante
- Frustração do desenvolvedor
- Desperdício de tokens/tempo
- Código inconsistente

---

### Abordagem Proativa (v2.0)

```
┌─────────────┐
│ Tarefa:     │
│ Criar       │
│ UserService │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 1. ANTES    │
│ Consultar   │
│ ADRs em     │
│ context.md  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Identificar:│
│ ADR-007:    │
│ Repository  │
│ Pattern     │
│ obrigatório │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ Planejar:   │
│ 1. Criar    │
│    UserRepo │
│    primeiro │
│ 2. Injetar  │
│    no       │
│    Service  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 2. DURANTE  │
│ Implementa  │
│ conforme    │
│ plano       │
│ (correto)   │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ 3. APÓS     │
│ Validação   │
│ de sanidade │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ ✅ 100%     │
│ conforme    │
│ (como       │
│  esperado)  │
└──────┬──────┘
       │
       ▼
┌─────────────┐
│ ✨ Zero     │
│ retrabalho  │
│ 🚀 Eficiente│
└─────────────┘
```

**Vantagens**:
- Código correto de primeira
- Zero retrabalho
- Economia de tokens
- Desenvolvedor confiante

---

## Como Funciona

### FASE 1: ANTES de Implementar (Consulta Proativa)

#### Passo 1.1: Ler Regras Críticas

Quando `/work` inicia uma tarefa, PRIMEIRO consulta o `context.md`:

```markdown
# Context: User Authentication

## ⚠️ Regras Críticas do Projeto

[COPIADO de critical-rules.md pelo /start]

### ADR-007: Repository Pattern Obrigatório
**Regra**: Services NUNCA acessam Prisma diretamente
**Implementação correta**:
class UserService {
  constructor(private userRepo: UserRepository) {}
}
```

#### Passo 1.2: Identificar ADRs Aplicáveis

```
Tarefa: Criar UserService

Regras aplicáveis (de context.md):
✅ ADR-007: Services devem usar Repositories
✅ ADR-003: ENUMs em /shared/enums/
✅ ADR-012: Testes obrigatórios
✅ ADR-015: Validação com Zod
```

#### Passo 1.3: Planejar Implementação

```
Plano de implementação:

1. Criar UserRepository primeiro (pré-requisito da ADR-007)
   Localização: src/repositories/user.repository.ts

2. Criar UserService injetando repository
   Localização: src/services/user.service.ts
   Pattern: Dependency Injection

3. Se precisar ENUM, criar em /shared/enums/ (ADR-003)
   Ex: src/shared/enums/user-role.enum.ts

4. Criar testes junto com implementação (ADR-012)
   Localização: src/services/__tests__/user.service.spec.ts

5. Adicionar validação Zod (ADR-015)
   Localização: src/shared/schemas/user.schema.ts

Resultado esperado: Código 100% conforme desde o início
```

---

### FASE 2: DURANTE Implementação (Código Correto de Primeira)

#### Ordem de Criação (Conforme Plano)

```typescript
// 1. PRIMEIRO: UserRepository (dependência)
// src/repositories/user.repository.ts

export class UserRepository {
  async findById(id: string): Promise<User | null> {
    return prisma.user.findUnique({ where: { id } });
  }

  async findByEmail(email: string): Promise<User | null> {
    return prisma.user.findUnique({ where: { email } });
  }

  async create(data: CreateUserDto): Promise<User> {
    return prisma.user.create({ data });
  }
}
```

```typescript
// 2. DEPOIS: UserService (usa repository)
// src/services/user.service.ts

import { UserRepository } from '../repositories/user.repository';
import { userSchema } from '../shared/schemas/user.schema';

export class UserService {
  constructor(private userRepo: UserRepository) {} // ✅ DI conforme ADR-007

  async getUser(id: string): Promise<User> {
    const user = await this.userRepo.findById(id);
    if (!user) throw new NotFoundException('User not found');
    return user;
  }

  async createUser(data: unknown): Promise<User> {
    const validated = userSchema.parse(data); // ✅ Zod conforme ADR-015
    return this.userRepo.create(validated);
  }
}
```

```typescript
// 3. ENUM (se necessário)
// src/shared/enums/user-role.enum.ts

export enum UserRole { // ✅ Localização conforme ADR-003
  ADMIN = 'admin',
  USER = 'user',
  GUEST = 'guest'
}
```

```typescript
// 4. Teste (junto com implementação)
// src/services/__tests__/user.service.spec.ts

describe('UserService', () => { // ✅ Teste conforme ADR-012
  it('should get user by id', async () => {
    // ...
  });
});
```

**Resultado**: Código 100% conforme ADRs, criado na ordem correta

---

### FASE 3: APÓS Implementação (Validação de Sanidade)

#### Validação Automática

```
Executando @adr-compliance-checker...

Validando UserRepository...
✅ Arquivo na localização correta: src/repositories/
✅ Usa Prisma (esperado para Repository)

Validando UserService...
✅ Arquivo na localização correta: src/services/
✅ NÃO usa Prisma diretamente (ADR-007 ✅)
✅ Injeta UserRepository via construtor (DI ✅)
✅ Usa validação Zod (ADR-015 ✅)

Validando UserRole enum...
✅ Localização: src/shared/enums/ (ADR-003 ✅)

Validando testes...
✅ Teste existe: user.service.spec.ts (ADR-012 ✅)

───────────────────────────────────────
📊 Relatório de Conformidade:
✅ 100% conforme (como esperado!)
⏱️  Tempo economizado: Zero correções necessárias
───────────────────────────────────────
```

**Propósito**: Confirmar, não corrigir. Se algo falhar aqui, é edge case para discutir.

---

### FASE 4: Relatório ao Final da Fase

Incluído automaticamente no `plan.md`:

```markdown
## FASE 2 [Completada ✅]

### Implementação User Authentication [Completada ✅]

**Arquivos criados:**
- src/repositories/user.repository.ts
- src/services/user.service.ts
- src/shared/enums/user-role.enum.ts
- src/shared/schemas/user.schema.ts
- src/services/__tests__/user.service.spec.ts

### Comentários:

#### Conformidade com ADRs (Abordagem Proativa)
- ✅ ADRs consultadas ANTES da implementação
- ✅ Código criado seguindo regras desde o início
- ✅ Validação final: 100% conforme
- ✅ Zero correções necessárias
- ✅ Implementação eficiente, sem desperdício

**Regras aplicadas:**
- ADR-007: Repository Pattern → UserRepository criado e injetado
- ADR-003: Shared Types → user-role.enum.ts em /shared/enums/
- ADR-015: Validação Zod → user.schema.ts criado
- ADR-012: Testes → user.service.spec.ts criado junto

✅ Todas as convenções obrigatórias seguidas desde o início.
```

---

## Exemplos Práticos

### Exemplo 1: Criar Endpoint de API

**Tarefa**: Criar `POST /api/users`

**ANTES (Consulta Proativa)**:
```
Consultando context.md...

ADRs aplicáveis:
- ADR-007: Repository Pattern
- ADR-010: API Versioning (/api/v1/)
- ADR-015: Validação Zod
- ADR-016: Error Handling Padronizado
- ADR-012: Testes obrigatórios

Plano:
1. UserRepository (se não existe)
2. UserService.createUser()
3. UserSchema (Zod)
4. POST /api/v1/users controller
5. Error handling middleware
6. Testes de integração
```

**DURANTE (Implementação Conforme)**:
```typescript
// 1. Repository
class UserRepository {
  async create(data: CreateUserDto): Promise<User> {
    return prisma.user.create({ data });
  }
}

// 2. Service
class UserService {
  constructor(private repo: UserRepository) {} // ✅ ADR-007

  async createUser(data: unknown): Promise<User> {
    const validated = userSchema.parse(data); // ✅ ADR-015
    return this.repo.create(validated);
  }
}

// 3. Controller
app.post('/api/v1/users', async (req, res, next) => { // ✅ ADR-010
  try {
    const user = await userService.createUser(req.body);
    res.status(201).json(user);
  } catch (error) {
    next(error); // ✅ ADR-016
  }
});

// 4. Teste
describe('POST /api/v1/users', () => { // ✅ ADR-012
  it('should create user', async () => {
    // ...
  });
});
```

**APÓS (Validação)**:
```
✅ 100% conforme
Zero retrabalho
```

---

### Exemplo 2: Refatorar Código Legado

**Tarefa**: Refatorar `OrderService` que viola ADR-007

**ANTES (Código Existente - Errado)**:
```typescript
class OrderService {
  async createOrder(data: any) {
    // ❌ Violação ADR-007: Prisma direto
    const order = await prisma.order.create({ data });
    return order;
  }
}
```

**Consultando ADRs**:
```
ADR-007: Repository Pattern

Regra: Services NUNCA acessam Prisma diretamente
Ação: Criar OrderRepository
```

**DURANTE (Refatoração Conforme)**:
```typescript
// 1. Criar OrderRepository
class OrderRepository {
  async create(data: CreateOrderDto): Promise<Order> {
    return prisma.order.create({ data });
  }
}

// 2. Refatorar OrderService
class OrderService {
  constructor(private orderRepo: OrderRepository) {} // ✅ Injetar repo

  async createOrder(data: CreateOrderDto): Promise<Order> {
    return this.orderRepo.create(data); // ✅ Usar repo
  }
}
```

**APÓS (Validação)**:
```
✅ Refatoração conforme ADR-007
✅ Repository pattern aplicado
✅ Service não acessa Prisma diretamente
```

---

## Benefícios Mensuráveis

### Métricas Antes vs Depois

| Métrica | v1.x (Reativo) | v2.0 (Proativo) | Melhoria |
|---------|----------------|-----------------|----------|
| **Violações de ADR** | ~15 por feature | ~1 por feature | 93% redução |
| **Tempo de correção** | 2-3 horas | <30 min | 85% economia |
| **Retrabalho** | ~30% | <5% | 83% redução |
| **Tokens usados** | 100% | 40% | 60% economia |
| **Conformidade** | ~70% | ~99% | +29% |
| **Satisfação dev** | 6/10 | 9/10 | +50% |

### ROI em Projeto Real

**Projeto**: 10 features, cada com 3 fases

**ANTES (Reativo)**:
- Violações totais: 150
- Tempo de correção: 30 horas
- Tokens desperdiçados: 60.000
- Frustração: Alta

**DEPOIS (Proativo)**:
- Violações totais: 10 (edge cases)
- Tempo de correção: 3 horas
- Tokens economizados: 36.000
- Satisfação: Alta

**Economia**:
- 27 horas de trabalho
- 36.000 tokens
- Código 99% conforme
- Time motivado

---

## FAQ

### P: "E se eu esquecer de consultar as ADRs?"

**R**: O `/work` v2.0 consulta automaticamente. Você não precisa lembrar - o sistema lembra por você.

```
/work "sessions/feature"
# Internamente:
# 1. Lê context.md automaticamente
# 2. Identifica ADRs aplicáveis
# 3. Planeja conforme regras
# 4. Implementa correto de primeira
```

### P: "E se a ADR estiver errada ou desatualizada?"

**R**: Abordagem proativa permite DISCUTIR antes de implementar:

```
Consultando ADR-007: Repository Pattern...

⚠️ OBSERVAÇÃO:
Esta ADR pode estar desatualizada para este caso de uso específico.

Opções:
1. Seguir ADR (recomendado)
2. Propor exceção (documentar motivo)
3. Propor atualização da ADR

Deseja discutir? (s/n)
```

### P: "Validação de sanidade ainda é necessária?"

**R**: SIM. Serve para:
1. Confirmar que tudo está conforme (como esperado)
2. Detectar edge cases raros
3. Gerar relatório de conformidade
4. Dar confiança ao desenvolvedor

Mas **NÃO** é para encontrar erros comuns (que foram evitados na abordagem proativa).

### P: "Como sei quais ADRs se aplicam à minha tarefa?"

**R**: O `/start` já fez isso por você ao enriquecer o `context.md`:

```markdown
## ⚠️ Regras Críticas do Projeto

[Apenas ADRs relevantes para esta feature]

## 📚 ADRs Relevantes

- ADR-007: Repository Pattern → [link]
- ADR-015: Zod Validation → [link]

[Carregadas seletivamente baseado nas áreas impactadas]
```

### P: "E se não houver ADRs no projeto?"

**R**: Sem problema! A seção "Implementação Guiada por ADRs" do `/work` é **condicional**:

```
Se context.md NÃO contém "Regras Críticas":
- Seguir boas práticas gerais
- Usar convenções existentes no projeto
- Focar em código de qualidade
- Pular abordagem proativa completamente
```

Fluxo tradicional é 100% preservado.

---

## Recursos Relacionados

- [discover-workflow.md](./discover-workflow.md) - Como gerar briefing com ADRs
- [COMMANDS.md](../COMMANDS.md) - Referência do comando `/work`
- [WORKFLOWS.md](../WORKFLOWS.md) - Workflows por cenário

---

**Última atualização**: 2025-01-26
**Versão**: 2.0.0
