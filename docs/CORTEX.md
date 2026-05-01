# 🧠 CORTEX - Guia de Uso Completo

> **Versão 2.4** - Bug Collect Forense Release
> Para histórico de mudanças, veja abaixo

## 🆕 **Novidades v2.4**

### Bug Collect - Investigação Forense de Bugs
- Novo comando `/bug-collect` para investigação profunda de bugs
- Cruzamento de hipóteses entre código, banco de dados e histórico git
- Quantificação de impacto (registros/usuários afetados)
- Geração automática de issue no Linear ou GitHub com root-cause analysis
- Proposta de abordagens de fix com trade-offs

---

## **Novidades v2.3**

### Geração PPTX Nativa (100% Editável)
- Novo método de geração PPTX usando pptxgenjs diretamente
- Slides totalmente editáveis no PowerPoint/Google Slides
- Especificação alinhada com Claude.ai
- Script `generate-aula01.js` como referência de implementação

### Skill px-presentations Atualizada
- Documentação completa da spec pptxgenjs
- Conversões px → inches e fontSize
- Notas sobre gotchas (OVAL vs ELLIPSE, cores sem #, evitar charSpacing)

### Curso CDD - Aula 01
- 9 slides completos com tema AI Frontiers
- Material base para as 10 aulas do curso

---

## 📋 **Changelog**

### v2.4 (2026-02-22)
- feat: Add bug-collect forensic investigation command
- docs: Update all documentation with bug-collect references

### v2.3 (2026-02-01)
- feat: Add native PPTX generation with pptxgenjs
- feat: Create CDD course Aula 01 slides
- docs: Update px-presentations skill with pptxgenjs spec

### v2.2 (2026-01-17)
- feat: Add Linear integration to engineering workflow
- feat: Add theme support to HTML2PPTX converter
- feat: Add DOCX skill for Word document generation
- feat: Add productivity calculator and dynamic economy metrics

---

## 🔄 **Recursos v2.2**

### Integração com Linear
- Gestão obrigatória de cards durante desenvolvimento
- Comando `/product:sync-linear` para sincronização em bulk
- Agente `@linear-project-sync` para automação

### Suporte a Temas PPTX
- 4 temas: `px`, `cortex`, `minimal`, `dark`
- Argumento `--theme` no conversor HTML2PPTX
- Cores e footers dinâmicos por tema

### Relatórios
- `/report:weekly` - Relatório semanal executivo
- `/report:general` - Relatório geral do projeto
- `/docx:report` - Documentos Word estruturados

---

## 📦 **INSTALAÇÃO DO CORTEX**

### **Suporte Multi-IDE**

O Cortex oferece suporte para três IDEs de IA principais através de um sistema de **fonte única**:

**Para Windsurf:**
```bash
cp -r cortex-v1/.claude /caminho/do/seu/projeto/.windsurf
```

**Para Cursor:**
```bash
cp -r cortex-v1/.claude /caminho/do/seu/projeto/.cursor
```

**Para Claude Code:**
```bash
cp -r cortex-v1/.claude /caminho/do/seu/projeto/
```

> **💡 Nota Importante**: O framework Cortex é mantido em uma única fonte (`.claude/`) para facilitar manutenção e atualizações. Ao copiar para seu projeto, renomeie a pasta conforme o IDE que está utilizando.

---

## 🚀 **FLUXO DE TRABALHO CORTEX PARA NOVOS PROJETOS**

### **🎯 VISÃO GERAL DO CONTEXTO**
**Cenário**: Base de código vazia + Documentação inicial disponível
**Meta**: Configuração integral do framework Cortex para inicialização de projeto
**Abordagem**: Investigação-Primeiro → Documentação-Primeiro → Estrutura-Primeiro

---

## **🆕 NOVIDADE v2.0: Sistema de Discovery**

### **Quando Usar `/discover`**

Execute `/discover` **ANTES** de iniciar desenvolvimento em projetos que possuem:

✅ **ADRs (Architecture Decision Records)** existentes
✅ **Frontend gerado com Lovable** com mock data
✅ **Múltiplas convenções arquiteturais** documentadas
✅ **Projetos legados** com documentação técnica extensa

**O que `/discover` faz:**

1. **Analisa ADRs** automaticamente
2. **Mapeia frontend Lovable** e identifica todos os mocks
3. **Gera briefing modular** em `docs/technical-context/briefing/`
4. **Cria índice mestre** para navegação eficiente
5. **Prepara contexto otimizado** para economizar tokens

```bash
# Execute uma vez por projeto
/discover

# Resultado: Briefing estruturado pronto para consumo
# - docs/technical-context/project-briefing.md (índice)
# - docs/technical-context/briefing/critical-rules.md
# - docs/technical-context/briefing/adrs-summary.md
# - docs/technical-context/briefing/frontend-lovable.md (se aplicável)
# - docs/technical-context/briefing/backend-conventions.md
# - docs/technical-context/briefing/tech-stack.md
```

**📊 Benefícios:**
- Reduz uso de tokens em até 60%
- Carregamento seletivo de contexto
- ADRs consultadas proativamente (não reativamente)
- Mapeamento automático de integrações frontend-backend

**🤖 Agentes Acionados:**
- `@adr-compliance-checker` - Analisa e consolida ADRs
- `@lovable-backend-mapper` - Mapeia mocks do frontend

> 💡 **Dica**: Após `/discover`, os comandos `/start`, `/plan` e `/work` usarão automaticamente o briefing gerado para Context Enhancement.

---

## **🎨 FLUXO RECOMENDADO: Projetos com Lovable Frontend + ADRs**

Este é o fluxo **otimizado v2.0** para projetos greenfield que utilizarão **Lovable** e possuem **ADRs definidas**:

### **📅 FASE 0: Discovery (Novo - 30 min)**

```bash
# 🆕 Execute PRIMEIRO em projetos com ADRs ou Lovable frontend
/discover

# Resultado: Briefing modular gerado automaticamente
# ✅ ADRs consolidadas por categoria
# ✅ Frontend mocks mapeados (se aplicável)
# ✅ Regras críticas extraídas
# ✅ Convenções de código documentadas
```

**🤖 Agentes Acionados**: `@adr-compliance-checker`, `@lovable-backend-mapper`

---

### **📅 FASE 1: Fundação de Contexto (Dias 1-2)**

```bash
# 1. Preparar ambiente
/warm-up "kickoff do projeto"

# 2. Capturar requisitos
/collect "requisitos empresariais e técnicos"

# 3. Gerar documentação estratégica
/build-business-docs "contexto empresarial completo"
/build-tech-docs "arquitetura técnica e stack"
/build-index "organizar master docs"

# 4. Validar alinhamento
/check "validar requisitos contra master docs"
```

**🤖 Agentes Acionados**: `@discovery-analyst`, `@project-blueprint-guardian`

---

### **📅 FASE 2: Design de Dados & Contratos de API (Dias 3-4)**

```bash
# 1. Especificar PRD completo
/spec "PRD com foco em contratos de API"

# 2. Design arquitetural
/light-arch "modelagem de dados + contratos de API"
# Deve incluir:
# - Modelagem de entidades e relacionamentos
# - Schemas de banco de dados
# - Contratos detalhados de API (endpoints, métodos, payloads, responses)
# - Estruturas de dados para cada endpoint
```

**📁 Saída Esperada**:
- Schemas de banco de dados completos
- Contratos de API documentados (endpoints, métodos, payloads, responses)
- Modelagem de entidades e relacionamentos

**🤖 Agentes Acionados**: @database-architect, @backend-architect

---

### **📅 FASE 3: Geração de Frontend com Lovable (Dia 5)**

```bash
# Invocar agente especializado (via @ no chat)
@lovable-frontend-prompt-generator

# O agente irá:
# ✅ Analisar todos os master docs (business + technical)
# ✅ Revisar contratos de API definidos
# ✅ Gerar prompt estruturado completo para Lovable
# ✅ Incluir mock data strategy baseada nos endpoints
# ✅ Especificar componentes seguindo Atomic Design

# Copie o prompt gerado e cole no Lovable
# Resultado: Frontend React 100% navegável com dados mockados
```

**🎯 Resultado**: Frontend React completo, navegável, com mock data estruturado

**🤖 Agente Acionado**: @lovable-frontend-prompt-generator

---

### **📅 FASE 4: Implementação Backend (Dias 6-9)**

```bash
# 1. Iniciar implementação (com Context Enhancement automático)
/start "nome-do-projeto-backend"
# 🆕 Se /discover foi executado:
#   ✅ Carrega briefing automaticamente
#   ✅ Pergunta quais áreas serão impactadas
#   ✅ Carrega ADRs relevantes seletivamente
#   ✅ Enriquece context.md com regras críticas

# 2. Planejar execução
/plan "implementação de API seguindo contratos"
# 🆕 Se frontend Lovable detectado:
#   ✅ Inclui fases de Mock Removal
#   ✅ Cria checklist de integração frontend-backend

# 3. Implementar iterativamente (Abordagem Proativa)
/work "sessions/nome-do-projeto-backend"
# 🆕 ANTES de implementar cada tarefa:
#   ✅ Consulta ADRs no context.md
#   ✅ Planeja implementação conforme regras
#   ✅ Cria código correto desde o início
# DURANTE implementação:
#   ✅ Segue padrões arquiteturais
#   ✅ Localização correta de arquivos
# APÓS implementação:
#   ✅ Validação de sanidade (confirma conformidade)
#   ✅ Relatório de conformidade com ADRs

# Resultado: Código 100% conforme, zero retrabalho

# 4. Validar cada entrega
/pre-pr  # Após cada feature completa
/pr      # Para criar Pull Request
```

**🤖 Agentes Acionados**: `@backend-python-specialist`, `@test-engineer`, `@code-reviewer`, `@adr-compliance-checker`

**📊 Novo Fluxo Proativo:**
```
❌ ANTES (v1.x - Reativo):
   Código → Detecta violação → Corrige → Desperdiça tokens

✅ AGORA (v2.0 - Proativo):
   ADRs → Código correto → Validação OK → Zero retrabalho
```

---

### **📅 FASE 5: Integração Frontend-Backend (Dias 10-11)**

```bash
# 🆕 Usar agente de mapeamento (já invocado pelo /discover)
# Se /discover NÃO foi executado, invocar manualmente:
@lovable-backend-mapper

# O agente irá:
# ✅ Identificar todos os pontos de mock data no frontend Lovable
# ✅ Mapear cada mock para o endpoint real correspondente
# ✅ Verificar compatibilidade de responses
# ✅ Listar discrepâncias para correção
# ✅ Gerar checklists de integração

# Implementar integrações identificadas
/work "sessions/frontend-integration"
# 🆕 Plano já inclui fases de Mock Removal (geradas pelo /plan)
#   - Checklist para cada mock
#   - Pré-requisitos de backend
#   - Tarefas de frontend
#   - Validação de integração
```

**🤖 Agente Acionado**: `@lovable-backend-mapper`

**📋 Checklist de Integração (gerado automaticamente):**
```markdown
### Remover Mock #1: User List

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
- [ ] Verificar network tab (chamada real)
- [ ] Verificar dados renderizados
```

---

### **📅 FASE 6: Validação de Aderência (Dia 12)**

```bash
# Verificar alinhamento com master docs
/check "validação completa do projeto"

# Invocar agente de verificação Lovable (se disponível)
@lovable-alignment-checker

# O agente irá:
# ✅ Comparar componentes vs especificação dos docs
# ✅ Verificar fluxos de usuário implementados
# ✅ Validar design system e usabilidade
# ✅ Checar acessibilidade e responsividade
# ✅ Confirmar cobertura de user types e permissões
```

**🤖 Agente Sugerido**: @lovable-alignment-checker (custom)

---

### **📅 FASE 7: Refinamento & Documentação (Dias 13-14)**

```bash
# Ajustes finais
/refine "melhorias de UX e edge cases"

# Atualizar documentação
/docs "documentação técnica completa"

# Validação final
/pre-pr  # Suite completa de validações
/pr      # Pull Request final
```

**🤖 Agentes Acionados**: @branch-code-reviewer, @branch-test-planner, @branch-documentation-writer

---

## **⚡ FLUXO ALTERNATIVO: Projetos Sem Lovable (Tradicional)**

## **⚡ SEQUÊNCIA SUGERIDA PARA INICIALIZAÇÃO DE PROJETO**

### **📋 ETAPA 1: Levantamento e Definição de Requisitos (15-30 min)**

```bash
# 1. Aquecimento inicial e preparação de contexto
/warm-up "kickoff do projeto - preparação de repositório inicial"

# 2. Levantamento estruturado de necessidades  
/collect "requisitos de negócio, limitações técnicas, demandas das partes interessadas"

# 3. Validação contra diretrizes e padrões
/check "verificar requisitos contra diretrizes do setor e limitações do projeto"

# 4. Aprimoramento das requisitos levantadas
/refine "detalhamento de requisitos funcionais e técnicas"
```

**🤖 Agentes Acionados Automaticamente**: @discovery-analyst → @project-blueprint-guardian → @business-analyst

---

### **📚 ETAPA 2: Fundamentação Documental (20-40 min)**

```bash
# 5. Elaboração de contexto empresarial
/build-business-docs "visão estratégica, partes interessadas, modelo operacional"

# 6. Elaboração de arquitetura técnica
/build-tech-docs "pilha de tecnologia, escolhas arquiteturais, limitações"

# 7. Desenvolvimento de Documento de Requisitos de Produto
/spec "PRD completo incluindo requisitos técnicas e empresariais"

# 8. Organização de índices documentais
/build-index "estruturar e organizar toda documentação gerada"
```

**📁 Diretório de Saída**: `docs/business-context/`, `docs/technical-context/`, `docs/master-docs/`  
**🤖 Agentes Acionados Automaticamente**: @discovery-analyst → @feature-docs-architect

---

### **🏗️ ETAPA 3: Fundamentação Técnica (30-60 min)**

```bash
# 9. Desenho arquitetural detalhado
/light-arch "estrutura do sistema, escolhas tecnológicas, plano de implementação"

# 10. Estruturação de tarefas de desenvolvimento  
/task "segmentação de etapas de desenvolvimento e tarefas de implementação"

# 11. Inicialização da configuração técnica
/start "preparação da fundação técnica e estrutura base do projeto"
```

**🤖 Agentes Acionados Automaticamente**: @workspace-structure-designer → @zenstack-implementation-lead → @standards-compliance-guardian

---

### **⚙️ ETAPA 4: Validação e Verificação de Integridade (10-15 min)**

```bash
# 12. Verificação final contra master docs
/check "validação de completude e coerência do sistema"
```

**🤖 Agentes Acionados Automaticamente**: @project-blueprint-guardian → @feature-docs-architect

---

## **🎯 COMANDOS ESSENCIAIS ORGANIZADOS POR PRIORIDADE**

### **🥇 PRIORIDADE MÁXIMA (Essencial)**
1. **`/collect`** - Fundação de qualquer projeto, levantamento de necessidades
1b. **`/bug-collect`** - Investigação forense de bugs com root-cause analysis
2. **`/build-business-docs`** - Contexto empresarial fundamental  
3. **`/build-tech-docs`** - Escolhas arquiteturais críticas
4. **`/spec`** - PRD como referência principal do projeto

### **🥈 PRIORIDADE MÉDIA (Sugerido)**  
5. **`/check`** - Verificação contra diretrizes e limitações
6. **`/refine`** - Detalhamento preciso de requisitos
7. **`/start`** - Preparação técnica inicial organizada

### **🥉 PRIORIDADE BAIXA (Complementar)**
8. **`/warm-up`** - Aquecimento de contexto (pode ser incorporado)
9. **`/light-arch`** - Revisão arquitetural (pode ser posterior)
10. **`/task`** - Organização de tarefas (pode vir durante execução)

---

## **🏃‍♂️ PERCURSO ACELERADO (Projetos Compactos)**

```bash
# Preparação rápida em 30-45 minutos
/collect "levantamento ágil de necessidades"
/build-business-docs "contexto empresarial core"
/spec "PRD enxuto e viável"
/start "preparação técnica inicial"
/plan
/work "sessions/<feature-name>"
```

## **🎯 PERCURSO COMPLETO (Projetos Complexos/Empresariais)**

```bash
# Preparação integral em 2-3 horas
/warm-up → /collect → /check → /refine →
/build-business-docs → /build-tech-docs → /spec → /build-index →
/light-arch → /task → /start → /plan → /work → /pre-pr → /pr
```

---

## **📁 ORGANIZAÇÃO RESULTANTE APÓS EXECUÇÃO**

```
projeto-inicial/
├── docs/
│   ├── business-context/           # gerado por /build-business-docs
│   │   ├── vision.md
│   │   ├── stakeholders.md  
│   │   └── business-model.md
│   ├── technical-context/          # gerado por /build-tech-docs
│   │   ├── architecture.md
│   │   ├── technology-stack.md
│   │   └── constraints.md
│   ├── master-docs/               # gerado por /spec  
│   │   ├── project-prd.md
│   │   └── requirements.md
│   └── index.md                    # gerado por /build-index
├── .cursor/
│   ├── sessions/                   # trabalho organizado por sessão
│   │   └── project-inception/
│   ├── agents/                     # agentes automatizados  
│   └── commands/                   # comandos Cortex
└── README.md                       # resumo executivo do projeto
```

---

## **🤖 AUTOMAÇÃO E ORQUESTRAÇÃO INTELIGENTE**

### **Agentes que Serão Ativados Dinamicamente:**
- **@discovery-analyst**: Investigação de requisitos e pesquisa
- **@project-blueprint-guardian**: Auditoria e conformidade  
- **@feature-docs-architect**: Elaboração de documentação
- **@workspace-structure-designer**: Design de arquitetura técnica (quando necessário)
- **@zenstack-implementation-lead**: Preparação técnica (para projetos ZenStack)

### **Processos Automáticos Disparados:**
- **Validações preliminares**: Checagem de dependências e ambiente operacional
- **Estruturação documental**: Organização sistemática seguindo padrões estabelecidos
- **Gestão de contexto**: Manutenção de histórico em `.cursor/sessions/`

---

## **⏱️ TEMPO ESTIMADO DE EXECUÇÃO**

- **Percurso Acelerado**: 30-45 minutos
- **Percurso Padrão**: 1-2 horas  
- **Percurso Completo**: 2-3 horas
- **Percurso Empresarial**: 4-6 horas (com múltiplas revisões)

---

## **🎉 ENTREGAVELS FINAIS**

Ao concluir este processo, você obterá:

✅ **Documentação integral** do projeto (estratégica + técnica)  
✅ **Especificações mestras** como referência de verdade  
✅ **Organização estrutural** alinhada aos padrões Cortex  
✅ **Fundação técnica** preparada para construção  
✅ **Framework de qualidade** operante com automações integradas  
✅ **Contextos de trabalho** estruturados para continuação  

**🚀 PRÓXIMA AÇÃO PÓS-PREPARAÇÃO**: `/work "desenvolvimento da primeira funcionalidade"`

---

## **📊 SISTEMA DE RELATÓRIOS E DOCUMENTOS**

### **Skills Disponíveis**

O Cortex inclui skills para geração de artefatos profissionais:

| Skill | Descrição | Comando |
|-------|-----------|---------|
| `docx` | Documentos Word estruturados | `/docx:report` |
| `px-presentations` | Apresentações PPTX | `/report:weekly`, `/report:general` |

### **Comandos de Relatórios**

```bash
# Relatório semanal executivo (PPTX)
/report:weekly

# Relatório geral do projeto (PPTX)
/report:general

# Documento Word estruturado
/docx:report
```

### **Tipos de Documento DOCX**

| Tipo | Uso | Seções Incluídas |
|------|-----|------------------|
| `technical` | Documentação técnica | Sumário, Visão Geral, Arquitetura, Requisitos |
| `executive` | Relatórios executivos | Resumo, Métricas, Entregas, Riscos, Próximos Passos |
| `proposal` | Propostas comerciais | Apresentação, Desafio, Solução, Investimento |
| `consulting` | Relatórios de consultoria | Diagnóstico, Recomendações, Plano de Ação, ROI |

### **Uso via Script**

```bash
# Instalar dependência
npm install docx --save-dev

# Gerar documento
node .claude/scripts/docx/generator.js \
  -t executive \
  -T "Relatório de Andamento" \
  -i dados.json \
  -o relatorio.docx
```

### **Estrutura de Saída**

```
reports/
├── weekly/              # Relatórios semanais (PPTX)
│   └── YYYY-MM-DD/
├── general/             # Relatórios gerais (PPTX)
│   └── PROJECT_YYYY/
└── docs/                # Documentos Word (DOCX)
    └── YYYY-MM-DD/
        ├── dados.json
        └── documento.docx
```

---

## **📁 ARQUIVOS DO FRAMEWORK**

### **Estrutura Completa**

```
.claude/
├── agents/              # 51 agentes especializados
│   ├── backend-architect.md
│   ├── frontend-architect.md
│   ├── test-engineer.md
│   ├── code-reviewer.md
│   └── ... (47 mais)
├── commands/            # Comandos invocáveis
│   ├── engineer/        # /start, /plan, /work, /pr
│   ├── product/         # /collect, /spec, /refine, /bug-collect
│   ├── report/          # /report:weekly, /report:general
│   ├── docx/            # /docx:report
│   ├── docs-commands/   # /build-tech-docs, /build-business-docs
│   └── meta/            # /create-agent
├── skills/              # Capacidades reutilizáveis
│   ├── docx/
│   │   └── SKILL.MD
│   └── px-presentations/
│       ├── SKILL.md
│       └── references/
├── scripts/             # Automações
│   ├── docx/
│   │   └── generator.js
│   ├── html2pptx/
│   │   └── convert.js
│   └── productivity/
│       └── calculator.js
└── rules/               # Regras globais
```

### **Replicando para Outros Projetos**

Para usar o Cortex em outro projeto:

```bash
# Copiar framework completo
cp -r .claude /novo-projeto/

# Instalar dependências
cd /novo-projeto
npm install docx html2pptx pptxgenjs --save-dev
```

Para replicar apenas a skill DOCX:

```bash
mkdir -p .claude/skills/docx .claude/commands/docx .claude/scripts/docx

cp cortex-v1/.claude/skills/docx/SKILL.MD .claude/skills/docx/
cp cortex-v1/.claude/commands/docx/report.md .claude/commands/docx/
cp cortex-v1/.claude/scripts/docx/generator.js .claude/scripts/docx/

npm install docx --save-dev
```

---

## **📚 DOCUMENTAÇÃO ADICIONAL**

- [README.md](../README.md) - Visão geral do framework
- [WORKFLOWS.md](WORKFLOWS.md) - Workflows detalhados
- [COMMANDS.md](COMMANDS.md) - Referência de comandos
- [DOCX-SKILL.md](DOCX-SKILL.md) - Guia da skill DOCX
- [.claude/scripts/reports/README.md](../.claude/scripts/reports/README.md) - Sistema de relatórios