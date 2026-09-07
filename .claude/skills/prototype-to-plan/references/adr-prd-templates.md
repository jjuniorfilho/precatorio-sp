> Carregado nas Fases 2 e 3 da skill `prototype-to-plan`, quando é preciso escrever ADRs e o PRD respeitando a convenção real do projeto. Templates + regras de grounding em código real (arquivo:linha).

# Templates de ADR e PRD + grounding

## Regra de grounding (vale para ADR e PRD)

Ancore afirmações sobre a fundação em **código que existe**, citando `arquivo:linha`. Exemplos:
- "o roteamento vive em `libs/ai-agents/src/pipelines/trabalhista/s3-document-path.ts:23-35`".
- "RLS por tenant via `executeWithTenant` (`libs/database/src/index.ts`)".

Nunca descreva uma capacidade como "a construir" se ela já existe (vira reuso), nem como "existe" se você não a encontrou no código. Em dúvida, leia o arquivo antes de afirmar.

## Teste de altitude: vira ADR?

Escreva ADR **somente** se a decisão muda pelo menos um destes:
- uma **fronteira** (app, módulo, boundary de scope Nx),
- um **contrato** (API pública, evento, schema de dados),
- um **fluxo de dados** (quem produz/consome o quê),
- uma **postura de segurança** (role, scope, RLS, isolamento),
- introduz **superfície/role/sinal/dependência** nova.

Decisão de produto, escopo, cópia, ou cosmética → **só PRD**, nunca ADR.

## Template de ADR (convenção px-agents)

Caminho: `master-docs/technical-context/adr/NNN-titulo-kebab.md` (próximo número livre; cuidado com reservados).

```markdown
---
status: Proposed
date: YYYY-MM-DD
deciders: [Rafael Fiales]
supersedes: []
superseded_by: null
implementation_pr: "PX-XXXX"
---

# ADR-NNN: <título da decisão, afirmativo>

## Context

<O estado atual do mundo, ancorado em arquivo:linha. O que existe hoje, qual o gap,
qual precedente já no repo. Seja concreto: cite os arquivos e o comportamento real.>

## Decision

<A decisão, em itens numerados se houver mais de uma cláusula. Deixe claro o que é
default não-negociável e o que é opt-in. Se a decisão preserva um gate existente
(ex.: contrato, RLS, shadow), diga explicitamente.>

## Consequências

- **Positivas:** <...>
- **Negativas / custo:** <...>
- **Neutras:** <...>

## Alternativas consideradas

- **<Alternativa A>** — <por que foi descartada>
- **<Alternativa B>** — <por que foi descartada>

## Open Questions

- <o que fica para uma issue separada / decisão futura>
```

Após escrever, **valide contra os ADRs existentes** invocando o agente `master-docs-gate-keeper` (mesmo passo do `product:spec`): ele pega conflito com decisão prévia. Trate inconsistências antes de seguir.

## Outline do PRD focado

O PRD é uma **feature spec**, não um epic. Reuse os elementos do `product:spec`, mas right-sized. Local sugerido: a própria issue-pai no Linear, ou `docs/specs/<feature>.md` se o projeto usar arquivos.

```markdown
# PRD — <Feature>

## 1. Problema & oportunidade
<1 parágrafo. O protótipo já mostra o "o quê"; aqui o "por quê".>

## 2. Persona & objetivo
<Quem usa, em que contexto, qual o job-to-be-done. 1 parágrafo.>

## 3. Decisões travadas
<Cole o bloco da Fase 1 (decision-gates). Link para os ADRs gerados.>

## 4. Escopo: reuso vs net-new
<Cole a tabela da Fase 0. Deixe explícito o que NÃO se reconstrói.>

## 5. Requisitos funcionais
<User stories / fluxos, referenciando as telas do protótipo por nome.>

## 6. Modelo de dados (entidades novas)
<Tabela(s) nova(s): colunas, tipos, FK, RLS (policy ou NO-RLS com precedente),
índices. Como se relaciona com o existente.>

## 7. Contrato de API (novo/alterado)
<Endpoints novos: método, path, request, response. O que o gate
openapi.json/api.gen.ts vai precisar. Marque o que é breaking.>

## 8. Requisitos não-funcionais
- **Multi-tenant / RLS:** isolamento por tenant (teste obrigatório).
- **Acessibilidade:** foco de teclado, reduced-motion, contraste.
- **Validação em modo real:** VITE_USE_MOCKS=false contra API seedada (gate, não opcional).
- **Segurança:** anti-escalação de role/scope, o que a role NÃO pode ver.

## 9. Riscos & mitigação
<Ex.: drift mock-vs-real → mitigado por contract-first + e2e real.>

## 10. Referências
- Protótipo: `<caminho commitado>`
- ADRs: ADR-NNN, ...
```

Rode a validação do `product:spec` contra master-docs (master-docs-gate-keeper) e itere até sign-off. **Menos é mais:** se a feature não precisa de uma seção, pule.
