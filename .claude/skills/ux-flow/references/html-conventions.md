# HTML Conventions — Convencoes para prototipos gerados por `/ux-flow prototype`

Regras de formato para os arquivos HTML que a skill gera. Segue-as literalmente para garantir que o output seja reutilizavel como referencia visual durante a implementacao React/Swift/Flutter posterior.

## Principio fundamental

> **O prototipo e um artefato committado no repo, nao um throwaway.** Ele e lido durante code review do PR que implementa a feature. Nomes de classes, estrutura de DOM e componentes devem ser pensados para facilitar a traducao em codigo real.

## Estrutura de arquivos

```
docs/prototypes/<feature-slug>/
├── shared.css          # @import do DS + extensoes locais
├── index.html          # Hub de navegacao
├── <tela-1>.html       # Tela 1 com todas as variantes empilhadas
├── <tela-2>.html       # Tela 2 com todas as variantes empilhadas
└── ...
```

Nada alem disso. Sem `js/`, sem `images/`, sem `dist/`, sem `node_modules/`.

## `shared.css` local

**Sempre** comeca com:

```css
/* =============================================================================
   <Feature Name> — Prototype CSS extensions
   Estende docs/design-system/shared.css com componentes especificos desta feature.
   ============================================================================= */

@import url('../../design-system/shared.css');

/* -----------------------------------------------------------------------------
   Protótipo shell — regras que so existem no protótipo (hero, hub, back button)
   ----------------------------------------------------------------------------- */
/* ... */

/* -----------------------------------------------------------------------------
   Feature-specific components
   ----------------------------------------------------------------------------- */
/* ... */
```

- **Nunca** copiar tokens do design system canonico. Sempre `@import`.
- Agrupar extensoes por bloco com comentarios de secao.
- Nomes de classes usar kebab-case, prefixo opcional pelo nome da feature (ex: `.doc-item`, `.upload-item`, `.sheet`).
- **Nunca** usar `!important`.
- **Nunca** usar cores hardcoded — usar `var(--primary)`, `var(--foreground)`, etc. Se precisar de cor nova, extender paleta via `hsla(hue, sat, light, alpha)` usando os hue/sat dos tokens existentes.

## `index.html` (hub)

Padrao visual:

- Hero no topo com eyebrow (`Issue #N` ou `Feature: X`), titulo, subtitulo
- Status row (alerta azul) com fase atual (ex: "Fase 0 · Prototipacao HTML antes do codigo")
- Nav grid com 1-4 cards, cada um correspondendo a uma tela
- Cada card tem: icone colorido, tag (issue/categoria), titulo, descricao (1 linha), variant pills (contagem de estados), meta row (path do arquivo)
- Footer com notas de uso

Inline SVG lucide para icones. Zero JS.

## Telas (arquivos individuais)

Estrutura:

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Aura V2 — <Nome da Tela> · #<Issue></title>
  <link rel="stylesheet" href="shared.css" />
</head>
<body class="proto-body">
  <div class="proto-container">

    <!-- Hero com botao Voltar -->
    <div class="proto-hero">
      <div>
        <div class="proto-hero-eyebrow">Issue #N · <contexto></div>
        <div class="proto-hero-title"><Titulo></div>
        <div class="proto-hero-subtitle"><descricao curta></div>
      </div>
      <a href="index.html" class="proto-back">
        <svg><!-- chevron-left lucide --></svg>
        Voltar ao hub
      </a>
    </div>

    <!-- Variante 1 -->
    <div class="proto-variant-header">
      <div class="proto-variant-label">Variante 1</div>
      <div class="proto-variant-title"><Nome do estado></div>
      <div class="proto-variant-desc"><descricao curta></div>
    </div>
    <!-- HTML da variante 1 -->

    <!-- Variante 2 -->
    <div class="proto-variant-header">
      <!-- ... -->
    </div>
    <!-- HTML da variante 2 -->

    <!-- ... -->

    <div style="height: 48px;"></div>
  </div>
</body>
</html>
```

Regras:

- **Sempre** `lang="pt-BR"` se o projeto for em portugues
- **Sempre** `<meta charset="UTF-8">`
- **Sempre** botao "Voltar ao hub" no canto superior direito
- Variantes empilhadas verticalmente com `.proto-variant-header` separando — nao usar tabs com JS
- Cada `.proto-variant-header` tem: label ("Variante N"), titulo, descricao
- Footer com `<div style="height: 48px;"></div>` para dar respiro no scroll
- Max ~500 linhas por arquivo — se exceder, considere quebrar em mais telas

## Icones

Use **inline SVG estilo lucide**. Formato padrao:

```html
<svg width="18" height="18" viewBox="0 0 24 24"
     fill="none" stroke="currentColor"
     stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
  <path d="..." />
</svg>
```

- `stroke="currentColor"` para herdar cor do contexto
- `width`/`height` variando por contexto: 14 (small), 18 (medium), 22 (hero)
- Nunca usar emojis para icones funcionais (ok para decorativo como titulo de secao: `📊`, `🎨`)
- Nunca usar font-icons (FontAwesome, etc)

Icones comuns e seus paths (copie de [lucide.dev](https://lucide.dev)):
- `x` — fechar
- `check` — sucesso
- `chevron-left/right` — navegacao
- `file-text` — documento
- `image` — imagem
- `sparkles` — IA
- `paperclip` — anexo
- `upload` — upload
- `download` — download
- `trash-2` — excluir
- `edit-3` — editar
- `loader-2` — spinner (aplicar classe `.animate-spin`)
- `alert-triangle` — warning
- `info` — info
- `users` — pessoas

## JavaScript

**Zero JavaScript executavel** na regra geral. Excecoes aceitaveis:

- **Nenhuma.** Se voce achou que precisava de JS, esta usando o ferramenta errada. Toggles entre estados = variantes empilhadas. Animacoes = CSS `@keyframes`. Navegacao entre telas = `<a href="outra.html">`.

Se o usuario explicitamente pedir interatividade real (ex: testar um fluxo step-by-step), ai sim pode adicionar JS minimo — mas tipicamente esse caso e melhor resolvido fazendo o proprio desktop app com uma tela fake do que HTML.

## Assets binarios

**Zero assets binarios.** Regras:

- **Imagens** — substituir por `.img-preview` CSS (retangulo com gradiente + label mock)
- **PDFs** — substituir por `.pdf-preview` HTML estilizado com texto mock realista
- **Video** — substituir por `.video-preview` CSS + label
- **Icones** — inline SVG
- **Fontes** — via Google Fonts CDN (herdado do design system)

O unico "asset externo" tolerado e o Google Fonts do `shared.css` canonico — e justamente o que nao podemos embutir facilmente.

## Mocks realistas

Quando o prototipo mostra preview de dados, sempre use conteudo **plausivel do dominio**, nunca lorem ipsum.

Exemplos:
- **App medico** — mock de PDF e laudo de exame real (TSH 6.82, T4 0.89, etc)
- **App financeiro** — mock de fatura com linhas de transacao realistas
- **App de devtools** — mock de codigo com linguagem e patterns reais
- **App de CRM** — leads com nomes brasileiros plausiveis, empresas conhecidas
- **Dashboard de analytics** — numeros realistas (MRR, churn, etc)

**Justificativa:** placeholder generico faz o usuario perder tempo mentalmente abstraindo "se fosse dados reais seria..." — mock realista permite discussao imediata de UX.

## Acessibilidade minima

Mesmo em prototipo, seguir basico:

- `lang` no `<html>`
- `alt` em imagens (nao se aplica pois nao ha imagens, mas se houver)
- `aria-label` em botoes icon-only
- Contraste suficiente (herdado do design system — confiar nos tokens)
- Foco visivel em interativos (herdado do design system)

Nao precisa ser WCAG compliant — prototipo e para discussao visual, nao auditoria.

## Naming alinhado ao React

Quando criar classes CSS, pense em como o React component vai se chamar:

| Classe CSS | Futuro componente React |
|---|---|
| `.doc-item` | `<DocumentItem>` |
| `.doc-list` | `<DocumentList>` |
| `.upload-zone` | `<UploadZone>` |
| `.drop-zone` | `<DropZone>` |
| `.sheet` | `<Sheet>` (shadcn) |
| `.ai-badge` | `<AIBadge>` |
| `.empty-state` | `<EmptyState>` |
| `.cat-badge.lab-exam` | `<CategoryBadge category="lab-exam" />` |

Regra pratica: cada bloco visual recorrente merece uma classe nomeada. Nao usar nomes genericos como `.box`, `.wrapper`, `.container-1`.

## Limite de tamanho

- `SKILL.md` desta skill: manter < 500 linhas (recomendacao oficial da Anthropic)
- `shared.css` local de um prototipo: nao ha limite rigido, mas se passar de 1500 linhas considere se muitas coisas deveriam estar no design system canonico
- HTML de uma tela: manter < 500 linhas idealmente; se muito maior, pode indicar que ha variantes demais e vale quebrar

## Checklist final antes de declarar prototipo pronto

Antes de entregar para sign-off:

- [ ] `index.html` abre no browser sem erros de console
- [ ] Todas as telas linkadas no hub existem
- [ ] Todas as telas tem botao "Voltar ao hub" funcional
- [ ] `shared.css` tem `@import` do design system canonico (nao duplica tokens)
- [ ] Zero `<script>` executavel
- [ ] Zero assets binarios
- [ ] Zero `!important`
- [ ] Zero cores hardcoded fora de `var(--foo)`
- [ ] Meta charset UTF-8 em todos os HTMLs
- [ ] `lang="pt-BR"` em todos os HTMLs (ou idioma do projeto)
- [ ] Pelo menos estado **populado + vazio + loading** em cada tela
- [ ] Mocks realistas (nao lorem ipsum) quando aplicavel
- [ ] Naming de classes pensando em futuro component React

Se algum item falhar, corrija antes do sign-off.
