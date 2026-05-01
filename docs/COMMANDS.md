# 📘 Referência Completa de Comandos Cortex

> **Versão 2.4** - Atualizado com Bug Collect Forense
> Última atualização: 2026-02-22

Este guia documenta todos os comandos disponíveis no Cortex Framework, organizados por categoria e casos de uso.

---

## 📑 Índice

- [Comandos de Engenharia](#comandos-de-engenharia)
- [Comandos de Produto](#comandos-de-produto)
- [Comandos de Relatórios](#comandos-de-relatórios)
- [Comandos de Documentação](#comandos-de-documentação)
- [Comandos de Discovery](#comandos-de-discovery)
- [Comparação de Comandos](#comparação-de-comandos)

---

## 🔧 Comandos de Engenharia

### `/discover` 🆕

**Categoria**: Discovery & Context Enhancement
**Quando usar**: ANTES de iniciar desenvolvimento em projetos com ADRs ou frontend Lovable

**O que faz**:
- Analisa ADRs (Architecture Decision Records) existentes
- Mapeia frontend Lovable e identifica mocks
- Gera briefing modular estruturado
- Prepara contexto otimizado para desenvolvimento

**Sintaxe**:
```bash
/discover
```

**Saída gerada**:
```
docs/technical-context/
├── project-briefing.md              # Índice mestre (~150 linhas)
└── briefing/
    ├── critical-rules.md            # Regras não-negociáveis (~80 linhas)
    ├── adrs-summary.md              # ADRs consolidadas
    ├── backend-conventions.md       # Convenções de código
    ├── frontend-lovable.md          # Mapeamento de mocks (se aplicável)
    └── tech-stack.md                # Stack tecnológico
```

**Agentes acionados**:
- `@adr-compliance-checker`
- `@lovable-backend-mapper`

**Benefícios**:
- ✅ Reduz uso de tokens em até 60%
- ✅ Carregamento seletivo de contexto
- ✅ ADRs consultadas proativamente
- ✅ Mapeamento automático de integrações

**Exemplo de uso**:
```bash
# Execute uma vez por projeto
/discover

# Resultado: Briefing pronto para uso pelos comandos /start, /plan, /work
```

---

### `/start`

**Categoria**: Inicialização de Feature
**Quando usar**: Ao começar desenvolvimento de nova feature

**O que faz** (v2.0):
1. Verifica se briefing do `/discover` existe
2. Se sim: Carrega contexto seletivamente
   - Pergunta quais áreas serão impactadas
   - Carrega apenas ADRs relevantes
   - Enriquece `context.md` com regras críticas
3. Cria arquivo `context.md` com:
   - ⚠️ Regras Críticas do Projeto (se briefing existe)
   - 📚 ADRs Relevantes com links
   - 🎨 Frontend Integration (se Lovable envolvido)
   - Contexto específico da feature
4. Cria arquivo `architecture.md`
5. **BLOQUEIA**: Aguarda aprovação explícita antes de `/plan`

**Sintaxe**:
```bash
/start "<feature-slug>"
```

**Exemplo**:
```bash
/start "user-authentication"

# Se briefing existe, o comando pergunta:
# 1. Esta feature envolve frontend Lovable? (s/n)
# 2. Áreas do backend impactadas:
#    [ ] API/Controllers
#    [ ] Database/ORM
#    [ ] Autenticação/Autorização
#    [ ] Services/Business Logic
```

**Saída gerada**:
```
.claude/sessions/user-authentication/
├── context.md                       # Contexto enriquecido com ADRs
└── architecture.md                  # Decisões arquiteturais
```

**Agentes acionados**:
- `@lovable-backend-mapper` (se frontend Lovable)

**⛔ IMPORTANTE**: NÃO prossegue automaticamente para `/plan`. Aguarda comando explícito.

---

### `/plan`

**Categoria**: Planejamento de Execução
**Quando usar**: Após `/start` ser aprovado

**O que faz** (v2.0):
1. Lê `context.md` e `architecture.md`
2. Cria plano de execução faseado em `plan.md`
3. **Se frontend Lovable detectado**:
   - Lê `frontend-lovable.md` (do briefing)
   - Inclui fases de "Mock Removal"
   - Gera checklist para cada mock
4. **BLOQUEIA**: Aguarda aprovação explícita antes de `/work`

**Sintaxe**:
```bash
/plan
```

**Exemplo de plano gerado** (com Lovable):
```markdown
## FASE 1: Implementação Backend API [Não Iniciada ⏳]

### Criar endpoint GET /api/users [Não Iniciada ⏳]
...

## FASE 2: Integração Frontend [Não Iniciada ⏳]

### Remover Mock #1: User List [Não Iniciada ⏳]

**Backend (pré-requisito):**
- [x] Endpoint GET /api/users criado
- [x] Testes de integração passando

**Frontend:**
- [ ] Remover mock de UserList.tsx:15-20
- [ ] Substituir por useFetch('/api/users')
- [ ] Adicionar loading state
- [ ] Adicionar error handling
- [ ] Criar teste com MSW
- [ ] Validar tipos TypeScript match

**Validação:**
- [ ] Testar manualmente no browser
- [ ] Verificar network tab
```

**Saída gerada**:
```
.claude/sessions/user-authentication/
├── context.md
├── architecture.md
└── plan.md                          # Plano faseado de execução
```

**⛔ IMPORTANTE**: NÃO inicia `/work` automaticamente. Aguarda comando explícito.

---

### `/work`

**Categoria**: Implementação de Código
**Quando usar**: Após `/plan` ser aprovado

**O que faz** (v2.2 - Com Integração Linear):

**GESTÃO DE CARDS (OBRIGATÓRIO):**
1. **Ao iniciar**: Mover card para "In Progress" no Linear
2. **Durante**: Adicionar comentários para updates significativos
3. **Ao abrir PR**: Mover card para "In Review"
4. **Após merge**: Mover card para "Done"

**Abordagem Proativa:**

**ANTES de implementar cada tarefa:**
1. Lê regras críticas do `context.md`
2. Identifica ADRs aplicáveis
3. Planeja implementação conforme ADRs
4. Decide estrutura de arquivos

**DURANTE implementação:**
1. Cria arquivos na localização correta
2. Segue padrões arquiteturais desde o início
3. Usa convenções obrigatórias

**APÓS implementação:**
1. Executa `@adr-compliance-checker` (se disponível)
2. Validação de sanidade (confirma conformidade)
3. Gera relatório de conformidade

**Sintaxe**:
```bash
/work "sessions/<feature-slug>"
```

**Exemplo**:
```bash
/work "sessions/user-authentication"

# Fluxo interno (automático):
# 1. Lê context.md → Identifica ADR-007: Repository Pattern
# 2. Planeja: Criar UserRepository ANTES de UserService
# 3. Implementa: user.repository.ts → user.service.ts
# 4. Valida: @adr-compliance-checker confirma 100% conforme
```

**Filosofia v2.0**:
```
❌ ANTES (Reativo):
   Código → Detecta violação → Corrige → Desperdiça tokens

✅ AGORA (Proativo):
   ADRs → Código correto → Validação OK → Zero retrabalho
```

**Agentes acionados**:
- `@adr-compliance-checker` (validação de conformidade)
- Agentes de implementação específicos (backend, frontend, etc.)

**Relatório gerado ao final da fase**:
```markdown
## FASE 1 [Completada ✅]

### Comentários:

#### Conformidade com ADRs (Abordagem Proativa)
- ✅ ADRs consultadas ANTES da implementação
- ✅ Código criado seguindo regras desde o início
- ✅ Validação final: 100% conforme
- ✅ Zero correções necessárias

**Regras aplicadas:**
- ADR-007: Repository Pattern → UserRepository criado e injetado
- ADR-003: ENUMs em /shared/enums/
- ADR-012: Testes → user.service.spec.ts criado junto
```

---

### `/pre-pr`

**Categoria**: Validação Pré-Pull Request
**Quando usar**: Antes de criar PR

**O que faz**:
- Executa suite completa de validações
- Verifica testes
- Checa conformidade com padrões
- Valida documentação

**Sintaxe**:
```bash
/pre-pr
```

**Agentes acionados**:
- `@branch-code-reviewer`
- `@branch-test-planner`
- `@branch-documentation-writer`
- `@adr-compliance-checker`

---

### `/pr`

**Categoria**: Criação de Pull Request
**Quando usar**: Após `/pre-pr` passar

**O que faz**:
- Cria Pull Request no GitHub
- Gera descrição automática
- Adiciona labels apropriados

**Sintaxe**:
```bash
/pr
```

---

## 🎨 Comandos de Produto

### `/brainstorm` 🆕

**Categoria**: Ideação e Planejamento Estratégico
**Quando usar**: Para decisões de produto e feature discovery

**O que faz**:
Facilita brainstorming estruturado em 5 fases:
1. **Contextualização**: Entender problema e objetivos
2. **Exploração Divergente**: Gerar ideias sem restrições
3. **Convergência Estruturada**: Avaliar e filtrar ideias
4. **Recomendação**: Escolher melhor caminho
5. **Documentação**: Registrar decisões

**Sintaxe**:
```bash
/brainstorm "<tópico>"
```

**Exemplo**:
```bash
/brainstorm "estratégia de onboarding de usuários"
```

**Saída gerada**:
```
docs/business-context/brainstorm/
└── onboarding-strategy-2025-01-26.md
```

---

### `/warm-up`

**Categoria**: Preparação de Contexto
**Quando usar**: Início de sessão de trabalho

**O que faz**:
- Prepara ambiente de trabalho
- Carrega contexto da sessão anterior
- Sincroniza estado do projeto

**Sintaxe**:
```bash
/warm-up "<contexto>"
```

---

### `/collect`

**Categoria**: Levantamento de Requisitos
**Quando usar**: Início de projeto ou nova feature

**O que faz**:
- Coleta requisitos de negócio
- Identifica stakeholders
- Mapeia restrições e dependências

**Sintaxe**:
```bash
/collect "<escopo>"
```

**Agentes acionados**:
- `@discovery-analyst`
- `@prd-interview-specialist`

---

### `/check`

**Categoria**: Validação de Requisitos
**Quando usar**: Após `/collect`

**O que faz**:
- Valida requisitos contra master docs
- Identifica conflitos
- Sugere ajustes

**Sintaxe**:
```bash
/check "<o-que-validar>"
```

---

### `/refine`

**Categoria**: Refinamento de Requisitos
**Quando usar**: Após `/check` identificar gaps

**O que faz**:
- Detalha requisitos
- Esclarece ambiguidades
- Adiciona critérios de aceitação

**Sintaxe**:
```bash
/refine "<requisito>"
```

---

### `/spec`

**Categoria**: Especificação de Produto (PRD)
**Quando usar**: Após requisitos refinados

**O que faz**:
- Gera Product Requirements Document
- Documenta user stories
- Define critérios de sucesso

**Sintaxe**:
```bash
/spec "<feature-name>"
```

**Saída gerada**:
```
docs/master-docs/
└── <feature-name>-prd.md
```

**Agentes acionados**:
- `@feature-docs-architect`
- `@feature-spec-validator`

---

### `/bug-collect` 🆕

**Categoria**: Investigação Forense de Bugs
**Quando usar**: Quando um bug é reportado e precisa de investigação profunda antes de criar a issue

**O que faz**:
- Investigação forense completa (código + banco + histórico git)
- Cruzamento de hipóteses com evidências reais
- Quantificação de impacto (registros/usuários afetados)
- Geração de issue ultra-detalhada com root-cause analysis
- Proposta de abordagens de fix com trade-offs
- Criação automática da issue no Linear ou GitHub

**Diferença do `/collect`**:
| Aspecto | `/collect` | `/bug-collect` |
|---------|-----------|----------------|
| Objetivo | Coletar requisitos | Investigar bugs |
| Profundidade | Superficial | Forense (código + banco + git) |
| Saída | Requisitos brutos | Issue com root-cause analysis |
| Hipóteses | Não aplica | Cruzadas com evidências |
| Impacto | Não avalia | Quantifica registros afetados |

**Fases**:
1. **Intake**: Entendimento inicial e triagem
2. **Reconhecimento**: Auto-detecção do projeto e stack
3. **Investigação Forense**: Código, banco de dados, histórico git
4. **Síntese**: Root-cause analysis e abordagens de fix
5. **Rascunho**: Issue detalhada para aprovação
6. **Criação**: Publicação no Linear ou GitHub Issues

**Sintaxe**:
```bash
/bug-collect "<descrição do bug>"
```

**Exemplo**:
```bash
/bug-collect "dashboard mostra valores diferentes do relatório exportado"
```

**Saída**: Issue criada no Linear/GitHub com:
- Root-cause analysis completo
- Code-paths envolvidos com arquivo:linha
- Evidências de banco de dados (se investigado)
- Abordagens de fix com trade-offs
- Casos de teste para validação

---

### `/sync-linear`

**Categoria**: Integração com Linear
**Quando usar**: Para sincronizar documentação de features com Linear

**O que faz**:
- Analisa documentação em `docs/business-context/features/`
- Compara com issues existentes no Linear
- Cria/atualiza épicos e sub-issues automaticamente
- Operações idempotentes (seguro executar múltiplas vezes)

**Sintaxe**:
```bash
/product:sync-linear
```

**Modos disponíveis**:
1. **Completo**: Sincronizar todas as features de todos os módulos
2. **Por Módulo**: Sincronizar apenas um módulo específico
3. **Por Escopo**: Sincronizar apenas um escopo (MVP, Fase 2, Fase 3)
4. **Preview**: Apenas gerar relatório de diferenças

**Agentes acionados**:
- `@linear-project-sync`

---

### `/light-arch`

**Categoria**: Arquitetura Leve
**Quando usar**: Após PRD para definir arquitetura

**O que faz**:
- Design de alto nível
- Modelagem de dados
- Contratos de API

**Sintaxe**:
```bash
/light-arch "<feature-name>"
```

**Agentes acionados**:
- `@backend-architect`
- `@database-architect`

---

### `/task`

**Categoria**: Quebra em Tarefas
**Quando usar**: Após arquitetura definida

**O que faz**:
- Divide feature em tarefas
- Estima esforço
- Identifica dependências

**Sintaxe**:
```bash
/task "<feature-name>"
```

---

## 📊 Comandos de Relatórios

### `/report:weekly`

**Categoria**: Relatórios Executivos
**Quando usar**: Para gerar relatório semanal de progresso

**O que faz**:
- Analisa commits da semana
- Coleta métricas de produtividade
- Gera slides HTML
- Converte para PPTX com tema selecionável

**Sintaxe**:
```bash
/report:weekly
```

**Temas disponíveis**:
| Tema | Descrição |
|------|-----------|
| `px` | PX Ativos Judiciais (padrão) |
| `cortex` | Cortex Framework |
| `minimal` | Tons neutros |
| `dark` | Tema escuro |

**Saída gerada**:
```
reports/weekly/YYYY-MM-DD/
├── slide_01_capa.html
├── slide_02_*.html
├── ...
├── metrics.json
└── weekly_report.pptx
```

---

### `/report:general`

**Categoria**: Relatórios Executivos
**Quando usar**: Para gerar relatório geral do projeto

**O que faz**:
- Análise completa do repositório
- Métricas de produtividade e economia
- Arquitetura e entregas
- Roadmap e próximos passos

**Sintaxe**:
```bash
/report:general
```

**Saída gerada**:
```
reports/general/PROJECT-YYYY/
├── slide_01_capa.html
├── slide_02_overview.html
├── slide_03_metrics.html
├── slide_04_architecture.html
├── slide_05_deliverables.html
├── slide_06_nextsteps.html
├── slide_07_obrigado.html
├── metrics.json
└── general_report.pptx
```

---

### `/docx:report`

**Categoria**: Documentos Word
**Quando usar**: Para gerar documentos Word estruturados

**O que faz**:
- Gera documentos DOCX profissionais
- Suporte a múltiplos tipos de documento
- Formatação automática (títulos, tabelas, etc.)

**Tipos disponíveis**:
- `technical` - Documentação técnica
- `executive` - Relatórios executivos
- `proposal` - Propostas comerciais
- `consulting` - Relatórios de consultoria
- `general` - Documentos genéricos

**Sintaxe**:
```bash
/docx:report
```

**Uso via script**:
```bash
node .claude/scripts/docx/generator.js \
  -t <tipo> \
  -T "Título" \
  -i dados.json \
  -o saida.docx
```

---

## 📚 Comandos de Documentação

### `/build-business-docs`

**Categoria**: Documentação de Negócio
**Quando usar**: Início de projeto

**O que faz**:
- Cria visão estratégica
- Documenta stakeholders
- Define modelo de negócio

**Sintaxe**:
```bash
/build-business-docs "<contexto>"
```

**Saída gerada**:
```
docs/business-context/
├── vision.md
├── stakeholders.md
└── business-model.md
```

---

### `/build-tech-docs`

**Categoria**: Documentação Técnica
**Quando usar**: Após business docs

**O que faz**:
- Documenta stack tecnológico
- Registra decisões arquiteturais
- Lista constraints técnicas

**Sintaxe**:
```bash
/build-tech-docs "<escopo>"
```

**Saída gerada**:
```
docs/technical-context/
├── architecture.md
├── technology-stack.md
└── constraints.md
```

---

### `/build-index`

**Categoria**: Organização de Documentação
**Quando usar**: Após criar documentação

**O que faz**:
- Cria índice de toda documentação
- Organiza estrutura
- Facilita navegação

**Sintaxe**:
```bash
/build-index
```

**Saída gerada**:
```
docs/
└── index.md
```

---

### `/docs`

**Categoria**: Atualização de Documentação
**Quando usar**: Após mudanças no código

**O que faz**:
- Atualiza documentação técnica
- Sincroniza com código
- Gera API docs

**Sintaxe**:
```bash
/docs "<escopo>"
```

**Agentes acionados**:
- `@branch-documentation-writer`

---

## 🆕 Comandos de Discovery (Novo)

### Comparação: `/discover` vs Fluxo Manual

| Aspecto | Com `/discover` | Sem `/discover` |
|---------|----------------|-----------------|
| **Tempo de setup** | ~30 min | ~2-3 horas |
| **Uso de tokens** | 40% do normal | 100% |
| **Conformidade ADRs** | Proativa (100%) | Reativa (~70%) |
| **Mapeamento Lovable** | Automático | Manual |
| **Contexto em `/start`** | Enriquecido | Básico |
| **Retrabalho** | Quase zero | Frequente |

### Quando NÃO usar `/discover`

❌ Projetos sem ADRs documentadas
❌ Projetos sem frontend Lovable
❌ Projetos muito simples (< 5 endpoints)
❌ Protótipos descartáveis

### Quando SEMPRE usar `/discover`

✅ Projetos com ADRs formais
✅ Frontend Lovable com mocks
✅ Projetos legados com documentação extensa
✅ Projetos enterprise com múltiplas convenções

---

## 📊 Comparação de Comandos

### Comandos de Inicialização

| Comando | Escopo | Duração | Pré-requisito | Saída |
|---------|--------|---------|---------------|-------|
| `/discover` | Projeto | 30 min | ADRs ou Lovable | Briefing modular |
| `/warm-up` | Sessão | 5 min | Nenhum | Contexto carregado |
| `/start` | Feature | 1-2h | `/discover` (recomendado) | context.md, architecture.md |

### Comandos de Execução

| Comando | Fase | Bloqueio | Validação | Saída |
|---------|------|----------|-----------|-------|
| `/plan` | Planejamento | ⛔ Sim | Revisão humana | plan.md |
| `/work` | Implementação | ❌ Não | @adr-compliance-checker | Código + relatório |
| `/pre-pr` | Pré-PR | ❌ Não | Suite completa | Relatório de validação |
| `/pr` | PR | ❌ Não | GitHub | Pull Request |

### Comandos de Produto

| Comando | Objetivo | Duração | Saída |
|---------|----------|---------|-------|
| `/brainstorm` | Ideação | 30-60 min | Decisões documentadas |
| `/bug-collect` | Investigação forense | 30-60 min | Issue com root-cause |
| `/collect` | Requisitos | 30 min | Requisitos brutos |
| `/refine` | Detalhamento | 1h | Requisitos refinados |
| `/spec` | PRD | 2-3h | PRD completo |
| `/light-arch` | Arquitetura | 1-2h | Design de alto nível |

---

## 🎯 Workflows Recomendados

### Greenfield com Lovable + ADRs (v2.0)

```bash
# Fase 0: Discovery (NOVO)
/discover

# Fase 1: Fundação
/warm-up → /collect → /build-business-docs → /build-tech-docs → /build-index

# Fase 2: Design
/spec → /light-arch

# Fase 3: Frontend (Lovable)
@lovable-frontend-prompt-generator

# Fase 4: Backend
/start → /plan → /work → /pre-pr → /pr

# Fase 5: Integração
/work (mock removal) → /pre-pr → /pr
```

### Projeto Simples (sem ADRs)

```bash
/collect → /spec → /start → /plan → /work → /pr
```

### Feature em Projeto Existente (com ADRs)

```bash
# Se /discover já foi executado no passado:
/start → /plan → /work → /pr

# Se nunca executou /discover:
/discover → /start → /plan → /work → /pr
```

---

## 📖 Recursos Adicionais

- [WORKFLOWS.md](./WORKFLOWS.md) - Guias detalhados por cenário
- [CHANGELOG.md](../../CHANGELOG.md) - Histórico de mudanças
- [guides/discover-workflow.md](./guides/discover-workflow.md) - Guia do `/discover`
- [guides/adr-proactive-approach.md](./guides/adr-proactive-approach.md) - Filosofia proativa

---

**Versão do Framework**: 2.4.0
**Última Atualização**: 2026-02-22
