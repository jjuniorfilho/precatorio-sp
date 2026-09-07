# Branding Interview — Roteiro para `/ux-flow init`

Roteiro de entrevista para coletar decisoes de branding/UX quando criar um novo design system do zero. Conduzida inline no chat durante o Modo A da skill.

## Regras gerais

- **Inline no chat** — nao gerar arquivo de perguntas para preencher
- **~10 minutos** — nao esticar; se o usuario nao sabe, use default sensato
- **Uma pergunta por mensagem** — evita muro-de-texto, usuario responde rapido
- **Permitir skip** — em qualquer pergunta o usuario pode dizer "escolhe por mim" ou "default"
- **Adaptar ao tipo de produto** — pular perguntas nao-aplicaveis (ex: densidade luxuosa nao se aplica a ferramenta interna de dashboard)
- **Registrar respostas** — manter nota mental das respostas para colocar no `branding-guide.md` gerado no final
- **Aproveitar business context existente** — ver Passo 0 abaixo. Nao perguntar o que os docs ja respondem.

## Passo 0: Descoberta de business context (OBRIGATORIO, antes de qualquer pergunta)

**Antes de iniciar a entrevista**, varra a pasta `docs/` do projeto procurando business docs. Se existirem, leia e pre-preencha as respostas. Confirme com o usuario ao inves de perguntar do zero.

### Arquivos a procurar (em ordem)

```
docs/business/PRODUCT_STRATEGY.md      # produto, posicionamento, audiencia
docs/business/VOICE_OF_CUSTOMER.md     # quem e o usuario, o que ele fala
docs/business/MESSAGING_FRAMEWORK.md   # tom de voz, value props, tagline
docs/business/COMPETITIVE_LANDSCAPE.md # concorrentes (referencias visuais indiretas)
docs/business/INDUSTRY_TRENDS.md       # contexto de industria
docs/business/PRODUCT_METRICS.md       # tipo de metrica = tipo de dashboard
docs/business/CUSTOMER_COMMUNICATION.md # tom escrito
docs/business-context/                 # outros artefatos
docs/business-context/project-briefing.md
docs/pitch/                            # pitch decks (se houver referencia visual)
README.md                              # overview geral
CLAUDE.md                              # pode ter info de produto
```

### Como ler

Use `Glob` para detectar presenca, depois `Read` nos que existirem. Nao precisa ler todos na integra — extrair **apenas** estes campos:

| Campo | Pode vir de |
|---|---|
| Nome do produto | `README.md` (titulo) ou `PRODUCT_STRATEGY.md` |
| Tipo de produto (SaaS, mobile, ferramenta interna) | `PRODUCT_STRATEGY.md` |
| Audiencia / ICP | `VOICE_OF_CUSTOMER.md`, `PRODUCT_STRATEGY.md` |
| Industria / dominio | `INDUSTRY_TRENDS.md`, `PRODUCT_STRATEGY.md` |
| Tom de voz escrito | `MESSAGING_FRAMEWORK.md`, `CUSTOMER_COMMUNICATION.md` |
| Concorrentes | `COMPETITIVE_LANDSCAPE.md` — cada concorrente e uma referencia visual indireta potencial |
| Tagline / value props | `MESSAGING_FRAMEWORK.md` |
| Cores/branding ja definidos | grep por "cor primaria", "color palette", "brand color" em qualquer arquivo |

### Como apresentar ao usuario

Apos ler, inicie a entrevista com um **resumo do que ja sabe**, nao com Q1 em branco:

> "Antes de comecar, li os docs de negocio do projeto e ja tenho algumas respostas. Confirma se esta certo:
>
> **Produto:** [nome extraido do README/PRODUCT_STRATEGY]
> **Tipo:** [SaaS medico / ferramenta interna / app mobile / etc]
> **Audiencia:** [extraido de VOICE_OF_CUSTOMER / PRODUCT_STRATEGY]
> **Dominio:** [medico / financeiro / devtools / etc]
> **Tom de voz escrito:** [extraido de MESSAGING_FRAMEWORK, se existir — ex: 'profissional e direto', 'confiavel e tecnico']
> **Concorrentes citados:** [lista de COMPETITIVE_LANDSCAPE, se existir]
>
> Tudo certo? Corrija ou complete o que estiver errado."

Apos confirmacao, **pule Q1** (ja respondida) e va direto para Q2. As perguntas sobre tom visual (Q2) e referencias (Q7) podem ate mesmo ser pre-preenchidas se os docs forem fortes:

- Se `COMPETITIVE_LANDSCAPE.md` lista concorrentes, esses **sao** referencias candidatas — pergunte: "Voce quer que o visual se alinhe a algum dos concorrentes listados, ou se **diferenciar** propositalmente? Se diferenciar, como?"
- Se `MESSAGING_FRAMEWORK.md` define tom escrito, muitas vezes ele mapeia direto para tom visual: "profissional e direto" → serio/minimalista, "caloroso e acessivel" → playful, "tecnico e preciso" → enterprise.

### Se nenhum business doc existir

Pule este Passo 0 e va direto para Q1 da entrevista normal.

### Outputs do Passo 0

Depois da confirmacao do usuario, atualize sua nota interna (rascunho do `branding-guide.md`) com:

```
Fonte de dados business: [lista de arquivos lidos]
Produto: <confirmado>
Audiencia: <confirmado>
Tom de voz escrito: <confirmado ou inferido>
Referencias potenciais (concorrentes): <lista>
```

Esse bloco deve aparecer como secao "Fontes e Premissas" no `branding-guide.md` final, referenciando os arquivos lidos.

## Ordem e perguntas

### Q1. Produto e audiencia (SOMENTE se Passo 0 nao respondeu)

> "Rapida pergunta para comecar: **qual o produto e para quem?** Ex: 'SaaS medico para dermatologistas brasileiros', 'ferramenta interna de devs', 'app mobile para consumer finance', etc."

**Por que:** define tom visual (clinico vs consumer vs enterprise), vocabulario dos componentes, densidade default.

**Default se skip:** "SaaS profissional para uso diario".

### Q2. Tom visual (sempre)

> "**Qual tom visual** voce prefere? Posso propor opcoes:
> (a) **serio / clinico** — muito usado em saude, financas, legal (Linear-like mas mais conservador)
> (b) **minimalista** — branco generoso, poucas cores, tipografia forte (Vercel, Stripe)
> (c) **playful** — cores vivas, cantos arredondados, ilustracoes (Notion, Linear)
> (d) **enterprise** — alta densidade, informacional, cinza + azul (Jira, Salesforce)
> (e) **bold** — contraste alto, tipografia grande, espacos marcados (Apple marketing)
> Qual mais combina, ou tem outra referencia?"

**Default se skip:** (a) serio/clinico para SaaS profissional, (b) minimalista para ferramentas internas.

### Q3. Tema (sempre)

> "**Light, dark, ou ambos?** Se ambos, qual e o primario (o que usuario ve primeiro)?"

**Default se skip:** Light como primario, dark para v2 (nao gerar dark nesta iteracao se nao for explicito).

### Q4. Cor primaria (sempre)

> "**Cor primaria** — tres formas de responder:
> (a) um hex/hsl especifico (ex: `#2563eb` ou `hsl(221, 83%, 53%)`)
> (b) nome de uma cor (azul, verde, roxo) e eu escolho um tom consistente com o tom visual
> (c) referencia externa — Linear (azul #5e6ad2), Stripe (roxo #635bff), Vercel (preto/branco), Notion (preto/vermelho), Figma (roxo/azul), ou link/nome de um app admirado
> Qual?"

**Default se skip:** azul `hsl(221, 83%, 53%)` (equivalente a Tailwind `blue-600` / shadcn default).

**Acao subsequente:** a partir da primaria, derivar secundaria (complementar rotacionada 40-60° no HSL) e acento (quente se primaria fria, e vice-versa). Nao perguntar — decidir e mostrar no showcase.

### Q5. Tipografia (sempre)

> "**Tipografia** — tres opcoes:
> (a) **Inter** (default, funciona para 95% dos casos, gratuita via Google Fonts)
> (b) outra familia especifica (ex: IBM Plex, Manrope, Satoshi, JetBrains Mono)
> (c) tenho restricao corporativa (define qual)
> Qual?"

**Default se skip:** Inter.

### Q6. Densidade (as vezes)

**So perguntar se** o produto for informacional (dashboard, admin, CRUD). Skip para landing pages ou consumer apps.

> "**Densidade** — qual se aproxima mais?
> (a) **confortavel** — espacos generosos, fontes medias (Linear)
> (b) **compacta** — alta densidade, fontes menores, muitas linhas visiveis (GitHub, Jira)
> (c) **luxuosa** — muito espaco em branco, fontes grandes (Apple, Stripe marketing)
> Qual?"

**Default se skip:** confortavel.

### Q7. Referencias visuais (sempre, no final)

> "**Ultima pergunta:** tem alguma referencia visual que voce admira e quer imitar o feeling? Links, screenshots, nomes de apps. Quanto mais especifico, melhor ('o Linear v2 novo', 'dashboard do Supabase', 'cards do Stripe checkout'). Se nao tiver, tudo bem — uso defaults baseados no que voce ja me disse."

**Acao subsequente:** se o usuario cita uma referencia, mencionar no `branding-guide.md` como "inspiracao visual" — isso ajuda a validar se o output ficou proximo do que ele queria.

## Perguntas opcionais (so se relevante)

### QX. Iconografia

> "Icones em lucide (padrao), heroicons, ou outro? Default: lucide inline SVG."

### QY. Radius

> "Cantos arredondados: muito (12-16px), medio (6-8px), pouco (2-4px)? Default: 8px (medio)."

### QZ. Shadow intensity

> "Sombras fortes (drop shadow marcado, estilo Figma) ou sutis (apenas elevation, estilo Linear)? Default: sutis."

## Formato da nota interna (rascunho para `branding-guide.md`)

Apos a entrevista, monte um rascunho em memoria antes de gerar o arquivo:

```
Produto: [Q1]
Audiencia: [Q1]
Tom: [Q2 escolhido]
Tema: [Q3 escolhido + primario]
Cor primaria: [Q4 - resolvida em HSL]
  - Se referencia externa, descobrir o hex/hsl exato
  - Se nome generico, escolher tom consistente com tom
Cor secundaria: [derivada]
Cor acento: [derivada]
Tipografia: [Q5]
Densidade: [Q6 ou default]
Referencias: [Q7]
Radius: [QY ou default 8px]
Shadows: [QZ ou default sutis]
```

Esses valores alimentam diretamente o template `assets/branding-guide-template.md` e os tokens em `assets/shared-css-template.css`.

## O que NAO perguntar

- Hex codes de cores secundarias (derive a partir da primaria)
- Tamanhos de fonte especificos (use escala modular baseada na densidade)
- Breakpoints responsivos (use defaults: 640/768/1024/1280)
- Nomes especificos de classes CSS (decide voce, baseado em convencoes shadcn-like)
- Arquitetura de tokens (tier-based vs semantic-based) — decida por defaults, nao exponha complexidade

## Duracao esperada

- Minimo: 3 perguntas (Q1, Q2, Q4) = ~2 min se usuario usa muito skip
- Tipico: 5-6 perguntas = ~7 min
- Maximo: 10 perguntas se usuario quer explorar tudo = ~15 min

Se o usuario demonstrar paciencia baixa ("rapido ai", "so faz o padrao"), corte para Q1 + Q4 e use defaults para o resto.
