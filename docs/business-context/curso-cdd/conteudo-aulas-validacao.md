# Curso Context-Driven Development com Cortex

## Conteúdo Detalhado das 10 Aulas para Validação

**Instrutor:** Rafael Fiales
**Formato:** Online ao vivo | 10 aulas de 2 horas
**Público:** PMs, Tech Leads, Engenheiros, Designers, CTOs, CPOs

---

# MÓDULO 1: FUNDAMENTOS E VISÃO

---

## AULA 1: A Revolução do Context-Driven Development

### Slide 1 - Capa
- **Título:** CONTEXT-DRIVEN DEVELOPMENT
- **Subtítulo:** Masterclass com Rafael Fiales
- **Destaque:** Framework Cortex
- **Tagline:** "Transformando o desenvolvimento de software com IA"

### Slide 2 - O Problema
- **Título:** O Desperdício Invisível no Desenvolvimento
- **Métricas de impacto:**
  - 60% do tempo é desperdiçado em retrabalho
  - 40% dos requisitos são mal interpretados
  - 3-5x mais tokens gastos sem contexto estruturado
- **Pergunta provocativa:** "Quanto sua empresa perde por mês com código errado?"

### Slide 3 - A Raiz do Problema
- **Título:** Por que a IA falha sem contexto?
- **3 problemas principais:**
  1. **Contexto fragmentado** - Informações espalhadas em docs, Slack, reuniões
  2. **Perda de memória** - Cada conversa começa do zero
  3. **Silos de conhecimento** - Negócio, Produto e Engenharia não se comunicam
- **Ilustração:** Diagrama de silos vs. fluxo integrado

### Slide 4 - Case: R$5 Milhões em 1 Ano
- **Título:** Como o Cortex economizou R$5MM
- **Cenário antes:**
  - 20 desenvolvedores equivalentes necessários
  - Custo mensal: R$400k
  - Retrabalho constante
- **Cenário depois:**
  - 2 desenvolvedores com Cortex
  - Custo mensal: R$40k
  - Zero retrabalho
- **Economia:** R$360k/mês = R$4.3MM/ano

### Slide 5 - A Solução: Context-Driven Development
- **Título:** O que é CDD?
- **Definição:** "Framework que estrutura contexto em 3 camadas para maximizar a eficácia de agentes de IA no desenvolvimento de software"
- **As 3 camadas:**
  1. **Negócio** - Visão, stakeholders, modelo de negócio
  2. **Produto** - Requisitos, PRDs, especificações
  3. **Engenharia** - Arquitetura, código, testes
- **Princípio:** "Cada camada gera contexto de alto nível para a próxima"

### Slide 6 - Arquitetura do Cortex
- **Título:** O Framework Cortex v2.2
- **Componentes:**
  - 52 agentes especializados
  - 30+ comandos padronizados
  - Skills reutilizáveis (DOCX, PPTX)
  - Integração com Linear
  - Context Enhancement (60% economia de tokens)
- **Diagrama:** Arquitetura visual do framework

### Slide 7 - Demo: Workflow End-to-End
- **Título:** Veja o Cortex em Ação
- **Fluxo demonstrado:**
  ```
  /warm-up → /collect → /spec → /check → /light-arch → /start → /plan → /work → /pre-pr → /pr
  ```
- **Tempo da demo:** 30 minutos
- **O que será mostrado:** Feature completa do zero ao PR

### Slide 8 - Setup do Ambiente
- **Título:** Mãos na Massa: Instalação
- **Passos:**
  1. Clonar repositório do curso
  2. Copiar .claude para seu projeto
  3. Verificar Claude Code funcionando
  4. Executar /warm-up
- **Tarefa:** Trazer /warm-up executado para próxima aula

### Slide 9 - Recapitulação
- **Título:** O que aprendemos hoje
- **Pontos-chave:**
  - O problema do contexto fragmentado
  - Case de R$5MM de economia
  - As 3 camadas do CDD
  - Arquitetura do Cortex
- **Próxima aula:** Fundamentos de LLMs e Prompt Engineering

---

## AULA 2: Fundamentos de LLMs e Prompt Engineering

### Slide 1 - Capa
- **Título:** FUNDAMENTOS DE LLMs
- **Subtítulo:** Entendendo a máquina antes de dirigi-la
- **Aula:** 2 de 10

### Slide 2 - Anatomia de um LLM
- **Título:** Como LLMs processam texto
- **Conceitos:**
  - **Tokens:** Unidades de texto (palavras, sílabas)
  - **Janela de contexto:** 128K-200K tokens
  - **Attention:** Como o modelo "presta atenção"
- **Analogia:** "Imagine uma memória de trabalho limitada"

### Slide 3 - Tokens na Prática
- **Título:** O que custa um token?
- **Exemplos:**
  - "Hello" = 1 token
  - "Context-Driven Development" = 4 tokens
  - Um PRD médio = 2.000 tokens
  - Um codebase médio = 50.000+ tokens
- **Impacto financeiro:** $0.01-0.03 por 1K tokens (Claude)

### Slide 4 - Hands-on: Tokenização
- **Título:** Exercício: Visualizando Tokens
- **Ferramenta:** tiktoken playground
- **Atividades:**
  1. Tokenizar um prompt real
  2. Calcular custo de uma conversa
  3. Otimizar prompt para menos tokens

### Slide 5 - Prompt Engineering Essencial
- **Título:** As 4 técnicas que você precisa dominar
- **Técnicas:**
  1. **Chain of Thought (CoT)** - "Pense passo a passo"
  2. **Few-shot learning** - Exemplos no prompt
  3. **Role prompting** - Definir persona
  4. **Structured outputs** - JSON, Markdown
- **Impacto:** 40-60% de melhoria na qualidade

### Slide 6 - Chain of Thought
- **Título:** Pensamento em cadeia
- **Exemplo ruim:**
  ```
  "Calcule o custo do projeto"
  ```
- **Exemplo bom:**
  ```
  "Calcule o custo do projeto seguindo estes passos:
  1. Liste todos os recursos necessários
  2. Estime horas para cada recurso
  3. Aplique taxa horária
  4. Some os custos
  5. Adicione margem de 20%"
  ```

### Slide 7 - Structured Outputs
- **Título:** Outputs estruturados
- **Por que importa:** Facilita parsing e integração
- **Exemplo:**
  ```json
  {
    "feature": "Login com OAuth",
    "prioridade": "alta",
    "estimativa_horas": 16,
    "dependencias": ["auth-service", "user-db"]
  }
  ```

### Slide 8 - Hands-on: Construindo Prompts
- **Título:** Exercícios práticos
- **Exercício 1:** Criar prompt para análise de requisitos
- **Exercício 2:** Prompt para code review
- **Exercício 3:** Prompt estruturado com output JSON
- **Tempo:** 30 minutos

### Slide 9 - Como o Cortex usa Prompt Engineering
- **Título:** Anatomia de um comando Cortex
- **Estrutura de um comando .md:**
  - Role definition
  - Context loading
  - Step-by-step instructions
  - Output format
  - Constraints
- **Exemplo:** Análise do comando /collect

### Slide 10 - Tarefa para Próxima Aula
- **Título:** Preparação
- **Atividade:**
  1. Analisar 2 comandos do Cortex
  2. Identificar técnicas de prompt usadas
  3. Trazer dúvidas sobre estrutura
- **Próxima aula:** Controle de Contexto e Agentes

---

## AULA 3: Controle de Contexto e Agentes de IA

### Slide 1 - Capa
- **Título:** CONTROLE DE CONTEXTO E AGENTES
- **Subtítulo:** O segredo da produtividade 10x
- **Aula:** 3 de 10

### Slide 2 - O Problema do Contexto Perdido
- **Título:** Por que conversas longas degradam?
- **Gráfico:** Qualidade vs. tamanho da conversa
- **Causas:**
  - Limite de janela de contexto
  - Diluição de informações importantes
  - Conflito entre instruções antigas e novas

### Slide 3 - Estratégias de Context Management
- **Título:** Como gerenciar contexto eficientemente
- **3 estratégias:**
  1. **Summarization** - Resumir conversas longas
  2. **RAG** - Recuperar contexto sob demanda
  3. **Context Enhancement** - Carregar seletivamente
- **Cortex usa:** Context Enhancement (60% economia)

### Slide 4 - Case: 60% de Economia de Tokens
- **Título:** Antes e depois do Context Enhancement
- **Antes (v1.x):**
  - 10.000 tokens por feature
  - 15 violações de ADR
  - 30% de retrabalho
- **Depois (v2.0):**
  - 4.000 tokens por feature
  - 1 violação por feature
  - <5% de retrabalho

### Slide 5 - De Chatbots a Agentes
- **Título:** A evolução da IA conversacional
- **Níveis:**
  1. **Chatbot** - Pergunta → Resposta
  2. **Assistente** - Mantém contexto
  3. **Agente** - Tem ferramentas e autonomia
- **Diferencial:** Agentes podem AGIR, não só responder

### Slide 6 - Arquitetura de um Agente
- **Título:** Como agentes funcionam
- **Componentes:**
  - **Prompt base** - Persona e instruções
  - **Tools** - Ações disponíveis (read, write, bash)
  - **Memory** - Contexto da sessão
  - **Planning** - Capacidade de planejar tarefas
- **Diagrama:** ReAct loop (Reason → Act → Observe)

### Slide 7 - Hands-on: Anatomia de um Agente Cortex
- **Título:** Analisando backend-architect.md
- **Elementos identificados:**
  - Persona e especialização
  - Capabilities listadas
  - Constraints definidas
  - Output format esperado
- **Tempo:** 20 minutos

### Slide 8 - Os 52 Agentes do Cortex
- **Título:** Especialistas por domínio
- **Categorias:**
  - Backend (4): architect, python, database, cleanup
  - Frontend (6): architect, react, ux-ui, mockup
  - Qualidade (7): test-engineer, code-reviewer, etc.
  - Documentação (5): architect, specialist, etc.
  - DevOps (2): docker, observability
  - Integração (2): linear-sync, task-coordinator

### Slide 9 - Hands-on: Criando Seu Primeiro Agente
- **Título:** Workshop: /meta:create-agent
- **Passos:**
  1. Definir caso de uso do aluno
  2. Executar comando de criação
  3. Personalizar agente
  4. Testar com tarefa real
- **Tempo:** 25 minutos

### Slide 10 - Recapitulação e Próximos Passos
- **Título:** O que aprendemos
- **Pontos-chave:**
  - Context management strategies
  - Diferença chatbot vs agente
  - Arquitetura multi-agente do Cortex
- **Próxima aula:** Camada de Negócio

---

# MÓDULO 2: AS 3 CAMADAS

---

## AULA 4: Camada de Negócio - A Base do Contexto

### Slide 1 - Capa
- **Título:** CAMADA DE NEGÓCIO
- **Subtítulo:** Se o agente não entende o negócio, o código será errado
- **Aula:** 4 de 10

### Slide 2 - Por que Negócio Primeiro?
- **Título:** A pirâmide do contexto
- **Diagrama:**
  ```
        [Engenharia]
          /    \
      [Produto]
        /    \
    [Negócio]  ← Fundação
  ```
- **Princípio:** "Código sem contexto de negócio é código errado"

### Slide 3 - O Erro Comum
- **Título:** Pular direto para código
- **Cenário típico:**
  1. PM pede "botão de exportar"
  2. Dev implementa exportar para CSV
  3. PM queria PDF com formatação
  4. Retrabalho de 8 horas
- **Custo:** R$2.000+ por mal-entendido

### Slide 4 - Case: Requisito Mal Entendido
- **Título:** 3 versões erradas vs 1 correta
- **Sem contexto:**
  - Versão 1: Exportar básico (errado)
  - Versão 2: Formato errado (errado)
  - Versão 3: Sem permissões (errado)
  - Total: 24 horas desperdiçadas
- **Com contexto:**
  - Versão 1: Correto de primeira
  - Total: 8 horas (economia de 67%)

### Slide 5 - O Comando /collect
- **Título:** Coletando requisitos estruturados
- **O que faz:**
  - Entrevista estruturada
  - Identifica stakeholders
  - Mapeia restrições
  - Documenta premissas
- **Agentes acionados:** @discovery-analyst

### Slide 6 - Workshop /collect
- **Título:** Mãos na massa
- **Atividade:**
  1. Cada aluno escolhe uma feature real
  2. Executa /collect
  3. Responde perguntas do agente
  4. Revisa output gerado
- **Tempo:** 30 minutos

### Slide 7 - O Comando /build-business-docs
- **Título:** Documentação estruturada de negócio
- **Outputs gerados:**
  - vision.md - Visão estratégica
  - stakeholders.md - Partes interessadas
  - business-model.md - Modelo de negócio
- **Localização:** docs/business-context/

### Slide 8 - Estrutura do Business Context
- **Título:** O que deve conter
- **Elementos:**
  - **Visão:** Para onde o produto vai
  - **Stakeholders:** Quem são e o que querem
  - **Modelo:** Como gera valor/receita
  - **Restrições:** Limites legais, técnicos, orçamento
  - **Glossário:** Termos do domínio

### Slide 9 - Hands-on: Criando Business Context
- **Título:** Exercício prático
- **Atividade:**
  1. Executar /build-business-docs
  2. Revisar e ajustar outputs
  3. Validar com colega
- **Tempo:** 25 minutos

### Slide 10 - Tarefa e Próxima Aula
- **Título:** Para casa
- **Tarefa:** Completar business context do seu projeto
- **Próxima aula:** Camada de Produto

---

## AULA 5: Camada de Produto - Traduzindo Negócio em Especificação

### Slide 1 - Capa
- **Título:** CAMADA DE PRODUTO
- **Subtítulo:** O PRD que a IA consegue implementar
- **Aula:** 5 de 10

### Slide 2 - O PM como Orquestrador de Contexto
- **Título:** Novo papel do Product Manager
- **Antes:** Escrever documentos longos
- **Agora:** Estruturar contexto para agentes
- **Competência-chave:** Traduzir negócio em specs acionáveis

### Slide 3 - Case: PRD Tradicional vs PRD para IA
- **Título:** Comparativo de eficácia
- **PRD tradicional:**
  - Vago e ambíguo
  - 80% de perguntas de clarificação
  - Interpretações múltiplas
- **PRD para IA:**
  - Estruturado e específico
  - 20% de perguntas
  - Implementação previsível

### Slide 4 - O Comando /refine
- **Título:** Refinando requisitos
- **O que faz:**
  - Transforma ideias vagas em specs
  - Adiciona critérios de aceitação
  - Identifica edge cases
  - Valida contra business context
- **Demo:** Ao vivo

### Slide 5 - Workshop /refine
- **Título:** Exercício prático
- **Atividade:**
  1. Selecionar uma feature do business context
  2. Executar /refine
  3. Iterar até spec clara
- **Tempo:** 20 minutos

### Slide 6 - O Comando /spec
- **Título:** Gerando PRD completo
- **Estrutura do PRD:**
  - Visão geral da feature
  - User stories
  - Critérios de aceitação
  - Dependências técnicas
  - Riscos identificados

### Slide 7 - Anatomia do PRD Cortex
- **Título:** Seções obrigatórias
- **Template:**
  ```markdown
  # Feature: [Nome]

  ## Contexto de Negócio
  [Link para business context]

  ## User Stories
  Como [persona], quero [ação], para [benefício]

  ## Critérios de Aceitação
  - [ ] Critério 1
  - [ ] Critério 2

  ## Dependências Técnicas
  - API X
  - Serviço Y
  ```

### Slide 8 - Hands-on: Criando PRD
- **Título:** Workshop /spec
- **Atividade:**
  1. Executar /spec para feature refinada
  2. Revisar PRD gerado
  3. Ajustar e completar
- **Tempo:** 20 minutos

### Slide 9 - Validação com /check e /light-arch
- **Título:** Garantindo consistência antes de codar
- **/check - Alinhamento com Master Docs:**
  - Verifica fit com business context
  - Identifica desalinhamentos
  - Exige correção antes de prosseguir
- **/light-arch - Arquitetura Inicial:**
  - Examina requirements e faz perguntas
  - Define componentes afetados
  - Propõe design arquitetural
  - Salva como comentário no Linear

### Slide 10 - Ponte para Engenharia
- **Título:** Do PRD ao código com validação
- **Fluxo completo:**
  ```
  PRD → /check → /light-arch → /start → /plan → /work → /pre-pr → /pr
  ```
- **Comandos de transição:**
  - **/check** - Valida alinhamento com master docs
  - **/light-arch** - Arquitetura inicial da feature
- **Próxima aula:** Camada de Engenharia

---

## AULA 6: Camada de Engenharia - Do Plano ao Código

### Slide 1 - Capa
- **Título:** CAMADA DE ENGENHARIA
- **Subtítulo:** O fluxo que elimina 90% do retrabalho
- **Aula:** 6 de 10

### Slide 2 - O Fluxo de Engenharia do Cortex
- **Título:** O pipeline completo
- **Fluxo após /spec:**
  ```
  /check → /light-arch → /start → /plan → /work → /pre-pr → /pr
  ```
- **Princípio:** "Validar antes de codar, revisar antes de mergear"

### Slide 3 - Case: Reativo vs Proativo
- **Título:** A mudança de paradigma do v2.0
- **Abordagem reativa (v1.x):**
  - Código → Erro → Correção → Desperdício
  - 15 violações de ADR por feature
- **Abordagem proativa (v2.0):**
  - ADRs → Código correto → Validação OK
  - 1 violação por feature

### Slide 4 - O Comando /start
- **Título:** Iniciando uma feature
- **O que faz:**
  1. Cria sessão de trabalho
  2. Carrega contexto relevante
  3. Identifica ADRs aplicáveis
  4. Gera context.md enriquecido
- **Output:** .claude/sessions/[feature]/context.md

### Slide 5 - Context Enhancement em Ação
- **Título:** Carregamento seletivo
- **Perguntas do /start:**
  - Envolve frontend? [s/n]
  - Áreas impactadas? [checkboxes]
  - ADRs relevantes? [auto-detectado]
- **Resultado:** Apenas contexto necessário carregado

### Slide 6 - Hands-on: Iniciando Feature
- **Título:** Exercício /start
- **Atividade:**
  1. Selecionar feature do PRD
  2. Executar /start "[feature-name]"
  3. Responder perguntas
  4. Analisar context.md gerado
- **Tempo:** 20 minutos

### Slide 7 - O Comando /plan
- **Título:** Planejamento faseado
- **Estrutura do plan.md:**
  ```markdown
  ## FASE 1: Setup [Não Iniciada]
  - [ ] Tarefa 1.1
  - [ ] Tarefa 1.2

  ## FASE 2: Implementação [Não Iniciada]
  - [ ] Tarefa 2.1
  ...
  ```
- **Princípio:** Fases sequenciais, tarefas paralelizáveis

### Slide 8 - O Comando /work
- **Título:** Execução com conformidade
- **Fluxo interno:**
  1. ANTES: Consulta ADRs
  2. DURANTE: Implementa conforme regras
  3. APÓS: Valida conformidade
- **Resultado:** Código 100% conforme desde o início

### Slide 9 - Hands-on: Planejando e Executando
- **Título:** Workshop /plan + /work
- **Atividade:**
  1. Executar /plan
  2. Revisar plan.md
  3. Executar /work (primeira fase)
  4. Observar consulta de ADRs
- **Tempo:** 20 minutos

### Slide 10 - O Comando /pre-pr (CRÍTICO)
- **Título:** A validação final antes do PR
- **Por que é o mais importante:**
  - Última linha de defesa
  - Garante conformidade total
- **4 agentes acionados:**
  1. **branch-master-docs-checker** - Alinhamento com master docs
  2. **branch-code-reviewer** - Revisão de código
  3. **branch-documentation-writer** - Atualiza documentação
  4. **branch-test-planner** - Valida cobertura de testes
- **Resultado:** PR aprovado de primeira

### Slide 11 - Próxima Aula: Ciclo Completo
- **Título:** Integrando as 3 camadas
- **Prévia:** Workshop de 70 minutos
- **Objetivo:** Executar Negócio → Produto → Engenharia

---

## AULA 7: Integração das 3 Camadas - O Ciclo Completo

### Slide 1 - Capa
- **Título:** INTEGRAÇÃO DAS 3 CAMADAS
- **Subtítulo:** Quando tudo funciona junto
- **Aula:** 7 de 10

### Slide 2 - Revisão: As 3 Camadas
- **Título:** Recapitulação rápida
- **Diagrama:**
  ```
  NEGÓCIO       →    PRODUTO     →    ENGENHARIA
     ↓                   ↓                 ↓
  /collect          /refine          /check
  /build-*           /spec           /light-arch
                                     /start → /plan → /work
                                     /pre-pr → /pr
  ```

### Slide 3 - O Fluxo de Contexto
- **Título:** Como contexto flui entre camadas
- **Ilustração:**
  - Business context alimenta PRD
  - PRD alimenta context.md
  - context.md guia implementação
  - Implementação valida contra negócio

### Slide 4 - Case: Feature Completa em 4 Horas
- **Título:** Timeline real
- **Sem Cortex:** 3 dias (24h+)
- **Com Cortex:**
  - 30min: Business context
  - 30min: PRD
  - 30min: Start + Plan
  - 2h: Implementação
  - 30min: PR
  - **Total: 4 horas**

### Slide 5 - Workshop: O Grande Exercício
- **Título:** Ciclo completo em 70 minutos
- **Timeline:**
  - 0-15min: /collect + /build-business-docs
  - 15-30min: /refine + /spec + /check
  - 30-45min: /light-arch + /start + /plan
  - 45-60min: /work (1 fase)
  - 60-70min: /pre-pr (4 agentes)
- **Foco:** Feature real do projeto do aluno

### Slide 6-7 - Workshop em Andamento
- **Título:** [Slides de suporte durante workshop]
- **Conteúdo:** Instruções passo a passo visíveis

### Slide 8 - Retrospectiva
- **Título:** O que funcionou bem?
- **Perguntas para discussão:**
  - Onde houve atrito?
  - O que surpreendeu?
  - Como adaptar para sua realidade?

### Slide 9 - Lições Aprendidas
- **Título:** Insights do workshop
- **Padrões observados:**
  - Importância do business context
  - Valor do refinamento
  - Economia real de tempo

### Slide 10 - Próximo Módulo
- **Título:** Avançando: Context Enhancement
- **Prévia:**
  - Sistema de Discovery
  - ADRs como guias
  - Integrações e escala

---

# MÓDULO 3: AVANÇADO E ESCALA

---

## AULA 8: Context Enhancement e Discovery

### Slide 1 - Capa
- **Título:** CONTEXT ENHANCEMENT
- **Subtítulo:** O segredo da economia de 60% de tokens
- **Aula:** 8 de 10

### Slide 2 - O Problema do Contexto Crescente
- **Título:** Quando o projeto fica grande demais
- **Cenários:**
  - Projeto com 50+ ADRs
  - Documentação extensa
  - Múltiplas convenções
- **Desafio:** Carregar tudo = ineficiente e caro

### Slide 3 - O Sistema de Discovery
- **Título:** /discover - Mapeamento inteligente
- **O que faz:**
  1. Analisa ADRs existentes
  2. Extrai regras críticas
  3. Gera briefings modulares
  4. Prepara carregamento seletivo

### Slide 4 - Briefings Modulares
- **Título:** Estrutura gerada pelo /discover
- **Arquivos:**
  ```
  docs/technical-context/
  ├── project-briefing.md     (índice)
  └── briefing/
      ├── critical-rules.md   (regras obrigatórias)
      ├── adrs-summary.md     (ADRs por categoria)
      ├── backend-conventions.md
      └── tech-stack.md
  ```

### Slide 5 - Hands-on: Implementando Discovery
- **Título:** Exercício /discover
- **Atividade:**
  1. Criar algumas ADRs de exemplo
  2. Executar /discover
  3. Analisar briefings gerados
  4. Testar carregamento seletivo
- **Tempo:** 25 minutos

### Slide 6 - ADRs: A Base do Context Enhancement
- **Título:** O que são Architecture Decision Records
- **Estrutura:**
  ```markdown
  # ADR-001: [Título]

  ## Contexto
  Por que essa decisão foi necessária

  ## Decisão
  O que decidimos

  ## Consequências
  Impactos positivos e negativos
  ```

### Slide 7 - ADRs Eficazes
- **Título:** Como escrever ADRs que funcionam
- **Dicas:**
  - Seja específico e acionável
  - Inclua exemplos de código
  - Documente o "porquê"
  - Mantenha atualizadas

### Slide 8 - Hands-on: Criando ADRs
- **Título:** Workshop de ADRs
- **Atividade:**
  1. Criar 2-3 ADRs para seu projeto
  2. Re-executar /discover
  3. Verificar no /start
- **Tempo:** 25 minutos

### Slide 9 - Métricas de Otimização
- **Título:** Como medir economia
- **Métricas:**
  - Tokens por feature (antes/depois)
  - Violações de ADR
  - Tempo de correção
  - % de retrabalho

### Slide 10 - Próxima Aula: Integrações
- **Título:** Levando para produção
- **Prévia:**
  - Integração com Linear
  - Relatórios automatizados
  - Plano de adoção

---

## AULA 9: Integrações, Reports e Governança

### Slide 1 - Capa
- **Título:** INTEGRAÇÕES E GOVERNANÇA
- **Subtítulo:** Cortex na operação real do time
- **Aula:** 9 de 10

### Slide 2 - Integração com Linear
- **Título:** Sincronização de projeto
- **Recursos:**
  - /product:sync-linear
  - Criação automática de épicos
  - Atualização de cards em tempo real
  - Rastreabilidade completa

### Slide 3 - Workflow com Linear
- **Título:** Fluxo obrigatório
- **Passos:**
  1. Ao iniciar: Card → "In Progress"
  2. Durante: Comentários de progresso
  3. Ao abrir PR: Card → "In Review"
  4. Após merge: Card → "Done"

### Slide 4 - Hands-on: Configurando Linear
- **Título:** Exercício de integração
- **Atividade:**
  1. Conectar Linear ao projeto
  2. Executar /product:sync-linear
  3. Verificar cards criados
- **Tempo:** 20 minutos

### Slide 5 - Sistema de Relatórios
- **Título:** Documentação automatizada
- **Comandos:**
  - /report:weekly → PPTX semanal
  - /report:general → PPTX geral
  - /docx:report → Documento Word
- **Temas:** px, cortex, minimal, dark

### Slide 6 - Hands-on: Gerando Relatórios
- **Título:** Workshop de reports
- **Atividade:**
  1. Gerar relatório semanal
  2. Gerar documento DOCX
  3. Personalizar tema
- **Tempo:** 15 minutos

### Slide 7 - Governança e Escala
- **Título:** Estratégia de adoção
- **Pilares:**
  1. **Onboarding:** Como treinar novos membros
  2. **Padronização:** Comandos obrigatórios
  3. **Customização:** Agentes específicos
  4. **Métricas:** KPIs de sucesso

### Slide 8 - Plano 30-60-90 dias
- **Título:** Roadmap de adoção
- **30 dias:**
  - Piloto com 2-3 pessoas
  - Comandos básicos
- **60 dias:**
  - Expansão para time completo
  - Customização de agentes
- **90 dias:**
  - Métricas consolidadas
  - Governança estabelecida

### Slide 9 - Hands-on: Plano de Adoção
- **Título:** Exercício final
- **Atividade:**
  - Cada aluno cria plano para sua empresa
  - Template 30-60-90
  - Discussão em grupo
- **Tempo:** 20 minutos

### Slide 10 - Preparação para Projeto Final
- **Título:** Próxima aula: Apresentações
- **Requisitos do projeto:**
  1. Usar pelo menos 2 camadas
  2. Demonstrar fluxo completo
  3. Apresentar métricas
  4. 8-10 minutos de apresentação

---

# MÓDULO 4: PROJETO FINAL

---

## AULA 10: Projeto Final - Implementação e Apresentação

### Slide 1 - Capa
- **Título:** PROJETO FINAL
- **Subtítulo:** Prova de conceito real do CDD
- **Aula:** 10 de 10

### Slide 2 - Formato das Apresentações
- **Título:** Como será a dinâmica
- **Regras:**
  - 8-10 minutos por apresentação
  - Demo do projeto implementado
  - Métricas obrigatórias
  - Q&A breve (2 min)

### Slide 3 - Critérios de Avaliação
- **Título:** O que será avaliado
- **Critérios:**
  1. Uso correto das camadas (30%)
  2. Qualidade do fluxo (30%)
  3. Métricas de resultado (20%)
  4. Documentação gerada (20%)

### Slide 4-8 - [Espaço para Apresentações]
- **Título:** Apresentações dos Projetos
- **Conteúdo:** Gerenciado ao vivo

### Slide 9 - Certificação
- **Título:** Parabéns aos concluintes!
- **Métricas do curso:**
  - X alunos certificados
  - Y projetos apresentados
  - Z horas de prática

### Slide 10 - Próximos Passos
- **Título:** Continue a jornada
- **Recursos:**
  - Comunidade de praticantes
  - Repositório do framework
  - Suporte pós-curso
  - Atualizações do Cortex

### Slide 11 - Obrigado!
- **Título:** OBRIGADO!
- **Métricas destacadas:**
  - 10 aulas
  - 20 horas
  - Framework completo
- **Mensagem:** "Transforme seu time com CDD"
- **Contato:** Rafael Fiales

---

# ANEXOS

## Materiais por Aula

| Aula | Slides | Exercícios | Demo | Tempo Prático |
|------|--------|------------|------|---------------|
| 1 | 9 | 1 | Workflow completo | 20 min |
| 2 | 10 | 3 | Tokenização | 45 min |
| 3 | 10 | 2 | Criar agente | 45 min |
| 4 | 10 | 2 | /collect, /build | 55 min |
| 5 | 10 | 2 | /refine, /spec, /check, /light-arch | 45 min |
| 6 | 11 | 2 | /start, /plan, /work, /pre-pr | 45 min |
| 7 | 10 | 1 | Ciclo completo | 70 min |
| 8 | 10 | 2 | /discover, ADRs | 50 min |
| 9 | 10 | 3 | Linear, Reports | 55 min |
| 10 | 11 | - | Apresentações | 80 min |

## Dependências Técnicas

- Claude Code (Anthropic)
- Repositório Cortex
- Projeto-base para exercícios
- Conta Linear (opcional)
- Node.js para scripts

---

**Status:** AGUARDANDO VALIDAÇÃO

Por favor, revise o conteúdo acima e confirme se:
1. Os tópicos estão adequados
2. A profundidade está correta
3. Os exercícios fazem sentido
4. Algo precisa ser adicionado/removido

Após sua validação, gerarei os HTMLs dos slides com o estilo CSS que você enviar (AI Frontiers).
