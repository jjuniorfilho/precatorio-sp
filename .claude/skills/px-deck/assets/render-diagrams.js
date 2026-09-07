/**
 * render-diagrams.js — rasteriza cada diagrama Mermaid do harness para PNG (alta DPI).
 *   node render-diagrams.js
 * Ajuste HARNESS, OUT e IDS. Anote o tamanho natural (WxH) impresso: a
 * deck-lib.diagram() usa natW/natH para preservar o aspect ratio no slide.
 */
// Raiz do projeto que tem playwright instalado (define REPO=/abs/do/projeto ao rodar).
const REPO = process.env.REPO || process.cwd();
const { chromium } = require(REPO + '/node_modules/playwright');
const fs = require('fs'); const path = require('path');

const HARNESS = process.env.HARNESS || (__dirname + '/diagrams-harness.html');
const OUT = process.env.DIAG_OUT || '/tmp/px-deck-diagrams';
const IDS = (process.env.DIAG_IDS || 'd1').split(',');   // ex.: 'd1,d2,d3'

fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const browser = await chromium.launch();
  const ctx = await browser.newContext({ viewport: { width: 1600, height: 1200 }, deviceScaleFactor: 3 });
  const page = await ctx.newPage();
  await page.goto('file://' + HARNESS, { waitUntil: 'networkidle' });
  await page.waitForTimeout(2500);
  for (const id of IDS) {
    try {
      const loc = page.locator(`#${id} svg`);
      await loc.waitFor({ timeout: 8000 });
      await loc.screenshot({ path: path.join(OUT, id + '.png') });
      const b = await loc.boundingBox();
      console.log(`OK ${id}  natW=${Math.round(b.width)} natH=${Math.round(b.height)}`);
    } catch (e) { console.log(`ERR ${id}  ${String(e).slice(0, 90)}`); }
  }
  await browser.close();
  console.log('diagramas em', OUT);
})();
