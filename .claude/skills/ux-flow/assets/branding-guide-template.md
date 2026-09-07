# Branding Guide — {{PROJECT_NAME}}

> Fonte de verdade das decisoes de branding e design system deste projeto.
> Gerado por `/ux-flow init` em {{DATE}}.
> Sempre que atualizar o `shared.css`, sincronizar este documento.

## Produto

**Nome:** {{PROJECT_NAME}}
**Tipo:** {{PRODUCT_TYPE}}
**Audiencia:** {{AUDIENCE}}
**Dominio / industria:** {{DOMAIN}}

## Fontes e Premissas

Este guide foi gerado a partir de:

- `{{SOURCE_DOC_1}}`
- `{{SOURCE_DOC_2}}`
- _(adicionar demais fontes lidas)_

Decisoes nao cobertas pelos docs foram respondidas por:

- _(lista de respostas do usuario durante a entrevista)_
- _(defaults aplicados quando usuario escolheu 'escolhe por mim')_

## Tom visual

**Escolha:** {{TONE}}

**Justificativa:** {{TONE_RATIONALE}}

**Implicacoes de desenho:**

- {{TONE_IMPLICATION_1}}
- {{TONE_IMPLICATION_2}}
- {{TONE_IMPLICATION_3}}

## Paleta de cores

### Primaria

| Token | Valor | Uso |
|---|---|---|
| `--primary` | `{{PRIMARY}}` | Botoes CTA, links, elementos interativos |
| `--primary-foreground` | `{{PRIMARY_FOREGROUND}}` | Texto sobre fundo primary |
| `--primary-light` | `{{PRIMARY_LIGHT}}` | Hovers, backgrounds suaves, badges |
| `--primary-hover` | `{{PRIMARY_HOVER}}` | Hover em botoes primary |

**Escolhida por:** {{PRIMARY_RATIONALE}}

### Secundaria

| Token | Valor | Uso |
|---|---|---|
| `--secondary` | `{{SECONDARY}}` | Elementos secundarios, destaques diferenciados |
| `--secondary-light` | `{{SECONDARY_LIGHT}}` | Badges, chips secundarios |

**Derivada por:** rotacao de {{HUE_ROTATION}}° no HSL da primaria.

### Neutros

| Token | Valor | Uso |
|---|---|---|
| `--background` | `{{BACKGROUND}}` | Fundo geral da aplicacao |
| `--foreground` | `{{FOREGROUND}}` | Texto principal |
| `--card` | `{{CARD}}` | Fundo de cards, modais |
| `--muted` | `{{MUTED}}` | Texto secundario, placeholders |
| `--muted-light` | `{{MUTED_LIGHT}}` | Backgrounds desabilitados, skeleton |
| `--border` | `{{BORDER}}` | Bordas de cards, separadores |
| `--border-strong` | `{{BORDER_STRONG}}` | Bordas de inputs, hover states |

### Status

| Token | Valor | Uso |
|---|---|---|
| `--success` | `{{SUCCESS}}` | Confirmacoes, sucessos |
| `--warning` | `{{WARNING}}` | Avisos, estados intermediarios |
| `--destructive` | `{{DESTRUCTIVE}}` | Erros, acoes destrutivas |

## Tipografia

**Familia:** {{FONT_FAMILY}}
**Fonte:** {{FONT_SOURCE}} (ex: Google Fonts, self-hosted)
**Tamanho base:** {{BASE_FONT_SIZE}} ({{BASE_FONT_SIZE_PX}})

**Escala modular** (relativa a `1rem = {{BASE_FONT_SIZE_PX}}`):

| Classe | Tamanho | Uso tipico |
|---|---|---|
| `.text-xs` | 0.667rem | Timestamps, meta |
| `.text-sm` | 0.778rem | Labels, captions |
| `.text-base` | 1rem | Body padrao |
| `.text-lg` | 1.111rem | Body destacado |
| `.text-xl` | 1.222rem | Subtitulos |
| `.text-2xl` | 1.444rem | Titulos de secao |
| `.text-3xl` | 1.778rem | Titulos de pagina |

**Pesos usados:** 400, 500, 600, 700.

## Densidade e espacamento

**Densidade:** {{DENSITY}}

**Justificativa:** {{DENSITY_RATIONALE}}

**Escala de espacamento** (multiplos de 4px):

```
4 8 12 16 20 24 32 48 64
```

**Radius padrao:** `{{RADIUS}}` (`--radius`)
**Radius pequeno:** `{{RADIUS_SM}}` (`--radius-sm`, botoes, inputs)
**Radius grande:** `{{RADIUS_LG}}` (`--radius-lg`, modais)

## Sombras

**Intensidade:** {{SHADOW_INTENSITY}}

- `--shadow-sm`: cards estaticos
- `--shadow-md`: cards hover, dropdowns
- `--shadow-lg`: modais, sheets

## Iconografia

**Padrao:** {{ICON_LIBRARY}}
**Uso em HTML:** inline SVG, `stroke="currentColor"`
**Tamanhos:** 14px (small), 18px (medium), 22px (hero)

## Referencias visuais consultadas

{{REFERENCES_LIST}}

## Componentes disponiveis

Ver `components.html` neste diretorio para showcase visual completo. A lista textual dos componentes tokenizados no `shared.css`:

- **Buttons**: `.btn`, `.btn-primary`, `.btn-outline`, `.btn-ghost`, `.btn-destructive`, `.btn-sm`, `.btn-icon`
- **Cards**: `.card`, `.card-hover`
- **Badges**: `.badge-*` (primary, secondary, muted, success, warning, destructive)
- **Inputs**: `.input`
- **Skeleton**: `.skeleton`
- **Typography utilities**: `.text-*`, `.font-*`, `.truncate`
- **Layout utilities**: `.flex*`, `.gap-*`, `.p-*`, `.mt-*`
- **Animations**: `.animate-spin`

Componentes faltantes devem ser adicionados ao `shared.css` canonico via edicao manual ou nova rodada de `/ux-flow init` evolutivo.

## Decisoes pendentes

- _(lista de itens que foram explicitamente adiados)_

## Changelog

| Data | Mudanca | Motivo |
|---|---|---|
| {{DATE}} | Versao inicial | Gerado via `/ux-flow init` |

---

*Ao evoluir este guide, atualizar `shared.css` correspondentemente e vice-versa. Proximas geracoes de protótipo (`/ux-flow prototype`) referenciam este arquivo e o CSS como fonte de verdade — inconsistencias entre os dois quebram a previsibilidade visual.*
