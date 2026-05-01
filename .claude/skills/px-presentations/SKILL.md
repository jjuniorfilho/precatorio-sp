---
name: px-presentations
description: "Criacao de apresentacoes profissionais nos padroes visuais PX Ativos Judiciais e AI Frontiers. Use esta skill quando precisar criar apresentacoes (.pptx), incluindo: Tech Reports, propostas comerciais, relatorios de projetos, mentorias, ou qualquer material institucional. A skill aplica automaticamente as cores, tipografia e elementos visuais da identidade selecionada."
---

# PX Presentations

Skill para criacao de apresentacoes profissionais com dois temas disponiveis:

1. **PX Ativos Judiciais** - Design corporativo com Navy + Gold
2. **AI Frontiers** - Design moderno dark com Navy + Cyan (padrao para propostas comerciais, mentorias e materiais AI Frontiers)

---

## Temas Disponíveis

### Tema 1: PX Ativos Judiciais

Veja CSS em `assets/px-custom.css`

```css
--color-primary: #1e3a5f;         /* Azul PX - fundos principais */
--color-secondary: #f0a500;        /* Amarelo/Dourado PX - destaques */
--color-surface: #ffffff;
--color-muted: #f5f7fa;
```

### Tema 2: AI Frontiers (PADRAO PARA PROPOSTAS)

Veja CSS completo em `assets/ai-frontiers.css`

```css
/* Backgrounds escuros */
--af-bg-darkest: #0b1929;          /* Cover e closing slides */
--af-bg-surface: #162338;           /* Cards em dark backgrounds */

/* Primary Navy */
--af-primary: #1e3a5f;              /* Headers, cards navy em light bg */

/* Accent Cyan */
--af-accent: #4fc3f7;               /* Labels, numeros, links, separadores */

/* Secondary Blue */
--af-secondary: #5bbad5;            /* Cards alternados, headers de scope cards */

/* Textos */
--af-text-primary: #ffffff;          /* Texto em dark */
--af-text-secondary: #94a3b8;        /* Subtitulos em dark */
--af-text-dark: #1e293b;            /* Texto em light */
```

---

## Elementos Visuais AI Frontiers

### Logo
- "AI" em cyan italico (#4fc3f7) + "FRONTIERS" em branco bold uppercase
- Posicionado no top-left dos slides dark (cover e closing)

### Circulos Decorativos
- 3 circulos concentricos semi-transparentes no canto superior direito
- Outer: rgba(79, 195, 247, 0.08), 300px
- Middle: rgba(79, 195, 247, 0.12), 220px
- Inner: rgba(79, 195, 247, 0.18), 140px
- Presentes nos slides de cover e closing

### Metric Cards (Light Background)
- Alternancia: 2 cards navy (#1e3a5f) + 2 cards cyan (#5bbad5)
- Numeros grandes brancos, labels brancos uppercase
- Border-radius: 8px, padding: 20px

### Metric Cards (Dark Background - Resultados)
- Background: #162338, border: rgba(79,195,247,0.2)
- Icone circular no topo (48px, bg #1a2940)
- Numero grande em cyan (#4fc3f7)
- Label em branco, descricao em cinza (#94a3b8)

### Scope Cards (2 colunas)
- Card com header colorido (navy OU cyan) + corpo branco
- Icone no header (brain, code, etc)
- Lista com checkmarks verdes (#22c55e)

### Info Boxes (rodape da cover)
- Background: #162338, border-radius: 8px
- Label em cyan uppercase 10px
- Valor em branco 14px

### Step Cards (closing)
- Background: #162338
- Numero em cyan grande (28px)
- Titulo em branco, descricao em cinza

### Callout/Quote Box (light slides)
- Border-left 4px cyan (#4fc3f7)
- Background: #f8fafc
- Texto escuro 13px

### Banner (dark slides)
- Background: rgba(79, 195, 247, 0.12)
- Texto branco bold centralizado
- Full-width com border-radius

### Linha Separadora
- Cyan (#4fc3f7), 80px width, 3px height

### Footer - Content Slides (Light)
- Barra navy (#1e3a5f) no bottom, 32px height
- Texto esquerda: "AI Frontiers | [Tipo Documento]" em branco 70% opacity
- Numero da pagina direita em cyan (#4fc3f7)

### Footer - Dark Slides
- Barra #162338 no bottom, 32px height
- Texto esquerda em cinza (#94a3b8)
- Numero da pagina em cyan (#4fc3f7)

### Secao de Contato (closing)
- Label "CONTATO" em cyan uppercase
- Nome em branco 18px bold
- Cargo em cinza
- Links (email, linkedin, telefone) em cyan com underline
- Nota de validade em cinza italico

---

## Elementos Visuais PX (Tema Alternativo)

### Elementos Obrigatorios PX
1. **Header Bar**: Barra azul (#1e3a5f) no topo, altura 60px
2. **Accent Element**: Retangulo amarelo (#f0a500) no canto superior direito, descendo do header
3. **Footer**: "Tech Report [ANO] | PX Ativos Judiciais" esquerda, numero pagina direita
4. **Icones de secao**: Quadrado amarelo arredondado (50x50px)

---

## Workflow de Criacao

### Passo 1: Setup do Ambiente

```bash
# Criar diretorio de trabalho
mkdir -p presentation && cd presentation

# Instalar dependencias
npm init -y
npm install pptxgenjs html2pptx
```

> **IMPORTANTE**: NÃO usar `/mnt/skills/public/pptx/html2pptx.tgz` — esse caminho nao existe.
> Instalar via npm diretamente: `npm install pptxgenjs html2pptx`

### Passo 2: Escolher Abordagem

**Abordagem A - pptxgenjs direto (RECOMENDADA)**:
Criar slides programaticamente com pptxgenjs. Mais controle, melhor resultado.

```javascript
const pptxgen = require("pptxgenjs");

async function createPresentation() {
  const pptx = new pptxgen();
  pptx.layout = "LAYOUT_16x9";

  // Criar slides programaticamente
  const slide = pptx.addSlide();
  // ... adicionar elementos

  await pptx.writeFile({ fileName: "output.pptx" });
}
```

**Abordagem B - HTML + html2pptx**:
Criar slides como HTML e converter. Bom para layouts complexos.

```javascript
const pptxgen = require("pptxgenjs");
const { html2pptx } = require("html2pptx");

async function createPresentation() {
  const pptx = new pptxgen();
  pptx.layout = "LAYOUT_16x9";

  const html = fs.readFileSync("slide01.html", "utf-8");
  await html2pptx(html, pptx);

  await pptx.writeFile({ fileName: "output.pptx" });
}
```

### Passo 3: Cores por Tema

**AI Frontiers (pptxgenjs)**:
```javascript
const AF = {
  bgDarkest:  '0b1929',
  bgSurface:  '162338',
  bgHover:    '1a2940',
  navy:       '1e3a5f',
  accent:     '4fc3f7',
  secondary:  '5bbad5',
  white:      'FFFFFF',
  textSec:    '94a3b8',
  textMuted:  '64748b',
  textDark:   '1e293b',
  subtitle:   '6b7280',
  success:    '22c55e',
  border:     'e2e8f0',
  borderDark: '2a3f5f'   // rgba(79,195,247,0.2) approx
};
```

**PX Ativos Judiciais (pptxgenjs)**:
```javascript
const PX = {
  navy:       '1e3a5f',
  navyDark:   '2d4a6f',
  amber:      'f0a500',
  white:      'FFFFFF',
  gray:       '666666',
  lightGray:  '999999',
  muted:      'f5f7fa',
  green:      '7ac47a',
  border:     'e2e8f0'
};
```

### Passo 4: Estrutura dos Slides (AI Frontiers)

#### Cover Slide
- Background: `bgDarkest` (#0b1929)
- Logo "AI FRONTIERS" top-left
- Circulos decorativos top-right
- Label em cyan ("PROPOSTA DE")
- Titulo grande em branco
- Separador cyan (80px x 3px)
- Subtitulo em branco/cinza
- 3 info boxes no bottom (PARA, DATA, PROPOSTA)

#### Content Slide (Light)
- Background branco
- Titulo bold escuro 28-32px
- Subtitulo cinza 13px
- Callout box com border-left cyan (se houver destaque)
- Metric cards (navy + cyan alternados)
- Bullets com seta cyan
- Footer navy bar

#### Scope Slide (2 Colunas)
- Background branco
- Titulo + subtitulo cinza
- 2 cards lado a lado
- Cada card: header colorido (navy ou cyan) + corpo branco
- Icone no header
- Checkmarks verdes na lista

#### Results Slide (Dark)
- Background: `bgDarkest`
- Titulo branco, subtitulo cinza
- 4 metric cards dark com icones circulares
- Numeros em cyan
- Banner semi-transparente no bottom

#### Closing Slide
- Background: `bgDarkest`
- Logo top-left
- Circulos decorativos
- Titulo grande branco
- 3 step cards (01, 02, 03)
- Separador cyan
- Secao de contato
- Nota de validade em italico

### Passo 5: Validacao Visual

```bash
# Converter para PDF
soffice --headless --convert-to pdf output.pptx

# Converter para imagens para inspecao
pdftoppm -jpeg -r 150 output.pdf slide
```

---

## Tipografia

### AI Frontiers
- **Titulos principais**: 28-32px, bold, branco (dark) ou #1e293b (light)
- **Subtitulos**: 13px, #6b7280 (light) ou #94a3b8 (dark)
- **Metricas grandes**: 36-48px, bold, branco (light bg cards) ou #4fc3f7 (dark bg cards)
- **Labels**: 10-11px, uppercase, letter-spacing 0.5-1px
- **Footer**: 9px
- **Logo**: AI 16px italic, FRONTIERS 16px bold

### PX Ativos Judiciais
- **Titulos principais**: 28-32px, bold, #1e3a5f
- **Subtitulos**: 13-14px, #666
- **Metricas grandes**: 48-56px, bold
- **Labels de metricas**: 11-13px
- **Footer**: 10px, #999

---

## Observacoes Importantes

- Margens laterais: 40px
- Gap entre cards: 20px
- Border-radius padrao: 8px (cards), 12px (scope cards)
- Slides 16:9 (960x540 para HTML, LAYOUT_16x9 para pptxgenjs)
- Sempre usar `npm install pptxgenjs` para a engine de geracao
- Para propostas comerciais e mentorias, usar tema AI Frontiers
- Para Tech Reports internos PX, usar tema PX Ativos Judiciais
