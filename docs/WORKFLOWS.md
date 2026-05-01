# 🔄 Workflows Cortex por Cenário

> **Versão 2.0** - Context Enhancement Edition
> Guias práticos para diferentes tipos de projeto

---

## 📑 Índice

- [Cenário 1: Greenfield com Lovable + ADRs](#cenário-1-greenfield-com-lovable--adrs)
- [Cenário 2: Greenfield Tradicional](#cenário-2-greenfield-tradicional)
- [Cenário 3: Feature em Projeto com ADRs](#cenário-3-feature-em-projeto-com-adrs)
- [Cenário 4: Projeto Legacy](#cenário-4-projeto-legacy)
- [Cenário 5: Brainstorming de Produto](#cenário-5-brainstorming-de-produto)
- [Cenário 6: Investigação Forense de Bug](#cenário-6-investigação-forense-de-bug)
- [Comparação de Workflows](#comparação-de-workflows)

---

## Cenário 1: Greenfield com Lovable + ADRs

**Quando usar**: Projeto novo que usará Lovable para frontend e possui ADRs definidas

**Duração total**: ~14 dias

**Benefícios do v2.0**:
- ✅ Discovery automático economiza 60% de tokens
- ✅ Mapeamento de mocks elimina retrabalho
- ✅ Abordagem proativa evita violações de ADRs

### FASE 0: Discovery (30 min) 🆕

```bash
/discover
```

**O que acontece:**
1. Analisa todas as ADRs em `docs/technical-context/adr/`
2. Consolida regras críticas
3. Gera briefing modular
4. Prepara contexto para as próximas fases

**Saída:**
```
docs/technical-context/
├── project-briefing.md
└── briefing/
    ├── critical-rules.md
    ├── adrs-summary.md
    ├── backend-conventions.md
    └── tech-stack.md
```

---

### FASE 1: Fundação de Contexto (Dias 1-2)

```bash
# 1. Preparação
/warm-up "kickoff do projeto"

# 2. Levantamento
/collect "requisitos empresariais e técnicos"

# 3. Documentação estratégica
/build-business-docs "contexto empresarial completo"
/build-tech-docs "arquitetura técnica e stack"
/build-index "organizar master docs"

# 4. Validação
/check "validar requisitos contra master docs"
```

**Agentes acionados**: `@discovery-analyst`, `@project-blueprint-guardian`

---

### FASE 2: Design de Dados & Contratos de API (Dias 3-4)

```bash
# 1. PRD
/spec "PRD com foco em contratos de API"

# 2. Arquitetura
/light-arch "modelagem de dados + contratos de API"
```

**Deve incluir:**
- Modelagem de entidades
- Schemas de banco de dados
- **Contratos detalhados de API** (crítico para Lovable)
  - Endpoints
  - Métodos HTTP
  - Request/Response payloads
  - Estruturas de dados

**Agentes acionados**: `@database-architect`, `@backend-architect`

---

### FASE 3: Geração de Frontend com Lovable (Dia 5)

```bash
# Invocar agente via @ no chat
@lovable-frontend-prompt-generator

# O agente:
# ✅ Analisa todos os master docs
# ✅ Lê contratos de API
# ✅ Gera prompt completo para Lovable
# ✅ Define mock data strategy

# Copiar prompt gerado e colar no Lovable
```

**Resultado**: Frontend React 100% navegável com mock data

**Agente acionado**: `@lovable-frontend-prompt-generator`

---

### FASE 4: Implementação Backend (Dias 6-9)

```bash
# 1. Iniciar (com Context Enhancement automático)
/start "nome-do-projeto-backend"

# 🆕 v2.0: O comando pergunta:
# - Esta feature envolve frontend Lovable? [s/n]
# - Áreas do backend impactadas? [checkboxes]
#
# Carrega apenas ADRs relevantes (economiza tokens)
# Enriquece context.md com regras críticas

# 2. Planejar
/plan "implementação de API seguindo contratos"

# 🆕 v2.0: Inclui automaticamente fases de Mock Removal
# se frontend Lovable foi detectado

# 3. Implementar (Abordagem Proativa)
/work "sessions/nome-do-projeto-backend"

# 🆕 v2.0: Fluxo interno automático:
# ANTES: Consulta ADRs → Planeja implementação
# DURANTE: Código correto desde o início
# APÓS: Validação confirma conformidade
#
# Resultado: Código 100% conforme, zero retrabalho

# 4. Validar
/pre-pr
/pr
```

**Agentes acionados**: `@backend-python-specialist`, `@test-engineer`, `@code-reviewer`, `@adr-compliance-checker`

**Diferença v2.0**:
```
❌ v1.x (Reativo): Código → Erro → Corrige → Desperdiça tokens
✅ v2.0 (Proativo): ADRs → Código OK → Valida → Zero retrabalho
```

---

### FASE 5: Integração Frontend-Backend (Dias 10-11)

```bash
# Usar mapeamento gerado pelo /discover
# Mocks já identificados em:
# docs/technical-context/briefing/frontend-lovable.md

# Implementar integrações
/work "sessions/frontend-integration"

# 🆕 v2.0: plan.md já contém checklist para cada mock:
# - Pré-requisito backend
# - Tarefas frontend
# - Validação de integração
```

**Checklist automático (exemplo)**:
```markdown
### Remover Mock #1: User List

**Backend:**
- [x] GET /api/users criado
- [x] Testes passando

**Frontend:**
- [ ] Remover mock de UserList.tsx:15-20
- [ ] Substituir por useFetch('/api/users')
- [ ] Loading state
- [ ] Error handling
- [ ] Teste com MSW
```

**Agente acionado**: `@lovable-backend-mapper`

---

### FASE 6: Validação Final (Dia 12)

```bash
/check "validação completa do projeto"

# Opcional: Agente custom de alinhamento Lovable
@lovable-alignment-checker
```

---

### FASE 7: Refinamento (Dias 13-14)

```bash
/refine "melhorias de UX e edge cases"
/docs "documentação técnica completa"
/pre-pr
/pr
```

---

## Cenário 2: Greenfield Tradicional

**Quando usar**: Projeto novo SEM Lovable ou ADRs formais

**Duração total**: 1-2 horas (setup) + desenvolvimento

### Percurso Acelerado (30-45 min)

```bash
/collect "levantamento ágil de necessidades"
/build-business-docs "contexto empresarial core"
/spec "PRD enxuto e viável"
/start "<feature-name>"
/plan
/work "sessions/<feature-name>"
```

### Percurso Completo (2-3 horas)

```bash
/warm-up → /collect → /check → /refine →
/build-business-docs → /build-tech-docs → /spec → /build-index →
/light-arch → /task → /start → /plan → /work → /pre-pr → /pr
```

**Diferença para Cenário 1**: Sem `/discover` (não há ADRs/Lovable para mapear)

---

## Cenário 3: Feature em Projeto com ADRs

**Quando usar**: Adicionar feature em projeto existente que possui ADRs

**Duração**: ~2-5 dias por feature

### Primeira Feature (com Discovery)

```bash
# Execute /discover UMA vez por projeto
/discover

# Depois, para cada feature:
/start "<feature-slug>"
/plan
/work "sessions/<feature-slug>"
/pre-pr
/pr
```

### Features Seguintes (Discovery já executado)

```bash
# Apenas comandos de engenharia
/start "<feature-slug>"
/plan
/work "sessions/<feature-slug>"
/pre-pr
/pr
```

**Benefício v2.0**: Context Enhancement reutiliza briefing do `/discover`

---

## Cenário 4: Projeto Legacy

**Quando usar**: Projeto existente com documentação extensa

**Duração inicial**: 1 dia (discovery) + feature development

### Setup Inicial

```bash
# 1. Execute /discover para mapear projeto
/discover

# Isso vai:
# ✅ Analisar ADRs existentes
# ✅ Mapear convenções de código
# ✅ Identificar frontend se houver
# ✅ Gerar briefing modular

# 2. Para cada feature, workflow normal:
/start → /plan → /work → /pre-pr → /pr
```

**Vantagem v2.0**: Economiza até 60% de tokens em projetos legados com muitas ADRs

---

## Cenário 5: Brainstorming de Produto

**Quando usar**: Decisões estratégicas de produto, ideação de features

**Duração**: 30-60 min

### Workflow

```bash
/brainstorm "<tópico a explorar>"

# Exemplo:
/brainstorm "estratégia de onboarding de novos usuários"
```

**Fases automáticas**:
1. **Contextualização** - Entender problema
2. **Exploração Divergente** - Gerar ideias
3. **Convergência** - Avaliar opções
4. **Recomendação** - Escolher caminho
5. **Documentação** - Registrar decisões

**Saída**:
```
docs/business-context/brainstorm/
└── onboarding-strategy-2025-01-26.md
```

---

## Cenário 6: Investigação Forense de Bug

**Quando usar**: Bug reportado que precisa de investigação profunda antes de virar issue

**Duração**: 30-60 min

### Workflow

```bash
/bug-collect "<descrição do bug>"

# Exemplo:
/bug-collect "dashboard mostra valores diferentes do relatório"
```

**Fases automáticas**:
1. **Intake** - Entender o bug e triagem
2. **Reconhecimento** - Mapear projeto e stack
3. **Investigação Forense** - Código + Banco + Git em paralelo
4. **Síntese** - Root-cause analysis com evidências cruzadas
5. **Rascunho** - Issue detalhada para aprovação do usuário
6. **Criação** - Publicar no Linear ou GitHub Issues

**Diferença do `/collect`**:
- `/collect` coleta requisitos → entrega requisitos brutos
- `/bug-collect` investiga bugs → entrega issue com root-cause analysis, evidências e abordagens de fix

**Saída**: Issue criada no projeto de gestão com:
- Root-cause analysis completo
- Code-paths envolvidos (arquivo:linha)
- Evidências de banco de dados
- Quantificação de impacto
- Abordagens de fix com trade-offs
- Casos de teste para validação

---

## Comparação de Workflows

### Por Duração

| Workflow | Setup | Desenvolvimento | Total |
|----------|-------|-----------------|-------|
| Greenfield + Lovable + ADRs | 2-3 dias | 11-12 dias | ~14 dias |
| Greenfield Tradicional | 1-2 horas | Variável | Variável |
| Feature (com Discovery) | 0 min* | 2-5 dias | 2-5 dias |
| Legacy (primeira vez) | 1 dia | Variável | Variável |
| Brainstorming | 0 min | 30-60 min | 30-60 min |
| Bug Forense | 0 min | 30-60 min | 30-60 min |

*Reutiliza briefing do `/discover` executado anteriormente

### Por Complexidade

| Complexidade | Workflow Recomendado | Comandos Chave |
|--------------|---------------------|----------------|
| **Baixa** | Greenfield Tradicional Acelerado | `/collect` → `/spec` → `/start` |
| **Média** | Feature em Projeto Existente | `/discover` → `/start` → `/plan` → `/work` |
| **Alta** | Greenfield + Lovable + ADRs | `/discover` → Workflow completo 7 fases |
| **Muito Alta** | Legacy Enterprise | `/discover` → `/start` (com Context Enhancement) |

### Por Tipo de Projeto

| Tipo | Tem ADRs? | Tem Lovable? | Usar `/discover`? | Workflow |
|------|-----------|--------------|-------------------|----------|
| **Greenfield Simples** | ❌ | ❌ | ❌ | Tradicional |
| **Greenfield com Lovable** | ❌ | ✅ | ✅ Recomendado | Com `/discover` (mapeia mocks) |
| **Greenfield com ADRs** | ✅ | ❌ | ✅ Obrigatório | Com `/discover` (carrega ADRs) |
| **Greenfield Completo** | ✅ | ✅ | ✅ Obrigatório | Workflow completo v2.0 |
| **Legacy** | ✅ | ❓ | ✅ Obrigatório | Discovery + Feature |
| **Feature Rápida** | ❌ | ❌ | ❌ | `/start` → `/plan` → `/work` |

---

## 🎯 Decisão Rápida: Qual Workflow Usar?

### Perguntas para Decidir:

1. **Seu projeto tem ADRs documentadas?**
   - ✅ Sim → USAR `/discover`
   - ❌ Não → Workflow tradicional

2. **Vai usar Lovable para frontend?**
   - ✅ Sim → USAR `/discover` + Workflow Lovable
   - ❌ Não → Workflow sem Lovable

3. **É primeira feature ou projeto novo?**
   - Primeira → Executar `/discover` primeiro
   - Seguintes → Reutilizar briefing

4. **Nível de complexidade?**
   - Baixa → Percurso acelerado
   - Média/Alta → Percurso completo
   - Muito Alta → `/discover` + Percurso completo

### Árvore de Decisão

```
Tem ADRs OU Lovable?
├─ SIM → Execute /discover
│  ├─ Greenfield? → Workflow completo 7 fases
│  └─ Feature? → /start → /plan → /work
│
└─ NÃO → Workflow tradicional
   ├─ Simples? → Percurso acelerado
   └─ Complexo? → Percurso completo
```

---

## 📊 Métricas de Sucesso por Workflow

### Greenfield + Lovable + ADRs (v2.0)

**Antes (v1.x)**:
- Tokens usados: 100%
- Retrabalho: ~30%
- Violações de ADR: ~15 por feature
- Tempo de integração: 3-4 dias

**Depois (v2.0)**:
- Tokens usados: 40%
- Retrabalho: <5%
- Violações de ADR: ~1 por feature (edge cases)
- Tempo de integração: 1-2 dias

**ROI**: 60% economia de tempo + 60% economia de tokens

---

## 🛠️ Troubleshooting

### "/discover não encontra ADRs"

**Causa**: ADRs não estão em `docs/technical-context/adr/`

**Solução**: Mover ADRs para localização esperada ou ajustar comando

### "/start não usa briefing"

**Causa**: `/discover` não foi executado ou briefing não existe

**Solução**: Executar `/discover` primeiro

### "Muitas ADRs carregadas no context.md"

**Causa**: Todas as ADRs copiadas ao invés de seletivas

**Solução**: Responder perguntas do `/start` para carregar apenas relevantes

### "Mocks não mapeados corretamente"

**Causa**: Frontend não segue padrões detectáveis

**Solução**: Invocar `@lovable-backend-mapper` manualmente e revisar

---

## 📚 Recursos Relacionados

- [COMMANDS.md](./COMMANDS.md) - Referência completa de comandos
- [CORTEX.md](./CORTEX.md) - Guia de uso principal
- [CHANGELOG.md](../../CHANGELOG.md) - Mudanças do v2.0
- [guides/discover-workflow.md](./guides/discover-workflow.md) - Guia detalhado do `/discover`
- [guides/adr-proactive-approach.md](./guides/adr-proactive-approach.md) - Filosofia proativa

---

**Última atualização**: 2026-02-22
**Versão do Framework**: 2.4.0
