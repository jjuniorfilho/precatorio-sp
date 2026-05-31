# Branding Guide — Consulta Precatório SP

**Estabelecido em**: 2026-05-31
**Via**: /ux-flow (iteração 2 — baseado no rhilo-app como referência)
**Status**: Fonte de verdade canônica

---

## Referência Visual

**rhilo-app** (`apps/frontend`) — shadcn/ui + Tailwind, estética SaaS enterprise limpa.
Características: radius pequeno (8px), palette HSL, sombras sutis profissionais, neutral-gray dominante, fundo branco com borders, tabelas interativas com hover elevation.

---

## Palette de Cores (HSL)

### Primary — Professional Blue
| Token | HSL | Uso |
|-------|-----|-----|
| `--primary` | `217 91% 60%` | Botões primários, links, foco |
| `--primary-dark` | `217 91% 50%` | Hover do primário |
| `--primary-light` | `217 91% 70%` | Acento suave |
| `--primary-50` | `217 91% 97%` | Backgrounds de badge, icon containers |

### Background / Surface
| Token | Light | Dark |
|-------|-------|------|
| `--background` | `0 0% 100%` (branco) | `222 47% 11%` (navy escuro) |
| `--card` | igual ao background | igual ao background |
| `--muted` | `210 40% 96%` (cinza azulado suave) | `217 33% 18%` |

### Semântico
- **Success**: `142 50% 45%` / bg: `149 80% 96%`
- **Warning**: `38 70% 50%` / bg: `48 100% 97%`
- **Error**: `0 60% 50%` / bg: `0 86% 97%`
- **Info**: `199 60% 45%` / bg: `210 100% 97%`

---

## Tipografia

**Família**: Inter (sans) + Fira Code (mono)
**Escala**: 12/13/14/16/20/24/30/36px
**Pesos**: 400/500/600/700
**Títulos**: semibold/bold + `tracking-tight` (-0.025em)

---

## Forma e Espaço

### Border radius — shadcn padrão (`--radius: 0.5rem`)
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

### Tabelas (rhilo table-row pattern)
- Zebra striping: `gray-50` em linhas pares
- Hover: `translateY(-1px)` + shadow-sm + background levemente mais claro
- Quick actions: visíveis só no hover (opacity 0 → 1)

### Cards
`rounded-lg border bg-card shadow-sm` — sem cor de fundo diferente do background, diferenciados apenas pelo border

### Botões
- Default: `bg-primary text-white`, hover: `bg-primary-dark`
- Secondary: `bg-muted text-secondary-foreground`, hover: `bg-muted` lighter
- Height fixo: sm=36px, default=40px, lg=44px

---

## Anti-padrões (baseado no rhilo)

- Nunca usar gradientes de fundo coloridos (apenas `from-primary/10 to-primary/5` em superfícies hero, se houver)
- Nunca usar border-radius > 12px em cards principais
- Nunca usar cor primária como fundo de seções
- Nunca usar sombras pesadas em cards fora de modais/popovers
- Nunca criar badges customizados fora do sistema de semantic colors definido
