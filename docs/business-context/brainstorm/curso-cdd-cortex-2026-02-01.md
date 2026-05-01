# Brainstorm: Curso de Context-Driven Development com Cortex

**Data:** 2026-02-01
**Participantes:** Rafael Fiales + Claude
**Duração:** ~45min

---

## Contexto

### Problema/Oportunidade
Criar um curso de 10 aulas (2h cada) sobre Context-Driven Development usando o framework Cortex, posicionando Rafael Fiales como autoridade no assunto no Brasil.

### Gatilho da Discussão
- Framework Cortex economizou R$5MM em 1 ano
- Demanda por formação estruturada em CDD
- Oportunidade de escalar conhecimento e impacto

### Público-Alvo
- PMs, Tech Leads, Engenheiros Full Stack/Backend/Frontend
- Designers, CTOs, CPOs
- Nível: Intermediário em IA (usam ChatGPT/Claude, mas sem metodologia)

### Restrições
- 10 aulas de 2h cada
- Formato: Online ao vivo
- Acesso hands-on total ao Cortex
- IDE: Claude Code (Anthropic)
- Objetivo: Adoção do Cortex nas empresas dos alunos
- Projeto final obrigatório

---

## Alternativas Exploradas

### Alternativa A: Bottom-Up (Técnico → Metodologia)

**Descrição:** Começar pelos fundamentos técnicos de LLMs e subir para a metodologia CDD.

**Vantagens:**
- Constrói base sólida de conhecimento técnico
- Alunos entendem o "porquê" antes do "como"
- Gradativo e pedagógico
- Bom para nivelamento de público heterogêneo

**Desvantagens:**
- Pode parecer lento para CTOs/CPOs
- Valor prático demora a aparecer
- Risco de perder engajamento nas primeiras aulas

**Esforço:** Médio
**Impacto:** Alto (para adoção técnica)

---

### Alternativa B: Top-Down (Transformação → Técnica)

**Descrição:** Começar pelo impacto transformacional e ROI, depois descer para implementação técnica.

**Vantagens:**
- Engaja C-level desde o início
- Mostra valor imediato
- Motiva aprendizado técnico posterior
- Cases como fio condutor

**Desvantagens:**
- Pode frustrar técnicos que querem profundidade logo
- Risco de parecer "comercial" demais
- Fundamentos podem parecer desconectados

**Esforço:** Médio
**Impacto:** Alto (para decisão de adoção)

---

### Alternativa C: Espiral (Teoria-Prática Intercalada)

**Descrição:** Alternar entre conceito e prática desde a primeira aula. Cada módulo tem teoria + hands-on + case.

**Vantagens:**
- Teoria e prática sempre juntas
- Engaja todos os perfis (CTOs e devs)
- Valor prático em todas as aulas
- Alunos saem com experiência real

**Desvantagens:**
- Mais complexo de preparar
- Exige infraestrutura hands-on robusta
- Pode parecer "corrido" em 2h por aula

**Esforço:** Alto
**Impacto:** Muito Alto (para adoção efetiva)

---

## Análise de Trade-offs

| Critério | Alt A (Bottom-Up) | Alt B (Top-Down) | Alt C (Espiral) |
|----------|------------------|------------------|-----------------|
| Engajamento C-level | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |
| Profundidade técnica | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Aplicabilidade imediata | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Adequação público misto | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Facilidade de preparação | ⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐ |
| Fit com projeto final | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Memorabilidade | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

---

## Decisão/Recomendação

**Recomendação:** Alternativa C (Espiral) com elementos da B (cases como fio condutor)

**Justificativa:**
1. **Público heterogêneo (PMs a CTOs)**: A abordagem espiral mantém todos engajados
2. **Hands-on total**: Cada aula terá prática, maximizando o acesso ao framework
3. **Projeto final**: A construção progressiva prepara naturalmente para o projeto
4. **Cases múltiplos**: Podem ser inseridos em cada módulo como exemplos reais
5. **Objetivo de adoção**: A prática desde a aula 1 acelera a curva de adoção

---

## Currículo Detalhado: 10 Aulas de 2 Horas

### MÓDULO 1: FUNDAMENTOS E VISÃO (Aulas 1-3)

#### AULA 1: A Revolução do Context-Driven Development
*"Por que 60% do tempo de desenvolvimento é desperdício e como resolver"*

| Tempo | Conteúdo |
|-------|----------|
| 0-30min | O Problema do Desperdício de Contexto |
| 30-45min | Case: R$5MM em 1 ano |
| 45-75min | O Framework Cortex - As 3 Camadas |
| 75-110min | Demo: Workflow End-to-End |
| 110-120min | Setup do Ambiente + /warm-up |

---

#### AULA 2: Fundamentos de LLMs e Prompt Engineering
*"Entendendo a máquina antes de dirigi-la"*

| Tempo | Conteúdo |
|-------|----------|
| 0-20min | Anatomia de um LLM (tokens, contexto) |
| 20-40min | Hands-on: Tokenização |
| 40-70min | Prompt Engineering Essencial |
| 70-100min | Hands-on: Construindo Prompts |
| 100-120min | Como o Cortex usa Prompt Engineering |

---

#### AULA 3: Controle de Contexto e Agentes de IA
*"O segredo da produtividade 10x: contexto estruturado"*

| Tempo | Conteúdo |
|-------|----------|
| 0-25min | O Problema do Contexto Perdido |
| 25-45min | Case: 60% de economia de tokens |
| 45-70min | De Chatbots a Agentes |
| 70-90min | Hands-on: Anatomia de um Agente Cortex |
| 90-115min | Hands-on: Criando Seu Primeiro Agente |
| 115-120min | Arquitetura Multi-Agente do Cortex |

---

### MÓDULO 2: AS 3 CAMADAS (Aulas 4-7)

#### AULA 4: Camada de Negócio - A Base do Contexto
*"Se o agente não entende o negócio, o código será errado"*

| Tempo | Conteúdo |
|-------|----------|
| 0-20min | Por que Negócio Primeiro? |
| 20-40min | Case: Requisito mal entendido |
| 40-60min | O Comando /collect |
| 60-90min | Workshop /collect |
| 90-105min | O Comando /build-business-docs |
| 105-120min | Hands-on: Criando Business Context |

---

#### AULA 5: Camada de Produto - Traduzindo Negócio em Especificação
*"O PRD que a IA consegue implementar"*

| Tempo | Conteúdo |
|-------|----------|
| 0-25min | O PM como Orquestrador de Contexto |
| 25-40min | Case: PRD tradicional vs PRD para IA |
| 40-55min | O Comando /refine |
| 55-75min | Workshop /refine |
| 75-95min | O Comando /spec |
| 95-120min | Hands-on: Criando PRD + Validação |

---

#### AULA 6: Camada de Engenharia - Do Plano ao Código
*"O fluxo que elimina 90% do retrabalho"*

| Tempo | Conteúdo |
|-------|----------|
| 0-20min | O Fluxo de Engenharia do Cortex |
| 20-35min | Case: Reativo vs Proativo |
| 35-55min | O Comando /start |
| 55-75min | Hands-on: Iniciando uma Feature |
| 75-95min | Os Comandos /plan e /work |
| 95-120min | Hands-on: Planejando e Executando |

---

#### AULA 7: Integração das 3 Camadas - O Ciclo Completo
*"Quando tudo funciona junto"*

| Tempo | Conteúdo |
|-------|----------|
| 0-15min | Revisão: As 3 Camadas |
| 15-30min | Case: Feature completa em 4 horas |
| 30-100min | Workshop: Ciclo Completo (Negócio → Produto → Engenharia) |
| 100-115min | Retrospectiva do Workshop |
| 115-120min | Introdução ao Módulo Avançado |

---

### MÓDULO 3: AVANÇADO E ESCALA (Aulas 8-9)

#### AULA 8: Context Enhancement e Discovery
*"O segredo da economia de 60% de tokens"*

| Tempo | Conteúdo |
|-------|----------|
| 0-25min | O Problema do Contexto Crescente |
| 25-45min | O Sistema de Discovery (/discover) |
| 45-70min | Hands-on: Implementando Discovery |
| 70-90min | ADRs: A Base do Context Enhancement |
| 90-120min | Hands-on: Criando ADRs |

---

#### AULA 9: Integrações, Reports e Governança
*"Cortex na operação real do time"*

| Tempo | Conteúdo |
|-------|----------|
| 0-25min | Integração com Linear |
| 25-45min | Hands-on: Configurando Linear |
| 45-65min | Sistema de Relatórios (PPTX, DOCX) |
| 65-80min | Hands-on: Gerando Relatórios |
| 80-100min | Governança e Escala |
| 100-120min | Plano de Adoção 30-60-90 dias |

---

### MÓDULO 4: PROJETO FINAL (Aula 10)

#### AULA 10: Projeto Final - Implementação e Apresentação
*"Prova de conceito real do CDD"*

| Tempo | Conteúdo |
|-------|----------|
| 0-10min | Abertura e Formato |
| 10-90min | Apresentações dos Projetos (8-10 min cada) |
| 90-105min | Feedback e Certificação |
| 105-120min | Próximos Passos e Comunidade |

**Critérios do Projeto Final:**
1. Usar pelo menos 2 camadas do Cortex
2. Demonstrar fluxo completo de pelo menos 1 feature
3. Apresentar métricas (tokens, tempo, qualidade)
4. Documentação gerada pelo framework

---

## Materiais Necessários por Aula

| Aula | Materiais |
|------|-----------|
| 1 | Slides visão geral, vídeo case R$5MM, repo projeto-base |
| 2 | Playground tokens, exercícios prompt, código comandos Cortex |
| 3 | Diagrama context window, template agente, lista 52 agentes |
| 4 | Template business context, checklist /collect, exemplo docs |
| 5 | Template PRD, comparativo PRD tradicional vs CDD |
| 6 | Fluxograma engenharia, exemplo context.md e plan.md |
| 7 | Projeto-exemplo workshop, checklist ciclo completo |
| 8 | Template ADR, guias discover e ADR-proactive |
| 9 | Guia Linear, template plano adoção 30-60-90 |
| 10 | Template apresentação, rubrica avaliação, certificado |

---

## Próximos Passos

- [ ] Validar estrutura curricular com stakeholders
- [ ] Criar materiais da Aula 1 (piloto)
- [ ] Testar workshop com grupo beta
- [ ] Finalizar infraestrutura hands-on
- [ ] Criar sistema de certificação
- [ ] Definir preço e modelo de comercialização

---

## Aprendizados

1. **Público misto exige flexibilidade**: A abordagem espiral é ideal para misturar C-level e técnicos
2. **Hands-on é diferencial**: A prática desde a aula 1 é o que diferencia de cursos teóricos
3. **Cases múltiplos engajam mais**: Inserir cases em cada módulo mantém relevância
4. **Projeto final como prova de valor**: Alunos saem com algo tangível para mostrar
5. **Adoção como objetivo**: Não é só ensinar, é garantir que apliquem na empresa

---

**Status:** Aguardando feedback do humano para próximos passos.
