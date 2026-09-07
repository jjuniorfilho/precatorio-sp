> Carregado na Fase 1 da skill `prototype-to-plan`, quando é preciso identificar e travar as decisões transversais antes da spec. Catálogo de categorias de decisão + como surface cada uma via AskUserQuestion.

# Catálogo de decisões transversais (Fase 1)

Trava-decisões é **bloqueante**: uma decisão re-litigada no meio da frota custa worktrees re-trabalhando. Varra as categorias abaixo e surface **só as que se aplicam** ao protótipo em questão (derive do gap da Fase 0; não force todas).

Como conduzir: uma rodada de `AskUserQuestion`, perguntas objetivas, com **recomendação na 1ª opção** marcada `(Recomendado)` quando houver um default sensato pela fundação. Não prossiga sem resposta. Registre cada decisão travada (vira insumo de ADR e da seção "Decisões" do PRD).

## Teste rápido: é decisão transversal?

Surface como gate se a resposta muda **mais de uma camada** ou trava um contrato/segurança. Se afeta só uma tela ou é cosmética, vai pro PRD como detalhe, não vira gate.

## Categorias

### 1. Papel / role & permissão
Quando o protótipo é para um perfil de usuário diferente do atual.
- Reusa uma role existente (ex.: `TENANT_USER`) ou cria uma nova (ex.: `ANALYST`)?
- Quais scopes a role enxerga? O que precisa ser **escondido** (admin, prompts, infra, billing)?
- Impacto: define o role-gating inteiro (rotas, guards, navegação). **Geralmente vira ADR.**

### 2. Fronteira de app
Onde a nova superfície vive.
- Rotas role-gated dentro do app existente, ou app/deploy separado?
- Trade-off: reuso de chrome/DS/auth vs separação de concerns e blast radius.
- Impacto: estrutura de build, deploy, navegação. **Vira ADR se for app separado.**

### 3. Tema / design system
Quando o protótipo divergiu do DS do projeto (paleta/fontes próprias).
- Reconcilia com o DS existente, vira **segundo tema** na lib de UI, ou é app à parte com tema próprio?
- Impacto: onde os tokens vivem, reuso de `@px-agents/ui`. Geralmente PRD + nota de ADR de fronteira.

### 4. Dado-como-sinal (o gate mais importante de não esquecer)
Quando uma entidade nova alimenta um **mecanismo existente**.
- Ex.: uma "revisão humana" que alimenta o gate de qualidade/promoção, o billing, ou o datalake.
- Pergunte: esse dado é consumido por quem, como, e isso muda o contrato/fluxo de um sistema que já existe?
- Impacto: muda contrato e fluxo de dados → **quase sempre vira ADR** (é conceitualmente novo, mesmo que a tabela seja simples).

### 5. Escopo de tenant / ownership
O significado de "meus" itens.
- "Meus processos" = todos do tenant, ou só os atribuídos ao usuário?
- Há conceito de atribuição/dono? Em v1 normalmente = tenant inteiro (RLS já isola), mas confirme.
- Impacto: query scoping, talvez coluna de ownership. PRD; vira gate se exigir modelo de atribuição novo.

### 6. Profundidade de v1 (anti-escopo)
O que **fica de fora** da primeira entrega.
- Liste o que o protótipo mostra mas não entra em v1 (ex.: edição inline, export, notificações).
- Impacto: tamanho da frota. Não é ADR, mas trava expectativa e evita scope creep.

## Formato de registro (após travar)

```markdown
## Decisões travadas — <feature> (YYYY-MM-DD)
- **Papel/role:** <decisão> — <justificativa> — [ADR? sim/não]
- **Fronteira de app:** <decisão> — <justificativa> — [ADR? sim/não]
- **Tema:** <decisão> — <justificativa>
- **Dado-como-sinal:** <decisão> — <justificativa> — [ADR? sim/não]
- **Escopo de tenant:** <decisão>
- **Anti-escopo v1:** <lista do que fica de fora>
```

Esse bloco é copiado verbatim para a seção "Decisões" do PRD e abre os ADRs aplicáveis.
