# Feature Interview — Roteiro para `/ux-flow prototype <feature-slug>`

Roteiro de entrevista para coletar requisitos visuais antes de gerar um prototipo de feature. Conduzida inline no chat durante o Modo B da skill, apos confirmar que o design system canonico existe.

## Regras gerais

- **Inline no chat** — evitar arquivos de perguntas
- **Max 8-10 minutos** — feature prototipo, nao PRD completo
- **Pular perguntas ja respondidas** — se o usuario ja descreveu a feature (ex: durante `/engineer:start`), nao repetir
- **Ler contexto existente** — sempre verificar se existe `.claude/sessions/<feature-slug>/context.md` ou `architecture.md`; se existir, usar como base e pular perguntas que o documento ja responde
- **Ancorar em superficies** — foco nao e arquitetura, e **quais telas preciso desenhar e quais estados cada uma mostra**

## Passo 0: Ler contexto existente (antes das perguntas)

**Obrigatorio.** Antes de abrir a boca, varra o projeto procurando contexto ja documentado sobre esta feature. Perguntar o que ja esta escrito frustra o usuario.

### Fontes a verificar (em ordem de prioridade)

1. **Sessao de engenharia ativa**
   ```
   .claude/sessions/<feature-slug>/context.md
   .claude/sessions/<feature-slug>/architecture.md
   .claude/sessions/<feature-slug>/plan.md
   ```
   Se existir, e a fonte de verdade mais rica. Leia `context.md` na integra — tem meta, estrategia, anti-escopo, criterios de aceitacao. Leia `architecture.md` para extrair superficies (lista de arquivos a criar/modificar = lista de componentes = lista de telas).

2. **Feature spec de negocio**
   ```
   docs/business/features/**/feature-<feature-slug>.md
   docs/business/features/<feature-slug>.md
   docs/business/features/sprint-*/feature-*.md
   ```
   Especificacoes de produto. Tem as "user stories", criterios de aceitacao em linguagem de negocio, cenarios. Frequentemente mencionam estados e edge cases.

3. **GitHub issues relacionadas**
   Se o projeto usa GitHub Issues e voce tem acesso ao mcp tool, busque pelo numero da issue (o `feature-slug` as vezes tem o numero, ex: `issues-167-168-*`). Issue body tipicamente tem:
   - Descricao do escopo
   - Arquivos afetados (lista de superficies)
   - Criterios de aceitacao (mapeiam para estados a cobrir)
   - Pontos de atencao (edge cases)

   Se projeto usa Linear, usar `mcp__linear-server__*` de forma equivalente.

4. **PRDs ou docs de produto**
   ```
   docs/prd/
   docs/business/**/*.md (outros alem de features/)
   ```

5. **Issues pai / epicos**
   Se a feature tem issue pai (ex: #167 descende de #162), ler a issue pai para ver o contexto maior.

### Como extrair superficies e estados das fontes

Mapeamento heuristico:

| Sinal no doc | Vira no prototipo |
|---|---|
| "Criar componente X" em architecture.md | Uma tela X no prototipo |
| "Arquivos afetados: a.tsx, b.tsx, c.tsx" na issue | Tres telas candidatas (uma por arquivo visual) |
| Lista de criterios de aceitacao | Cada criterio pode virar uma variante/estado |
| "Quando [condicao], deve [resultado]" | Estado a cobrir |
| "Se falha X" | Estado de erro |
| "Enquanto carrega" | Estado loading |
| "Se vazio" | Empty state |
| Anti-escopo explicito | Nao representar no prototipo |

### Apresentar pre-preenchimento

Apos ler, apresente ao usuario um resumo e pergunte so o que falta:

> "Li os docs da feature. Ja sei:
>
> **Objetivo:** [extraido]
> **Superficies que preciso prototipar:** [lista baseada em architecture.md / issue body]
> **Estados-chave por tela:**
> - Tela 1: populado / vazio / loading / [outros extraidos dos criterios]
> - Tela 2: ...
> **Anti-escopo:** [extraido]
> **Mock realista do que:** [se relevante, ex: 'PDF de laudo medico']
>
> Confirma? Quer adicionar/remover alguma tela ou estado, ou ja posso montar o prototipo?"

Se o usuario confirmar, **pule direto para Passo 2 (planejamento da arvore de arquivos)**. Nao faca as perguntas Q1-Q7.

Se algum aspecto critico nao foi respondido pelos docs, faca **apenas** essas perguntas especificas — nao rode o roteiro completo.

## Passo 1: Perguntas

### Q1. Problema (so se nao ha context.md)

> "Rapida: **qual problema da feature?** Em uma frase — o que o usuario nao consegue fazer hoje?"

### Q2. Superficies / telas (sempre)

> "Quais **telas ou paineis** essa feature envolve? Liste os nomes como voce os chamaria naturalmente (ex: 'card de documentos no perfil', 'dialog de upload', 'detail sheet')."

**Acao:** extrair N superficies. Cada uma vira um arquivo HTML no prototipo.

### Q3. Estados por tela (sempre)

Para cada superficie listada em Q2, perguntar:

> "Para **[nome da superficie]** — quais estados visuais voce quer cobrir? Eu sempre cubro os basicos: **populado** (caso feliz), **vazio** (empty state), **carregando** (skeleton). Tem mais algum especifico? Ex: erro, edge case, variante por feature flag, permissao, responsabilidade?"

**Acao:** montar lista `[superficie][estados]` que define quantas variantes cada arquivo tera.

**Default se skip:** populado + vazio + carregando.

### Q4. Interacoes-chave (sempre)

> "Tem **interacoes visuais** importantes que o prototipo precisa deixar claro? Ex: drag-and-drop, multi-select, multi-step flow, abertura de modal/sheet, animacao critica. Nao precisa funcionar — so preciso representar visualmente."

**Acao:** lista de interacoes vira notas nos arquivos gerados (ex: "Estado: arrastando" no drop zone).

### Q5. Referencias externas (as vezes)

> "Alguma **referencia** de outro app que faz isso bem? Linear, Notion, Figma, Stripe, Apple, concorrente direto. Quanto mais especifico ('o dialog de upload do GitHub', 'os cards do Notion database'), melhor para eu reproduzir o feeling."

**Default se skip:** nao forcar — prototipo usa exclusivamente o design system canonico.

### Q6. Mocks realistas (as vezes)

Se a feature envolve preview de dados (PDF, imagem, codigo, grafico, tabela), perguntar:

> "O prototipo vai mostrar preview de **[tipo de dado]**. Posso gerar um mock **realista** (texto plausivel de [exemplo do dominio]) ou um **placeholder neutro** (retangulo generico)? Mock realista deixa a discussao de UX mais produtiva."

**Default:** sempre preferir realista quando o dominio for conhecido (medico, financeiro, tecnico). Placeholder so se o dominio e ambiguo.

### Q7. Anti-escopo (sempre)

> "Ultima — tem algo que voce NAO quer que apareca no prototipo? Features em backlog, decisoes adiadas, complexidade que voce nao quer misturar. Anti-escopo mantem o prototipo focado."

**Acao:** registrar como `proto-note` no final das telas relevantes ("Fora de escopo: X — sera coberto em [issue futura]").

### Q8. Tema (quase sempre pular)

So perguntar se o design system suportar light E dark e a feature tiver requisito explicito. Na maioria dos casos, use o tema primario do design system sem perguntar.

### Q9. Acessibilidade / responsividade (raro)

Pular por padrao. So perguntar se:
- O projeto tem requisito A11Y formal (WCAG AA/AAA)
- A feature e primariamente mobile
- O usuario menciona explicitamente

Nesses casos:
> "A11Y — tem requisito especifico (WCAG AA, contraste minimo, navegacao keyboard-only) que precisa aparecer no prototipo?"

## Passo 2: Planejamento da arvore

Apos as perguntas, propor a arvore de arquivos explicitamente:

> "Baseado nas respostas, vou gerar:
>
> ```
> docs/prototypes/<feature-slug>/
> ├── shared.css                     # @import do design system + extensoes locais
> ├── index.html                     # Hub de navegacao
> ├── <superficie-1>.html            # [N estados] — populated, empty, loading
> ├── <superficie-2>.html            # [M estados] — ...
> └── ...
> ```
>
> Confirma?"

Aguarde "sim" / "ok" / "manda" antes de gerar. Se o usuario pedir mudancas (remover tela, fundir duas, trocar nomes), aplicar e reconfirmar.

## Passo 3: Execucao

Apos aprovacao da arvore, gerar arquivos em sequencia:

1. **`shared.css` do prototipo** primeiro — `@import url('../../design-system/shared.css');` + extensoes especificas da feature no topo do arquivo
2. **Cada tela** com variantes empilhadas separadas por `.proto-variant-header`
3. **`index.html` por ultimo** — agora que sei os arquivos finais gerados

Apos todos gerados, reportar:

> "Gerei N arquivos em `docs/prototypes/<feature-slug>/`. Abrir `index.html` no browser:
> ```bash
> open docs/prototypes/<feature-slug>/index.html
> ```
> Caminha pelas telas e me fala o que achou. Espero sign-off antes de dar a Fase X como concluida."

## Passo 4: Iteracao

Se o usuario pedir ajustes:

- **Mudancas de tokens** (cor, espacamento) → editar em `shared.css` local (nao no canonico) SE for decisao especifica da feature
- **Mudanca de token global** → perguntar: "isso e decisao permanente? Se sim, altero o design system canonico em `docs/design-system/shared.css` tambem"
- **Adicionar variante** → editar o HTML relevante
- **Adicionar tela** → novo arquivo HTML + atualizar `index.html` com mais um card
- **Remover tela** → deletar arquivo + remover do hub

Apos cada iteracao, perguntar "melhorou?" ou "aprovado?". Sign-off explicito e obrigatorio.

## Quando chamar esta entrevista automaticamente

Esta skill pode ser invocada automaticamente em contextos onde claramente ha necessidade de UX novo:

- `/engineer:start` com feature envolvendo novas telas
- `/engineer:plan` quando o plano gerado teria "prototipar" como fase
- Usuario pede "quero ver antes de implementar"
- Usuario pede "mockup" ou "wireframe"

Nesses casos, primeiro verificar se `docs/design-system/` existe. Se nao, rodar `init` antes.
