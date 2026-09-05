# Design System Discovery — Heuristicas

Procedimento para detectar se um projeto ja tem design system estabelecido antes de propor criar um novo. Usado pelo Modo A (`init`) da skill `ux-flow`.

## Ordem de verificacao

Verifique na ordem abaixo. **Pare na primeira correspondencia forte** e reporte ao usuario.

### 1. Design system canonico da skill (forte)

```
docs/design-system/shared.css
docs/design-system/branding-guide.md
```

Se existirem, e o que a skill gerou anteriormente. Confirmar idade (via `git log` do arquivo) e perguntar se ainda e o canonico ou se precisa evoluir.

### 2. Shared.css inline em pasta de prototipo (medio)

```
docs/prototypes/*/shared.css
```

Padrao encontrado em projetos que iniciaram prototipagem sem formalizar design system. Exemplo real: `docs/prototypes/ui-overhaul/shared.css` no Aura V2 (Issue #150). Reportar localizacao e oferecer tres opcoes:
- **Promover** o `shared.css` do prototipo para `docs/design-system/` como canonico (move + cria `branding-guide.md` retroativamente)
- **Manter** como esta e apenas criar `branding-guide.md` que documente as decisoes
- **Substituir** com novo design system via entrevista

### 3. Branding/design docs existentes (medio)

```
docs/branding/
docs/design/
docs/ui/
BRANDING.md
DESIGN.md
```

Documentacao escrita mas sem HTML/CSS associado. Ler para extrair decisoes ja tomadas (cor primaria, tipografia, tom). Nao ignore — essas decisoes devem alimentar a entrevista se precisar criar `shared.css` novo.

### 4. Biblioteca de componentes (forte)

```
packages/ui/
libs/ui/
libs/shared/ui/
libs/design-system/
```

Projeto tem lib de componentes propria. Procurar dentro dela:
- `*.css` com custom properties
- `theme.ts` ou `theme.json`
- `tokens.ts` ou `tokens.json`
- Storybook (`*.stories.tsx`)

Se encontrar, **extrair tokens** para usar como fonte de verdade. Nao criar `shared.css` paralelo — criar um `shared.css` que **importe ou replique** os tokens da lib, mantendo consistencia.

### 5. shadcn/ui ou similar (forte)

```
apps/*/src/components/ui/button.tsx        # padrao shadcn
apps/*/src/app/globals.css                  # Next.js com shadcn
apps/*/src/styles/globals.css
components.json                             # arquivo de config do shadcn
```

Projeto usa shadcn. As custom properties CSS (`:root { --background: ...; --foreground: ...; }`) em `globals.css` **sao** o design system. Ler e usar como fonte de verdade. O `shared.css` gerado pela skill deve importar ou replicar essas variaveis.

### 6. Tailwind config (medio)

```
tailwind.config.{ts,js,cjs,mjs}
```

Tokens em formato Tailwind. Extrair `theme.extend.colors`, `theme.extend.fontFamily`, etc. Converter para custom properties CSS no `shared.css` gerado.

### 7. Figma tokens exportados (fraco, mas sinal)

```
*.figma.tokens.json
figma-tokens.json
tokens/*.json
```

Projeto usa Figma Tokens Studio. Parsear o JSON e gerar `shared.css` a partir dos tokens.

### 8. Framework CSS global (fraco)

```
apps/*/src/app.css
apps/*/src/index.css
apps/*/public/globals.css
```

CSS global sem estrutura clara. Ler para identificar se ha tokens (custom properties) ou apenas resets. Se so resets, tratar como "nada encontrado" e propor criar design system novo.

## Cenarios de output

Apos rodar as verificacoes, classifique em um destes tres cenarios e reporte ao usuario:

### Cenario 1: Canonico ja existe

Passou na verificacao 1. Reportar:

> "Design system canonico encontrado em `docs/design-system/`. Ultimo update: [data via git log]. Quer: (a) usar como esta para o proximo prototipo, (b) revisar/evoluir o `branding-guide.md` antes?"

### Cenario 2: Algo proximo existe

Passou em qualquer uma das verificacoes 2-8 mas nao na 1. Reportar:

> "Encontrei [descricao do que foi achado em qual local]. Quer:
> (a) promover para `docs/design-system/` como canonico,
> (b) criar `docs/design-system/` do zero via entrevista (ignorando o que ja existe),
> (c) manter o atual e gerar apenas o `branding-guide.md` documentando as decisoes ja tomadas?"

Se o que foi encontrado for uma lib de componentes (verificacao 4) ou shadcn (5), **sempre recomende a opcao (c)** — a lib e fonte de verdade, nao o `shared.css`.

### Cenario 3: Nada encontrado

Nenhuma verificacao passou. Reportar:

> "Nenhum design system encontrado. Posso conduzir uma entrevista (~10 min) para coletar preferencias e gerar `docs/design-system/shared.css` + `branding-guide.md` + `components.html`. Topa?"

## Comandos uteis durante a descoberta

```bash
# Listar candidatos a design system
find docs -name "shared.css" -o -name "branding-guide.md" 2>/dev/null

# Detectar shadcn
test -f components.json && echo "shadcn detected"

# Ler tailwind config se existir
find . -maxdepth 3 -name "tailwind.config.*" 2>/dev/null

# Procurar custom properties em CSS global
grep -r "^:root" apps/*/src/**/*.css libs/**/*.css 2>/dev/null | head
```

Use apenas as ferramentas `Glob`, `Grep` e `Read` (ou `Bash` quando precisar de shell) — nao modifique arquivos durante a fase de descoberta.
