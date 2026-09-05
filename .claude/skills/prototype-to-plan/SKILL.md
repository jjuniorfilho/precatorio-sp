---
name: prototype-to-plan
description: Conduz um protótipo HTML navegável aprovado até um plano de entrega correto, respeitando a fundação de engenharia real do projeto. Lê ADRs, contrato OpenAPI, schema Prisma e libs existentes; trava as decisões de arquitetura ANTES da spec; gera PRD focado + ADRs ancorados no código real; e monta o plano no Linear decomposto por camada e contract-first, evitando o drift mock-vs-real. Use quando houver um protótipo aprovado e o usuário pedir "do protótipo pro Linear", "planejar a implementação do protótipo", "gerar PRD/ADR/tasks a partir do mockup", ou antes de rodar a frota sobre uma feature de UI nova.
argument-hint: "[caminho-do-prototipo]  (ex.: docs/prototypes/analista-portal/index.html)"
---

# Prototype → Plan — do protótipo aprovado ao plano de entrega correto

## Visão Geral

Esta skill transforma um **protótipo HTML navegável já validado** em três artefatos prontos para a frota: um **PRD focado**, os **ADRs** das decisões arquiteturais, e um **plano no Linear** decomposto por camada e sequenciado contract-first. Ela é a ponte entre `/ux-flow` (que produz o protótipo) e `/engineer:fleet` (que implementa).

**Ela não reimplementa `product:spec` nem `product:task` — ela os orquestra** com o enquadramento que faltava: leitura da fundação de engenharia real, trava-decisões antes da spec, e os guardrails anti-drift que evitam o padrão "UI linda em mock que não casa com o backend" (lição real de produção: um FE mock-first ficou bonito mas não vinculava dado no backend — param de query rejeitado, KPIs em skeleton). O valor da skill é o **processo**, não o conteúdo: o protótipo já carrega as decisões de UX; o que falta é grounding na realidade + sequência correta.

> **Nota de portabilidade.** Esta skill nasceu no projeto `px-agents` e foi promovida ao framework. Caminhos e comandos concretos citados adiante (ex.: `apps/api/openapi.json`, `pnpm contract:check`, `master-docs/.../adr/`) são **exemplos ilustrativos** desse projeto. Em outro projeto, descubra os equivalentes na Fase 0 (fundação) e adapte; não assuma os caminhos/IDs do px-agents.

## Quando invocar

- Há um protótipo aprovado (sign-off explícito) e o usuário quer planejar a implementação real.
- Pedidos: "do protótipo pro Linear", "gera o PRD e as tasks desse mockup", "planeja a frota dessa feature", "transforma esse protótipo em ADR/PRD/issues".
- Como Fase seguinte ao `/ux-flow prototype <slug>`, antes do `/engineer:fleet`.

**Não invocar** quando o protótipo ainda não foi aprovado (volte para `/ux-flow`), nem para um bug/ajuste pontual sem superfície nova (use `/product:task` direto).

## Princípios não-negociáveis desta skill

1. **Orquestrar, não duplicar.** PRD via o fluxo de `product:spec`; issues via o fluxo de `product:task`. A skill adiciona grounding + decomposição + sequência.
2. **Grounding no código real.** ADRs e PRD citam `arquivo:linha` e endpoints/tabelas que **existem**
   — afirmações aterrissadas em código real. Nunca inventar a fundação. O que já existe é **reuso**, não net-new.
3. **Trava-decisões é bloqueante.** Decisões transversais (papel/role, fronteira de app, tema, dado-como-sinal, escopo de tenant) são travadas via `AskUserQuestion` ANTES da spec. Decisão re-litigada no meio da frota é caro.
4. **Contract-first sempre.** O contrato (`apps/api/openapi.json` → `apps/admin/src/types/api.gen.ts`) aterrissa antes do FE consumi-lo. Nunca paralelizar FE com o BE que define seu contrato.
5. **Validação em modo real é critério de aceitação**, não afterthought (`VITE_USE_MOCKS=false` contra API seedada).
6. **Right-size.** Feature spec, não epic PRD. ADR só para decisão genuinamente arquitetural.

## Pré-requisitos (verifique antes de começar)

- **Protótipo aprovado e commitado.** Se estiver untracked (`git status` mostra `??`), peça para commitar primeiro — o Linear precisa referenciar um artefato durável. Ofereça o commit.
- **Projeto com fundação documentada:** ADRs em `master-docs/technical-context/adr/`, contrato em `apps/api/openapi.json`, schema em `libs/database/prisma/schema.prisma`. Se faltar, a skill ainda funciona, mas avise que o grounding será mais raso.

---

## Fase 0 — Ingestão & grounding (ler a realidade)

Objetivo: inventariar o protótipo E mapear o que já existe na fundação, separando **reuso** de **net-new**. Esta fase é o que torna o plano honesto.

### 0.1 Inventariar o protótipo

Leia o(s) HTML do protótipo e extraia, sem interpretar demais:
- **Telas/superfícies** (cada `data-screen`, rota, ou arquivo).
- **Fluxos** (navegação entre telas, o caminho-feliz).
- **Interações net-new** (o que tem comportamento além de exibir: upload, revisão, anotação, viewer, etc.).
- **Toques de dado** (que entidade cada tela lê/escreve: lawsuit, document, report, e qualquer coisa NOVA — ex.: uma revisão, um comentário).
- **Tokens visuais divergentes** (paleta/fontes próprias do protótipo vs o design system do projeto — sinal de decisão de tema pendente).

### 0.2 Escanear a fundação de engenharia

Siga o roteiro de [references/foundation-scan.md](references/foundation-scan.md). Em resumo, leia: `CLAUDE.md`, o índice de ADRs, `openapi.json` (endpoints já existentes), o schema Prisma (tabelas/enums), as libs de UI/design system, e o modelo de auth/RBAC (roles, scopes, RLS). Produza um **mapa reuso-vs-net-new**:

| Capacidade do protótipo | Já existe? (onde) | Veredito |
|---|---|---|
| ex.: upload de documentos | sim — `POST /lawsuits/:id/documents` | reuso |
| ex.: revisão com comentários | não | **net-new (BE + tabela)** |

Apresente esse mapa ao usuário. Ele evita a frota reconstruir o que já está pronto e expõe o miolo net-new (que costuma ser a parte arriscada e pequena).

---

## Fase 1 — Trava-decisões (BLOQUEANTE)

Antes de qualquer spec, identifique as **decisões transversais** que, se não travadas agora, serão re-litigadas no meio da frota. Use o catálogo de [references/decision-gates.md](references/decision-gates.md) para varrer as categorias e surface **só as que se aplicam** a este protótipo (não force as cinco se só três cabem).

Categorias típicas (derive do gap Fase 0, não hardcode):
- **Papel/role & permissão** — reusa role existente ou cria nova? Quais scopes? O que esconder?
- **Fronteira de app** — rotas role-gated no app existente, ou app/deploy separado?
- **Tema/design system** — o protótipo divergiu do DS? Reconcilia, vira segundo tema na lib, ou é app à parte?
- **Dado-como-sinal** — alguma entidade nova alimenta um mecanismo existente (gate de qualidade, billing, datalake)? Isso muda contrato e merece ADR.
- **Escopo de tenant/ownership** — "meus" itens = do tenant inteiro ou atribuídos ao usuário?

Faça as perguntas via `AskUserQuestion` (uma rodada, objetiva, com recomendação na 1ª opção). **Não prossiga** sem as respostas. Registre as decisões travadas (viram insumo de ADR e da seção "Decisões" do PRD).

---

## Fase 2 — ADRs (só o que é arquitetural)

Para cada decisão travada que passa no **teste de altitude** (muda uma fronteira, um contrato, um fluxo de dados, uma postura de segurança, ou introduz superfície/role/sinal/dependência nova), escreva um ADR seguindo a convenção real do projeto. Decisões de produto/escopo/cosmética **não viram ADR** — vão só pro PRD.

Use o template e as regras de grounding em [references/adr-prd-templates.md](references/adr-prd-templates.md):
- Numeração: próximo número livre em `master-docs/technical-context/adr/` (cuidado com números reservados, ex.: 028).
- Frontmatter real (`status: Proposed`, `date`, `deciders`, `supersedes`, `implementation_pr`).
- Seções: Context (com `arquivo:linha` reais), Decision, Consequências, Alternativas consideradas.
- **Valide contra ADRs existentes** invocando o agente `master-docs-gate-keeper` (mesmo passo que `product:spec` faz) — pega conflito com decisão prévia.

Apresente os ADRs para aprovação antes de seguir.

---

## Fase 3 — PRD focado

Gere o PRD orquestrando o fluxo de `product:spec`, passando como contexto: **o protótipo** (fonte de verdade visual), **os ADRs** (Fase 2), e **o mapa reuso-vs-net-new** (Fase 0). Right-size: feature spec, não epic.

O PRD precisa cobrir, no mínimo (detalhe em [references/adr-prd-templates.md](references/adr-prd-templates.md)):
- Problema, persona, objetivo (1 parágrafo cada — o protótipo já mostra o "o quê").
- **Decisões travadas** (Fase 1) como seção explícita.
- **Escopo: reuso vs net-new** (a tabela da Fase 0) — deixa claro o que NÃO se reconstrói.
- **Modelo de dados** das entidades novas (tabela, colunas, RLS, como se relaciona com o existente).
- **Contrato de API** novo/alterado (endpoints, request/response) — o que o gate `openapi.json`/`api.gen.ts` vai precisar.
- **NFRs:** multi-tenant/RLS, acessibilidade, e **validação em modo real** como requisito.
- Referência ao protótipo por caminho commitado.

Rode a validação de `product:spec` contra master-docs (master-docs-gate-keeper). Itere até sign-off.

---

## Fase 4 — Plano no Linear (decomposição correta)

Orquestre o fluxo de `product:task`, mas imponha a **decomposição por camada** e o **sequenciamento contract-first**. Regras completas (labels, ids do projeto, template de issue, ondas) em [references/layered-linear-plan.md](references/layered-linear-plan.md).

**Camadas (ordem de dependência):**
1. **Decisões/ADR** — se ainda não mergeados, viram a primeira issue (doc-only).
2. **BE + contrato** — schema/migration + endpoints + regenera `openapi.json`/`api.gen.ts`. **Aterrissa primeiro.**
3. **RBAC/segurança** — role-gating, guards, isolamento de tenant (teste de RLS).
4. **FE** — consome o contrato **real** gerado em (2). Mock-first permitido, mas o gate é modo real.
5. **e2e real** — Playwright contra a stack seedada (`VITE_USE_MOCKS=false`).

**Sequência em 2 ondas, não tudo paralelo no t0:**
- **Onda 1 (contract-first):** ADR + BE + contrato + role model. Trava o contrato que o FE vai consumir.
- **Onda 2 (FE larga):** telas consumindo `api.gen.ts` real + e2e.

Cada issue carrega: labels (`type:*`, `area:*`, `int:*`), critérios de aceitação referenciando **PRD + ADR + protótipo**, dependências explícitas, e os **ACs anti-drift** (contrato verde, RLS isola tenant, validado em modo real). Apresente o plano (árvore de issues + grafo de dependência + ondas) para confirmação antes de criar no Linear.

---

## Fase 5 — Handoff para a frota

Encerre entregando:
- **Artefatos:** caminhos do PRD e dos ADRs, IDs das issues criadas.
- **Plano de ondas** com a ordem contract-first explícita.
- **Próximo comando sugerido:** `/engineer:fleet` (ou a `fleet-orchestration-skill`) começando pela Onda 1.
- Lembrete dos gates locais antes de cada PR: `pnpm contract:check`, `./scripts/check-migration-rls.sh`, e validação em modo real.

Se `.claude/memory/` existir, registre a sessão e a decisão de processo (formato em [references/layered-linear-plan.md](references/layered-linear-plan.md)).

---

## Guardrails anti-drift (o que essa skill existe para evitar)

- **Contract-first ou drift.** FE paralelo ao BE que define seu contrato = drift garantido (visto em producao). Onda 1 trava o contrato; Onda 2 consome.
- **Modo real é gate.** Mock-first valida velocidade, não verdade. AC de FE inclui `VITE_USE_MOCKS=false`.
- **Reuso antes de net-new.** A tabela Fase 0 impede a frota reconstruir upload/processamento/preview que já existem.
- **Decisão travada antes da spec.** Trava-decisões bloqueia; sem ele a frota re-litiga e diverge.
- **ADR/PRD ancorados em `arquivo:linha`.** Grounding real, não fundação inventada.
- **Right-size.** Feature spec + ADR pontual, não epic PRD para uma feature de UI.

## Anti-Patterns (NÃO fazer)

- Gerar PRD/ADR sem ler a fundação (ADRs, openapi, schema) — produz plano desalinhado.
- Reimplementar `product:spec`/`product:task` em vez de orquestrá-los.
- Pular o trava-decisões e deixar role/fronteira/tema "pra resolver na frota".
- Criar ADR para decisão cosmética/de escopo (poluição), ou pular ADR para decisão que muda contrato/segurança.
- Decompor FE-cêntrico ("implementar a rota e a interface") sem a camada BE+contrato primeiro.
- Criar issues paralelas sem dependências, mandando BE e FE juntos no t0.
- Referenciar um protótipo untracked (sem commit) nas issues.
- Declarar o plano pronto sem sign-off do usuário em cada fase (decisões, ADR, PRD, Linear).

## Referências

- **Roteiro de leitura da fundação**: [references/foundation-scan.md](references/foundation-scan.md)
- **Catálogo de decisões transversais**: [references/decision-gates.md](references/decision-gates.md)
- **Templates de ADR e PRD + regras de grounding**: [references/adr-prd-templates.md](references/adr-prd-templates.md)
- **Decomposição por camada + plano de ondas no Linear**: [references/layered-linear-plan.md](references/layered-linear-plan.md)
