# Identidade visual PX (deck)

Padrão Navy + Ouro da PX Ativos Judiciais. Implementado em `assets/deck-lib.js`.

## Paleta (`d.C`)

| Token | Hex | Uso |
| --- | --- | --- |
| `navy` | `#1E3A5F` | fundos de capa/seção/closing, cabeçalhos de card, texto de título |
| `navyDark` | `#15293F` | blocos de código |
| `navyCard` | `#243B57` | info-boxes sobre fundo navy |
| `amber` | `#F0A500` | acentos, labels, numeração de rodapé, destaque |
| `white` | `#FFFFFF` | fundo de conteúdo, texto sobre navy |
| `gray` | `#4A5568` | corpo de texto em slides claros |
| `muted` | `#F5F7FA` | fundo de card claro |
| `green` | `#2E9E5B` | positivo / aprovado |
| `red` | `#D14343` | crítico / atenção |
| `faintNum` | `#294565` | número grande translúcido nas seções |

## Tipografia

- Texto: **Arial**. Código/comando: **Courier New**. (Ambas existem no Office 365,
  zero substituição de fonte.)
- Título de conteúdo: 25pt bold navy. Subtítulo: 13pt gray.
- Título de capa: 60pt (44pt se > 22 chars). Seção: número 140pt + título 40pt.
- Métrica grande: 46pt bold branco. Label de métrica: 14pt ouro.
- Rodapé: 9pt; número da página em ouro.

## Anatomia

- **Capa / Seção / Statement / Closing**: fundo navy, faixa ouro no topo-esquerdo,
  logo em chip branco, acento ouro.
- **Conteúdo**: fundo branco, header com logo + divisória ouro + título navy,
  rodapé navy com numeração ouro.
- **Logo**: `assets/logo-px.png` (PX navy, transparente). Direto nos slides claros;
  em chip branco arredondado nos navy (a `deck-lib` faz isso). Mantê-lo pequeno
  (320px embute leve; o original 1920px infla o arquivo ~4x).
- Layout 16:9 wide (13.333 x 7.5 pol). Margens ~0.6 pol.

## Tipos de slide (deck-lib)

`cover` · `section` · `statement` (frase de impacto navy) · `metrics` (cards de
número) · `showcase` (screenshot em destaque, com caption) · `shot` (screenshot +
bullets) · `diagram` (PNG wide/side + bullets) · `steps` (passos numerados) ·
`cards` (2-4 colunas com cabeçalho colorido) · `quote` (citação) · `closing`.
Para conteúdo livre: `contentSlide(title, sub)` retorna o slide com header; o
caller adiciona e chama `d.footer(slide)`.

## Registro técnico vs executivo

- **Técnico**: prioriza `diagram`, `shot`, tabelas e blocos de código. Pode usar
  termos. Diagramas renderizados do Mermaid (tema PX claro).
- **Executivo (board)**: prioriza `statement`, `metrics`, `showcase`, `steps`,
  `cards`. ZERO jargão. Traduz tudo para valor. Números reais rotulados com
  honestidade (ex.: "ambiente de validação"). Tom calibrado pelo lead.
