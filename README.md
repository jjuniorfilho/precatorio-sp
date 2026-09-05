# Cortex - Context-Driven Development Framework

> **Versao 2.4.0** | Framework de desenvolvimento orientado a contexto para IDEs de IA

## O que e o Cortex?

O Cortex e um framework que potencializa o desenvolvimento de software atraves de:

- **52 Agentes de IA especializados** por dominio (backend, frontend, testes, docs, etc.)
- **Skills reutilizaveis** para geracao de artefatos (DOCX, PPTX, etc.)
- **Comandos padronizados** para workflows consistentes
- **Integracao com Linear** para gestao de cards em tempo real
- **Geracao PPTX nativa** - slides 100% editaveis com pptxgenjs
- **Context Enhancement** que reduz uso de tokens em ate 60%

## Instalacao Rapida

> **Acesso restrito**: Requer permissao no repositorio GitHub para instalar.

### Via repo rafaelfiales

```bash
# Instalador interativo (recomendado)
npx github:rafaelfiales/cortex-ai-context-driven-design

# Projeto novo (direto, sem menu)
npx github:rafaelfiales/cortex-ai-context-driven-design --new

# Atualizar framework existente (preserva sessions/)
npx github:rafaelfiales/cortex-ai-context-driven-design --update
```

### Via org PX Ativos Judiciais

```bash
# Instalador interativo (recomendado)
npx github:PX-Ativos-Judiciais/cortex-cdd

# Projeto novo (direto, sem menu)
npx github:PX-Ativos-Judiciais/cortex-cdd --new

# Atualizar framework existente (preserva sessions/)
npx github:PX-Ativos-Judiciais/cortex-cdd --update
```

### Instalacao Manual (alternativa)

```bash
# Para Claude Code
cp -r .claude /caminho/do/seu/projeto/

# Para Windsurf
cp -r .claude /caminho/do/seu/projeto/.windsurf

# Para Cursor
cp -r .claude /caminho/do/seu/projeto/.cursor
```

## Arquitetura

```
.claude/
├── agents/           # 53 agentes especializados
│   ├── backend-architect.md
│   ├── frontend-architect.md
│   ├── test-engineer.md
│   ├── linear-project-sync.md  # NOVO: Sync com Linear
│   └── ...
├── commands/         # Comandos invocaveis via /comando
│   ├── engineer/     # /start, /plan, /work, /pr
│   ├── product/      # /collect, /spec, /refine, /sync-linear
│   ├── report/       # /report:weekly, /report:general
│   ├── docx/         # /docx:report
│   └── ...
├── skills/           # Capacidades reutilizaveis
│   ├── docx/         # Geracao de documentos Word
│   └── px-presentations/  # Geracao de PPTX (com temas)
├── scripts/          # Automacoes
│   ├── docx/         # generator.js
│   ├── html2pptx/    # convert.js, generate-aula01.js (PPTX nativo)
│   └── productivity/ # calculator.js
└── rules/            # Regras globais
```

## Comandos Principais

### Produto

| Comando | Descricao |
|---------|-----------|
| `/product:warm-up` | Aquecimento de contexto do projeto |
| `/product:collect` | Coleta de requisitos |
| `/product:refine` | Refinamento de requisitos |
| `/product:spec` | Geracao de PRD |
| `/product:brainstorm` | Ideacao de produto |
| `/product:bug-collect` | **NOVO**: Investigacao forense de bugs |
| `/product:sync-linear` | Sincronizar features com Linear |

### Engenharia

| Comando | Descricao |
|---------|-----------|
| `/engineer:start` | Iniciar desenvolvimento |
| `/engineer:discover` | Descoberta e mapeamento |
| `/engineer:plan` | Planejamento de implementacao |
| `/engineer:work` | Execucao de tarefas |
| `/engineer:pre-pr` | Validacao pre-PR |
| `/engineer:pr` | Criar Pull Request |
| `/engineer:docs` | Atualizar documentacao |

### Relatorios

| Comando | Descricao |
|---------|-----------|
| `/report:weekly` | Relatorio semanal executivo (PPTX) |
| `/report:general` | Relatorio geral do projeto (PPTX) |
| `/docx:report` | Documento Word estruturado |

## Workflow Recomendado

### Projeto Novo

```bash
/product:warm-up          # Preparar contexto
/product:collect          # Coletar requisitos
/product:spec             # Gerar PRD
/engineer:start           # Iniciar desenvolvimento
/engineer:plan            # Planejar execucao
/engineer:work            # Implementar
/engineer:pre-pr          # Validar
/engineer:pr              # Criar PR
```

### Geracao de Documentos

```bash
# Documento Word
/docx:report              # Invoca skill docx

# Ou via script diretamente:
node .claude/scripts/docx/generator.js \
  -t executive \
  -T "Titulo do Documento" \
  -i dados.json \
  -o documento.docx
```

## Skills Disponiveis

### Skill: docx

Geracao de documentos Word estruturados.

**Arquivos:**
- `.claude/skills/docx/SKILL.MD` - Documentacao da skill
- `.claude/commands/docx/report.md` - Comando invocavel
- `.claude/scripts/docx/generator.js` - Script de geracao

**Tipos de documento:**
- `technical` - Documentacao tecnica
- `executive` - Relatorios executivos
- `proposal` - Propostas comerciais
- `consulting` - Relatorios de consultoria
- `general` - Documentos genericos

**Uso:**
```bash
node .claude/scripts/docx/generator.js \
  -t <tipo> \
  -T "Titulo" \
  -i dados.json \
  -o saida.docx
```

### Skill: px-presentations

Geracao de apresentacoes PPTX com dois metodos:

**Arquivos:**
- `.claude/skills/px-presentations/SKILL.md`
- `.claude/scripts/html2pptx/generate-aula01.js` - Geracao nativa (recomendado)
- `.claude/scripts/html2pptx/convert.js` - Conversao HTML para imagens

**Metodo 1: Geracao Nativa (Recomendado)**

Gera PPTX 100% editavel usando pptxgenjs diretamente:

```bash
# Exemplo: Aula 01 do curso CDD
node .claude/scripts/html2pptx/generate-aula01.js
```

**Vantagens:**
- Slides totalmente editaveis no PowerPoint/Google Slides
- Textos, shapes e cores podem ser modificados
- Menor tamanho de arquivo
- Segue especificacao do Claude.ai

**Metodo 2: HTML para Imagens**

Renderiza HTML como imagens (util para fidelidade visual):

```bash
# Tema padrao (px)
node .claude/scripts/html2pptx/convert.js -i slides/ -o output.pptx

# Com tema especifico
node .claude/scripts/html2pptx/convert.js -i slides/ -o output.pptx --theme cortex
```

**Temas disponiveis:**

| Tema | Descricao | Cores |
|------|-----------|-------|
| `px` | PX Ativos Judiciais (padrao) | Navy + Amber |
| `cortex` | Cortex Framework | Navy escuro + Roxo |
| `minimal` | Tons neutros | Cinza + Azul |
| `dark` | Tema escuro | Preto + Amarelo |

### Outras Skills

Skills de processo/workflow (nao geram arquivo diretamente, orientam o agente durante o comando):

| Skill | Uso |
|-------|-----|
| `agent-orchestrator` | Desenhar workflows multi-agente (paralelo vs sequencial, feedback loops) para novos comandos |
| `fleet-orchestration` | Orquestra `/engineer:fleet` e `/engineer:fleet-autonomous` (worktrees paralelas por issue) |
| `mcp-manager` | Instalar/sincronizar MCPs com agentes (`/meta:mcp-install`, `/meta:mcp-sync`) |
| `memory-manager` | Organizar, podar e destilar `.claude/memory/` |
| `prototype-to-plan` | Levar um prototipo HTML aprovado ate um plano de entrega (PRD/ADR/Linear) |
| `ux-flow` | Workflow UX-first: design system HTML e prototipos navegaveis antes do codigo |
| `px-deck` | Apresentacoes .pptx de alto detalhe na identidade PX (prints reais via Playwright) |
| `self-evolution` | Ciclo de auto-evolucao do framework (`/meta:evolve`), baseado em padroes de uso |

## Integracao com Linear

O Cortex agora integra com Linear para gestao de cards em tempo real durante o desenvolvimento.

### Workflow Obrigatorio

1. **Ao iniciar trabalho**: Mover card para "In Progress"
2. **Durante desenvolvimento**: Adicionar comentarios para updates significativos
3. **Ao abrir PR**: Mover card para "In Review"
4. **Apos merge**: Mover card para "Done"

### Sincronizacao de Features

```bash
# Sincronizar features com Linear
/product:sync-linear

# Modos disponiveis:
# - Completo: todas as features
# - Por Modulo: um modulo especifico
# - Por Escopo: MVP, Fase 2, Fase 3
# - Preview: apenas relatorio de diferencas
```

### Agente: linear-project-sync

Agente especializado que:
- Analisa documentacao em `docs/business-context/features/`
- Compara com issues existentes no Linear
- Cria/atualiza epicos e sub-issues automaticamente
- Operacoes idempotentes (seguro executar multiplas vezes)

## Dependencias

```bash
# Para skill docx
npm install docx --save-dev

# Para skill px-presentations
npm install pptxgenjs puppeteer --save-dev

# Opcional: LibreOffice para conversao PDF
sudo apt install libreoffice-core libreoffice-writer
```

## Agentes por Categoria

### Backend
- `backend-architect.md` - Arquitetura de backend
- `database-architect.md` - Design de banco de dados
- `backend-python-specialist.md` - Especialista Python

### Frontend
- `frontend-architect.md` - Arquitetura de frontend
- `react-developer.md` - Desenvolvimento React
- `ux-ui-design-expert.md` - Design UX/UI

### Qualidade
- `test-engineer.md` - Engenharia de testes
- `code-reviewer.md` - Revisao de codigo
- `code-quality-guardian.md` - Qualidade de codigo

### Documentacao
- `documentation-architect.md` - Arquitetura de docs
- `documentation-specialist.md` - Especialista em docs
- `project-documentation-specialist.md` - Docs de projeto

### DevOps
- `docker-orchestrator.md` - Orquestracao Docker
- `observability-engineer.md` - Observabilidade

### Integracao
- `linear-project-sync.md` - Sincronizacao com Linear

## Estrutura de Saida

Apos usar o Cortex, seu projeto tera:

```
projeto/
├── docs/
│   ├── business-context/    # Contexto de negocio
│   ├── technical-context/   # Contexto tecnico
│   └── master-docs/         # Documentos mestres
├── reports/
│   ├── weekly/              # Relatorios semanais
│   ├── general/             # Relatorios gerais
│   └── docs/                # Documentos DOCX
└── .claude/                 # Framework Cortex
```

## Replicando para Outros Projetos

### Arquivos Essenciais

Para replicar o Cortex completo:

```bash
# Copiar tudo
cp -r .claude /novo-projeto/

# Instalar dependencias
cd /novo-projeto && npm install docx html2pptx pptxgenjs --save-dev
```

### Apenas Skill DOCX

Para replicar apenas a geracao de documentos:

```bash
# Criar estrutura
mkdir -p /novo-projeto/.claude/skills/docx
mkdir -p /novo-projeto/.claude/commands/docx
mkdir -p /novo-projeto/.claude/scripts/docx

# Copiar arquivos
cp .claude/skills/docx/SKILL.MD /novo-projeto/.claude/skills/docx/
cp .claude/commands/docx/report.md /novo-projeto/.claude/commands/docx/
cp .claude/scripts/docx/generator.js /novo-projeto/.claude/scripts/docx/

# Instalar dependencia
cd /novo-projeto && npm install docx --save-dev
```

## Documentacao Adicional

- [docs/CORTEX.md](docs/CORTEX.md) - Guia completo de uso
- [docs/WORKFLOWS.md](docs/WORKFLOWS.md) - Workflows detalhados
- [docs/COMMANDS.md](docs/COMMANDS.md) - Referencia de comandos
- [.claude/scripts/reports/README.md](.claude/scripts/reports/README.md) - Sistema de relatorios

## Licenca

Proprietary - Veja LICENSE.txt para termos completos.
