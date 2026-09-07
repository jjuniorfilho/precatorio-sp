---
name: ux-flow
description: UX-first workflow para criar design system HTML e prototipos visuais navegaveis antes de escrever codigo real. Use quando o usuario quer desenhar uma feature nova, validar UX/UI com protótipo HTML, estabelecer branding/design system do projeto, ou pedir "prototipa essa tela antes de implementar". Conduz entrevista, detecta design system existente, gera protótipos reutilizáveis.
argument-hint: [init | prototype <feature-slug>]
---

# UX Flow — Design System + Prototipagem HTML

Workflow de design e UX antes de implementar codigo real. Detecta ou cria um design system HTML do projeto, conduz entrevistas com o usuario, e gera prototipos navegaveis que servem de referencia visual para a implementacao posterior.

**Filosofia:** separar **decisoes visuais** (rapidas, iterativas, em HTML estatico) da **implementacao de codigo** (lenta, cara). Prototipo bom = menos retrabalho no React/Swift/Flutter depois.

## Direcao de design (plugin `frontend-design`) — o gosto, nao so o processo

Esta skill garante o **processo** (descoberta, entrevista, prototipo, sign-off). A **qualidade estetica** (paleta, tipografia, layout, elemento-assinatura que nao parece template) vem da skill **`frontend-design`** do plugin oficial da Anthropic (`claude-plugins-official`), quando instalada. As duas sao complementares: `ux-flow` da a esteira, `frontend-design` da a direcao de arte.

**Regra:** antes de gerar QUALQUER CSS/token novo (Modo A Passo 4) ou tela de prototipo (Modo B Passo 5), consulte a `frontend-design` como diretor de arte. Se o plugin nao estiver instalado, siga os principios abaixo manualmente (sao o destilado dela) e avise ao usuario que instalar `frontend-design` eleva o resultado.

Principios que a `frontend-design` impoe (aplicar mesmo sem o plugin):
- **Ancorar no assunto.** Palette/type/layout derivam do produto e da audiencia concretos (dos business docs + entrevista), nao de um default generico.
- **Fugir do "cara de IA".** Evitar os 3 clusters batidos: (1) fundo creme + serifada alto-contraste + terracota; (2) fundo quase-preto + um verde-acido/vermelhao; (3) layout jornal com hairlines e zero border-radius. So usar se o brief pedir explicitamente.
- **Tipografia carrega personalidade.** Parear display + corpo com intencao, escala de tipos e pesos deliberados. Nao usar a mesma familia que se usaria em qualquer projeto.
- **Estrutura e informacao.** Numeracao (01/02/03), eyebrows, dividers so quando codificam algo verdadeiro (uma sequencia real), nunca como decoracao.
- **Gaste a ousadia em um lugar so.** Um elemento-assinatura memoravel; o resto quieto e disciplinado. Quality floor sem alarde: responsivo, foco de teclado visivel, `prefers-reduced-motion` respeitado.
- **Dois passos: planejar tokens -> autocritica -> so entao codar.** Antes de escrever o `shared.css`, esboce o sistema de tokens (4-6 cores nomeadas, 2+ tipografias com papeis, conceito de layout, assinatura) e critique contra o brief: se qualquer parte parece o default que voce faria para qualquer pagina similar, revise e diga o que mudou e por que.

Copy tambem e design: nomear pelo que o usuario controla (nao pelo sistema), voz ativa, o mesmo termo do inicio ao fim do fluxo, erro/vazio como direcao (nao humor).

## Quando invocar

- Usuario pede "prototipa essa tela", "quero ver a UX antes de implementar", "cria um mockup"
- Feature nova com superficies visuais sem precedente no projeto
- Inicio de projeto sem design system estabelecido
- Necessidade de validar branding/paleta antes de gerar componentes
- Durante `/engineer:plan`, quando o plano precisa de fase UX anterior ao codigo

## Modos

Esta skill opera em dois modos. O usuario escolhe via argumento:

- **`/ux-flow init`** — descobre ou cria o design system do projeto (primeira vez)
- **`/ux-flow prototype <feature-slug>`** — cria um prototipo de feature usando o design system existente
- **`/ux-flow`** (sem argumento) — detecta automaticamente se o design system existe e oferece o modo apropriado

## MODO A — `init` (Design System Discovery + Creation)

### Passo 1: Descoberta

Antes de propor criar qualquer coisa, **varra o projeto** procurando design system ja existente. Nao recrie o que ja existe.

Locais a verificar (em ordem):

1. `docs/design-system/shared.css` — padrao canonico desta skill
2. `docs/prototypes/*/shared.css` — design system inline em pasta de prototipo (caso aura_v2/ui-overhaul)
3. `docs/branding/` — branding guides existentes
4. `packages/ui/` ou `libs/shared/ui/` — biblioteca de componentes com tokens
5. `apps/*/src/components/ui/` — shadcn/ui ou similar (extrair tokens via `globals.css`, `theme.css`)
6. `tailwind.config.{ts,js}` — tokens em formato Tailwind
7. `*.figma.tokens.json` — tokens exportados do Figma Tokens Studio

Para heuristicas detalhadas de deteccao, veja [references/design-system-discovery.md](references/design-system-discovery.md).

### Passo 2: Diagnostico

Apos a varredura, reporte ao usuario um dos tres cenarios:

**Cenario 1 — Design system canonico existe** (`docs/design-system/shared.css`)
> "Ja existe um design system em `docs/design-system/shared.css` e `branding-guide.md`. Posso usar como fonte de verdade para proximos prototipos sem mudancas, ou voce quer revisar/evoluir o guide antes?"

**Cenario 2 — Existe algo proximo mas nao canonico** (ex: `docs/prototypes/ui-overhaul/shared.css`, ou `tailwind.config.ts`)
> "Encontrei [caminho]. Quer: (a) promover para `docs/design-system/` como fonte canonica, (b) criar um novo do zero baseado em entrevista, ou (c) manter o atual e apenas criar um `branding-guide.md` que documente as decisoes ja tomadas?"

**Cenario 3 — Nada encontrado**
> "Nenhum design system encontrado. Posso conduzir uma entrevista curta (~10 min) para coletar preferencias de branding/UX e gerar `docs/design-system/shared.css` + `branding-guide.md` + `components.html` (showcase)."

Aguarde decisao do usuario.

### Passo 3: Entrevista de branding (se cenario 2c ou 3)

**Antes** de perguntar qualquer coisa ao usuario, **leia os business docs do projeto** procurando informacao ja respondida. Nao perguntar o que os docs ja respondem — isso frustra o usuario e faz a skill parecer burra.

Arquivos que tipicamente ja contem respostas (varia por projeto):

```
docs/business/PRODUCT_STRATEGY.md      # produto, posicionamento, audiencia
docs/business/VOICE_OF_CUSTOMER.md     # quem e o usuario
docs/business/MESSAGING_FRAMEWORK.md   # tom de voz
docs/business/COMPETITIVE_LANDSCAPE.md # concorrentes = referencias visuais candidatas
docs/business-context/project-briefing.md
README.md
CLAUDE.md
docs/pitch/                            # decks com possivel identidade visual
```

Use `Glob`/`Read` para extrair: nome do produto, tipo (SaaS/mobile/interno), audiencia, industria, tom de voz escrito, concorrentes citados. **Apresente ao usuario um resumo para confirmar** antes de perguntar mais nada.

Apos a confirmacao, conduza apenas as perguntas que **ainda nao estao respondidas**. Use o roteiro completo em [references/branding-interview.md](references/branding-interview.md), que tem o Passo 0 de descoberta obrigatorio. As perguntas-chave sao:

1. **Produto e audiencia** — provavelmente ja respondido pelos business docs
2. **Tom visual** — serio/clinico, playful, minimalist, bold, enterprise (pode ser inferido do tom de voz escrito)
3. **Tema** — light only, dark only, ambos
4. **Cor primaria** — cor exata em HSL/hex, ou referencia externa (Linear, Stripe, Notion, Vercel, Figma)
5. **Tipografia** — Inter (padrao), outra familia
6. **Densidade** — confortavel (Linear-like), compacta (GitHub-like), luxuosa (Apple-like)
7. **Referencias visuais** — links, screenshots, dribbble (se COMPETITIVE_LANDSCAPE existe, usar como pontos de partida)

Conduza a entrevista **inline no chat**. Permita "nao sei, escolhe por mim" em qualquer pergunta — neste caso use defaults sensatos (Inter, light theme, azul #2563eb, densidade confortavel).

### Passo 4: Geracao dos artefatos

**Passo 4.0 (direcao de arte, antes de escrever o CSS):** invoque a skill `frontend-design` (ou aplique os principios da secao "Direcao de design" acima) para produzir o **plano de tokens** ancorado neste produto: 4-6 cores nomeadas, display + corpo + utilitaria com papeis e escala, conceito de layout, e o elemento-assinatura. **Critique o plano contra o brief** (parece default? revise) ANTES de materializar no `shared.css`. So depois preencha os templates abaixo derivando cada cor/tipo desse plano.

Crie a seguinte estrutura:

```
docs/design-system/
├── shared.css              # Tokens CSS + componentes base + utilitarios
├── branding-guide.md       # Decisoes tomadas + paleta + tipografia + justificativas
├── components.html         # Showcase de todos os componentes (abrir no browser)
└── references/             # Screenshots ou links externos das referencias usadas
    └── README.md
```

**Templates a usar:**
- `shared.css` → [assets/shared-css-template.css](assets/shared-css-template.css)
- `branding-guide.md` → [assets/branding-guide-template.md](assets/branding-guide-template.md)
- `components.html` → [assets/components-showcase-template.html](assets/components-showcase-template.html)

**Principios para o `shared.css` gerado:**
- CSS custom properties (`:root { --foo: bar }`) para tokens
- Classes utilitarias presentationais (`.btn`, `.card`, `.badge`, `.input`, `.chip`, etc.)
- Reset minimo, Inter como fonte default (via Google Fonts `@import`)
- Nomes de classes alinhados com a convencao shadcn/ui quando aplicavel (facilita migracao para React depois)
- Sem JavaScript runtime
- Comentarios de secao (`/* === Buttons === */`) para navegacao

### Passo 5: Validacao visual

Abra o `components.html` no browser do usuario (se possivel, via `open` / `xdg-open` / `start`) e peca revisao. Itere sobre feedback visual ate aprovacao explicita. **Nao avance para outro modo sem sign-off.**

Ao concluir, **registre decisao** em `.claude/memory/patterns/decisions.md` (se o diretorio existir) com data, cor primaria escolhida, tipografia e justificativa principal.

## MODO B — `prototype <feature-slug>` (Feature Prototyping)

### Passo 1: Pre-requisito

Verifique se `docs/design-system/shared.css` existe. Se nao existir:
> "Nao ha design system canonico ainda. Rode `/ux-flow init` primeiro para estabelecer um, ou confirme se quer usar um design system alternativo (ex: `docs/prototypes/ui-overhaul/shared.css`)."

Nao prossiga sem design system definido.

### Passo 2: Ler design system

Leia **ambos**:
- `docs/design-system/shared.css` (tokens + componentes)
- `docs/design-system/branding-guide.md` (decisoes + justificativas)

Use como fonte unica de verdade. **Nao invente tokens novos.** Se o design system nao tiver algum componente necessario para a feature, **pergunte** ao usuario se quer adicionar ao `shared.css` canonico (e volta para Modo A evolutivo) ou se quer extender so dentro do prototipo.

### Passo 3: Entrevista sobre a feature

Use o roteiro em [references/feature-interview.md](references/feature-interview.md). Perguntas-chave:

1. **Problema** — qual dor a feature resolve
2. **Usuario-alvo** — quem vai usar, em que contexto
3. **Superficies** — quais telas/paineis/dialogos envolvidos (listar nomes)
4. **Estados por tela** — para cada tela, quais estados (empty, loading, populated, error, edge cases)
5. **Interacoes-chave** — modais, sheets, navegacao, drag-and-drop, multi-step
6. **Referencias** — outros apps que fazem bem (Linear, Notion, Figma, app concorrente)
7. **Escopo visual** — responsividade, acessibilidade, dark mode (ja decidido pelo design system, mas vale confirmar se a feature tem requisitos extras)
8. **Anti-escopo** — o que NAO incluir no prototipo (evita ruido visual)

Conduza inline. Permita "skip" e defaults.

### Passo 4: Planejar a arvore de arquivos

Gere em `docs/prototypes/<feature-slug>/`:

```
docs/prototypes/<feature-slug>/
├── shared.css              # @import do design system canonico + extensoes LOCAIS da feature
├── index.html              # Hub de navegacao
├── <screen-1>.html         # Cada tela cobre multiplas variantes empilhadas
├── <screen-2>.html
└── ...
```

**Regra de ouro:** `shared.css` do prototipo **sempre comeca com** `@import url('../../design-system/shared.css');` (nao copia o conteudo). Isso garante que qualquer evolucao do design system se propague. Extensoes locais ficam abaixo do import, comentadas como `/* === Feature-specific extensions === */`.

Confirme a arvore com o usuario antes de gerar qualquer arquivo.

### Passo 5: Gerar os arquivos

**Antes de gerar as telas:** consulte a skill `frontend-design` (ou a secao "Direcao de design") para decidir a direcao de arte da feature DENTRO do design system canonico — o hero/abertura caracteristica, a hierarquia visual e o elemento-assinatura da feature. O `shared.css` canonico e a fonte de verdade dos tokens; a `frontend-design` guia COMO compor esses tokens em telas que nao parecam template. Nao reinvente paleta/tipografia ja definidas no design system.

Use os templates como ponto de partida:
- Hub `index.html` → [assets/prototype-index-template.html](assets/prototype-index-template.html)
- Tela com variantes → [assets/prototype-screen-template.html](assets/prototype-screen-template.html)

Regras de formato (convencoes detalhadas em [references/html-conventions.md](references/html-conventions.md)):

- **Zero JavaScript executavel.** Toggles de variantes sao headers separadores em sequencia, nao abas com JS.
- **Zero deps runtime.** Sem CDN de libs (exceto Google Fonts herdado do design system).
- **Zero assets binarios.** Icones sao inline SVG estilo lucide. Previews visuais (PDF, imagem) sao mocks CSS/SVG.
- **Mock realista quando possivel.** Ex: se a tela mostra preview de PDF medico, gere texto realista de laudo. Se mostra grafico de metricas, use numeros plausiveis. Placeholder generico polui a discussao de UX.
- **Nomes de classes alinham com futuros nomes de componentes React.** Exemplo: `.document-item` no HTML vira `<DocumentItem>` no React depois. Isso e parte do valor reutilizavel.
- **Todos os estados empilhados na mesma pagina** com headers `.proto-variant-header` entre eles. Facilita scrollar e comparar.
- **Sempre incluir botao "Voltar ao hub"** no canto superior direito de cada tela.
- **Todas as telas listadas no `index.html`** como cards navegaveis com descricao curta, variant pills e meta row (path + contagem de variantes).

### Passo 6: Cobertura de estados

Para cada tela listada, force-se a cobrir no minimo:
- Estado populado (caso feliz com dados plausiveis)
- Estado vazio (empty state com CTA)
- Estado carregando (skeleton)
- Estado de erro (quando aplicavel)

Se a tela tem variantes especificas (feature flag, permissao, tipo de dado), cobrir tambem.

### Passo 7: Validacao visual

Abra o `index.html` no browser do usuario. Caminhe junto por cada tela e estado. Capture feedback. Itere.

**Sign-off bloqueante.** Nao de o prototipo por concluido sem aprovacao explicita ("aprovado", "tamo bom", "pode seguir").

### Passo 8: Reaproveitamento futuro

Ao final, informe ao usuario que o prototipo pode ser:
- Referenciado em `plan.md` de features subsequentes como "visualizacao canonica"
- Usado como spec visual durante code review do PR que implementa a feature
- Evoluido adicionando novas telas incrementalmente (basta rodar `/ux-flow prototype <feature-slug>` novamente e adicionar arquivos)

## Interacao com outros comandos

- **Durante `/engineer:start`**: se a feature envolve UX novo, sugerir rodar `/ux-flow prototype` como Fase 0 do plan antes do codigo
- **Durante `/engineer:plan`**: validar se existe prototipo; se nao, considerar adicionar fase UX
- **Durante `/engineer:work`**: prototipo e referencia visual durante implementacao; nao precisa ser re-gerado

## Memoria persistente

Se `.claude/memory/patterns/decisions.md` existir no projeto, appende entradas quando tomar decisoes de design system relevantes:

```markdown
### YYYY-MM-DD — Design system estabelecido via /ux-flow init
**Contexto**: [projeto tipo X, ausencia de DS previo]
**Decisao**: [cor primaria Y, tipografia Z, densidade W]
**Justificativa**: [baseado em entrevista, referencia mencionada, default sensato]
**Confianca**: alta | media | baixa
```

Nao criar arquivos em `.claude/memory/` se eles nao existirem — respeitar a estrutura do projeto.

## Anti-padroes (NAO fazer)

- Criar design system sem verificar se ja existe
- Inventar tokens de cor no prototipo em vez de usar os do design system
- Gerar HTML com `<script>` complexo para simular interacoes
- Instalar libs (`react-pdf`, `pdfjs-dist`, etc.) — isto e prototipo, nao build
- Usar placeholders genericos ("lorem ipsum") quando mock realista agregaria valor
- Pular a entrevista e assumir preferencias do usuario
- Declarar prototipo "pronto" sem sign-off explicito
- Criar pasta de prototipo com nome ambiguo (use `<feature-slug>` descritivo, nao `test-1`)
- Duplicar tokens entre `shared.css` do prototipo e o canonico — sempre `@import`

## Recursos adicionais

- **Heuristicas de descoberta de DS**: [references/design-system-discovery.md](references/design-system-discovery.md)
- **Roteiro de entrevista de branding**: [references/branding-interview.md](references/branding-interview.md)
- **Roteiro de entrevista de feature**: [references/feature-interview.md](references/feature-interview.md)
- **Convencoes de HTML do prototipo**: [references/html-conventions.md](references/html-conventions.md)
- **Template de shared.css**: [assets/shared-css-template.css](assets/shared-css-template.css)
- **Template de branding-guide.md**: [assets/branding-guide-template.md](assets/branding-guide-template.md)
- **Template de components.html**: [assets/components-showcase-template.html](assets/components-showcase-template.html)
- **Template de prototype index.html**: [assets/prototype-index-template.html](assets/prototype-index-template.html)
- **Template de screen.html**: [assets/prototype-screen-template.html](assets/prototype-screen-template.html)

## Exemplo de referencia

Um exemplo completo desta skill em acao existe em `docs/prototypes/documents-ui-167-168/` (Aura V2, issues #167+#168). Estrutura gerada:
- `shared.css` com `@import` do design system do `ui-overhaul`
- `index.html` hub com 4 cards navegaveis
- 4 telas (`patient-documents-card.html`, `upload-document-dialog.html`, `document-detail-sheet.html`, `consultation-bottom-bar.html`) cobrindo 17 estados/variantes no total
- Mock realista de PDF de laudo hormonal para preview
- Zero JS executavel, zero deps
- Aprovado pelo usuario em sign-off manual

Use como golden path de referencia visual quando em duvida sobre formato.
