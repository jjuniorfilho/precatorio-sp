---
name: px-deck
description: >-
  Cria apresentações .pptx de ALTO DETALHE na identidade PX Ativos Judiciais
  (navy + ouro, logo real), com prints REAIS das aplicações capturados via
  Playwright, diagramas de arquitetura/fluxo renderizados de Mermaid, e o
  vocabulário/numeros reais do sistema. Use quando pedirem "uma
  apresentação", "um deck", "slides", "um PPTX", "apresentação para o board /
  conselho / sócios", "handoff em slides", ou quiser materializar um tema
  (arquitetura, evals, produto, roadmap) num deck no padrão visual PX com telas
  reais. Dois registros: TÉCNICO (handoff de engenharia, com diagramas e termos)
  e EXECUTIVO (board/comercial, zero técnico, vende o produto). Gera .pptx que
  abre nativo no PowerPoint / Office 365.
---

# PX Deck — apresentações .pptx no padrão PX, com telas reais

Receita reutilizável que produz decks `.pptx` densos e com identidade PX:
prints reais das apps (Playwright), diagramas (Mermaid -> PNG), tabelas/cards,
e o logo real da PX. A engine é `pptxgenjs` (renderiza fiel no PowerPoint). O
núcleo de slides está em [`assets/deck-lib.js`](assets/deck-lib.js).

## Regras DURAS (não violar)

1. **Acentuação PT-BR correta** em TODA a prosa (á é í ó ú ã õ ç â ê ô à). É o
   erro nº 1 e o mais visível. A `deck-lib` não conserta isso sozinha: o texto
   que você passa tem que vir acentuado. Validar SEMPRE no fim (ver §Validação).
2. **Sem travessão (—)** em texto/UI/títulos. Use dois-pontos, vírgula ou
   parênteses. Blocos de comando de terminal podem ficar sem acento (mimicam input).
3. **Tela real > mockup.** Capture as apps rodando (modo real, dado real) via
   Playwright. Não invente telas nem use mock quando a stack está no ar.
4. **Número real > número inventado.** Puxe métricas do DB/sistema; no registro
   executivo, rotule honestamente (ex.: "ambiente de validação", não "clientes").
5. **Logo real** (`assets/logo-px.png`): direto nos slides claros, em chip branco
   nos slides navy. A `deck-lib` faz isso por construção.

## Fluxo

### 1. Setup (uma vez)

```bash
WORK=<scratchpad>/pptx; mkdir -p "$WORK" && cd "$WORK"
npm init -y >/dev/null 2>&1 && npm install pptxgenjs@^3.12 >/dev/null 2>&1
```

### 2. Capturar telas reais (se o deck mostra as apps)

Use [`assets/capture-screens.js`](assets/capture-screens.js) como template. Ele
injeta um JWT real no `localStorage` (mesmo truque do e2e) e tira screenshot de
cada rota. Pré-requisitos: a stack no ar (`docker compose ... up -d`), e os ids
reais (user PLATFORM_ADMIN/ANALYST, tenant, um lawsuit/run de exemplo).

- Descubra os ids no DB: `docker exec pxagents-dev-postgres psql -U dev -d pxagents -tAc "..."`.
- O `JWT_SECRET` dev é `dev-jwt-secret-please-change`; o claim shape é `{ sub, tenantId, role, scopes }` HS256 (ADR-007).
- Storage keys: a que o app usa no `localStorage` (exemplo px-agents: admin `px-agents.admin.jwt`, portal `px-agents.portal.jwt`).
- Viewport 1440x900, `deviceScaleFactor: 2`. Confira 2-3 prints (Read no PNG)
  antes de montar, para garantir que populam (não estão em /login nem skeleton).

### 3. Renderizar diagramas (se o deck é técnico)

Use [`assets/diagrams-harness.html`](assets/diagrams-harness.html) (tema PX claro
para Mermaid) + [`assets/render-diagrams.js`](assets/render-diagrams.js). Escreva
seus flowcharts no harness (classes `navy`/`gold`/`store`/`warn`), renderize, e a
`deck-lib.diagram()` embute o PNG preservando o aspect ratio. PPTX não renderiza
Mermaid nativo: por isso o passo de rasterização.

### 4. Montar o deck

Escreva um gerador (ex.: `gen.js`) que usa a `deck-lib`:

```js
const Pptx = require(path.join(__dirname, 'node_modules/pptxgenjs'));
const { makeDeck } = require('<repo>/.claude/skills/px-deck/assets/deck-lib.js');
const d = makeDeck(Pptx, { logoPath: '<...>/logo-px.png', footerText: 'PX Agents · Confidencial', title: '...' });

d.cover({ label, title, subtitle, infoBoxes: [['PARA','...']] });
d.footer(d.section('01', 'Seção', 'subtítulo'));     // divisor de seção (navy)
d.statement({ label, big, sub });                    // frase de impacto (navy)
d.metrics({ title, subtitle, items: [['78','processos'], ...], note });
d.showcase({ title, subtitle, img, caption });       // screenshot em destaque
d.shot({ title, subtitle, img, bullets: [...] });    // screenshot + bullets (técnico)
d.diagram({ title, subtitle, img, natW, natH, bullets, layout: 'wide'|'side' });
d.steps({ title, subtitle, items: [['1','Passo','texto'], ...] });
d.cards({ title, subtitle, items: [['Cabeçalho','corpo', corOpcional], ...], note });
d.quote({ title, subtitle, quote, author, bullets });
d.closing({ label, title, subtitle, refs: [['LABEL','valor']], note });
await d.save('<out>.pptx');
```

`d.C` expõe a paleta (`d.C.navy`, `d.C.amber`, `d.C.green`, `d.C.red`...).

### 5. Validação (obrigatória)

```bash
unzip -t out.pptx >/dev/null && echo OK            # zip íntegro
unzip -l out.pptx | grep -c "ppt/slides/slide"     # contagem de slides
# acentos presentes (deve ser > 0) e SEM mojibake (Ã quebrado):
for f in $(unzip -l out.pptx | grep -oE "ppt/slides/slide[0-9]+.xml"); do unzip -p out.pptx "$f"; done \
  | grep -oE "[áàâãéêíóôõúç]" | wc -l
```

Idealmente, render-check num PowerPoint/Office 365. Sem LibreOffice local, faça a
verificação por XML acima + confira os PNGs de print/diagrama com Read antes de embutir.

## Os dois registros

| Registro | Quando | Slides típicos | Tom |
| --- | --- | --- | --- |
| **Técnico** (handoff) | passar o sistema a engenheiros | section + diagram + shot + tabelas + code | preciso, com termos e diagramas |
| **Executivo** (board) | vender a sócios / C-level | cover + statement + metrics + showcase + steps + cards | ZERO técnico, narrativo, vende valor |

Exemplos vivos (no projeto px-agents, de onde esta skill foi promovida): handoff
técnico `docs/onboarding/handoff-px-agents.pptx` e board `docs/presentations/px-agents-conselho-2026-06.pptx`,
ambos gerados com esta mesma receita.

## Identidade visual

Paleta, tipografia e tipos de slide completos em
[`reference/px-theme.md`](reference/px-theme.md). Resumo: navy `#1E3A5F` + ouro
`#F0A500`, fundo navy nas capas/seções/closing e branco no conteúdo, Arial (texto)
+ Courier New (código), logo real PX, rodapé navy com numeração em ouro.
