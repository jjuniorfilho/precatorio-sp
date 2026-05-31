# Branding Guide — Consulta Precatório SP

**Estabelecido em**: 2026-05-31
**Via**: /ux-flow (iteração 3 — baseado no BTG Pactual Content Portal como referência)
**Status**: Fonte de verdade canônica

---

## Referência Visual

**BTG Pactual Content Portal** (`content.btgpactual.com`) — design institucional corporativo.
Características: navbar em royal blue, hero em dark navy, radius pequeno (8px), tipografia Sora para headings + Inter para UI, sombras sutis, sidebar branca com item ativo em azul-cinza claro, cards com border #E5E7EB, fundo branco dominante no conteúdo.

---

## Palette de Cores (HSL)

### Três Níveis de Azul — Sistema BTG
| Token | HSL | Hex aprox. | Uso |
|-------|-----|------------|-----|
| `--primary` (Royal Blue) | `222 57% 42%` | #2B4FA8 | Navbar, botões primários, links |
| `--navy` (Dark Navy) | `225 62% 14%` | #0C1B3D | Hero, footer, fundo escuro |
| `--blue-section` (Medium Blue) | `221 58% 44%` | #2F5BB4 | Seções CTA, banners |

### Primary — Royal Blue corporativo
| Token | HSL | Uso |
|-------|-----|-----|
| `--primary` | `222 57% 42%` | Botões primários, links, navbar background |
| `--primary-dark` | `222 57% 34%` | Hover do primário |
| `--primary-light` | `222 57% 55%` | Acento suave |
| `--primary-50` | `222 57% 96%` | Backgrounds de badge, icon containers |

### Background / Surface
| Token | Light | Dark |
|-------|-------|------|
| `--background` | `0 0% 100%` (branco) | `225 62% 11%` |
| `--card` | igual ao background | `225 62% 13%` |
| `--muted` | `214 40% 96%` (azul-cinza muito claro) | `222 40% 18%` |
| `--sidebar-active-bg` | `214 40% 96%` = #F0F3F8 | `222 40% 22%` |

### Ícones e Elementos Interativos
| Token | HSL | Hex | Uso |
|-------|-----|-----|-----|
| `--icon-blue` | `219 55% 55%` | #4472CA | Ícones na sidebar, feature icons |
| `--border` | `220 13% 91%` | #E5E7EB | Todas as bordas |

### Texto
| Token | Hex | Uso |
|-------|-----|-----|
| `--foreground` (`--text-primary`) | #0F172A | Texto principal, quase preto |
| `--muted-foreground` (`--text-secondary`) | #6B7280 | Texto secundário, labels |
| `--text-muted` | #9CA3AF | Texto muted, placeholders |

### Semântico
- **Success**: `142 50% 45%` / bg: `149 80% 96%`
- **Warning**: `38 70% 50%` / bg: `48 100% 97%`
- **Error**: `0 60% 50%` / bg: `0 86% 97%`
- **Info**: `199 60% 45%` / bg: `210 100% 97%`

---

## Tipografia

### Famílias
| Família | Uso | Pesos |
|---------|-----|-------|
| **Sora** | Headings h1–h3, card-title, page-title, value-amount | 600, 700, 800 |
| **Inter** | Body, UI, labels, botões, inputs | 400, 500, 600, 700 |
| **Fira Code** | Números de processo, código mono | 400, 600 |

### Import Google Fonts
```css
@import url('https://fonts.googleapis.com/css2?family=Sora:wght@600;700;800&family=Inter:wght@400;500;600;700&family=Fira+Code:wght@400;600&display=swap');
```

### Tokens
```css
--font-heading: 'Sora', sans-serif;
--font-sans:    'Inter', system-ui, sans-serif;
--font-mono:    'Fira Code', monospace;
```

### Escala
12 / 13 / 14 / 16 / 20 / 24 / 30 / 36px
**Pesos**: 400 / 500 / 600 / 700
**Títulos**: Sora bold + `tracking-tight` (-0.025em)

---

## Forma e Espaço

### Border radius — base `--radius: 0.5rem`
- `sm` = 4px | `md` = 6px | `lg` = 8px | `xl` = 12px | `full` = 9999px

**Botões**: 6px (md). **Cards**: 8px (lg). **Modais**: 12px (xl). **Badges/pills**: 9999px.

### Shadows
```
xs:  0 1px 2px rgba(16,24,40,0.05)
sm:  0 1px 3px rgba(16,24,40,0.1), 0 1px 2px rgba(16,24,40,0.06)   ← cards padrão
md:  0 4px 8px -2px rgba(16,24,40,0.1), 0 2px 4px -2px (...)      ← hover / modais
lg:  0 12px 16px -4px ...                                           ← sheets / popovers
```

---

## Componentes Chave

### Navbar (portal público)
- Background: `--primary` (royal blue #2B4FA8)
- Logo e links: texto branco (`color: #fff`)
- Botão outline: borda branca + texto branco (`.btn-outline-white`)
- Botão filled: fundo branco + texto azul primário (`.btn-filled-white`)

### Hero (landing page)
- Background: `--navy` (dark navy #0C1B3D)
- Título: branco (`color: #fff`), fonte Sora bold
- Subtítulo: `rgba(255,255,255,0.75)`
- Eyebrow badge: fundo `rgba(255,255,255,0.12)`, borda `rgba(255,255,255,0.2)`
- Search bar: fundo branco com sombra sobre o hero dark

### Sidebar Admin
- Background: `#FFFFFF` (branco puro)
- Border-right: `1px solid var(--border)` — #E5E7EB
- Item ativo: `background: var(--sidebar-active-bg)` = `hsl(214 40% 96%)` = #F0F3F8
- Ícones: `color: var(--icon-blue)` = #4472CA
- Item ativo, ícones: `color: var(--primary)`

### Topbar Admin
- Background: `#FFFFFF`
- Border-bottom: `1px solid var(--border)`

### Page Background (admin)
- `background: var(--muted)` = `hsl(214 40% 96%)` como page-level background

### Footer (landing page)
- Background: `--navy` (dark navy)
- Texto: `rgba(255,255,255,0.6)`
- Links: `rgba(255,255,255,0.75)` → hover: `#fff`
- Brand: `#fff` bold

### Tabelas (BTG table-row pattern)
- Zebra striping: `gray-50` em linhas pares
- Hover: `translateY(-1px)` + shadow-sm + background levemente mais claro
- Quick actions: visíveis só no hover (opacity 0 → 1)

### Cards
`rounded-lg border bg-card shadow-sm` — sem cor de fundo diferente do background, diferenciados pelo border (#E5E7EB)

### Botões
- Default: `bg-primary text-white`, hover: `bg-primary-dark`
- Navbar outline (sobre azul): borda branca + texto branco
- Navbar filled (sobre azul): fundo branco + texto azul primário
- Height fixo: sm=36px, default=40px, lg=44px

---

## Anti-padrões

- Nunca usar gradientes de fundo coloridos (apenas superfícies sólidas — navy, blue-section, branco ou muted)
- Nunca usar border-radius > 12px em cards principais
- Navbar de páginas públicas **sempre** em royal blue (nunca branco)
- Hero da landing **sempre** em dark navy (nunca branco)
- Footer da landing **sempre** em dark navy
- Nunca usar sombras pesadas em cards fora de modais/popovers
- Nunca criar badges customizados fora do sistema de semantic colors definido
- Sidebar admin **sempre** com fundo branco (nunca azul)
