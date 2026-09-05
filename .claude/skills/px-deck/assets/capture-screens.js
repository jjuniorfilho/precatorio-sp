/**
 * capture-screens.js — TEMPLATE de captura de telas reais via Playwright.
 *
 * Tira screenshot de cada rota injetando um JWT real no localStorage (mesmo
 * truque do e2e autenticado). Ajuste o bloco CONFIG e rode:
 *   node capture-screens.js
 *
 * Pré-requisitos: stack no ar; playwright + jsonwebtoken disponíveis no
 * node_modules do repo. Descubra os ids no DB antes:
 *   docker exec pxagents-dev-postgres psql -U dev -d pxagents -tAc \
 *     "select id, email, role, tenant_id from users where email in ('admin@px.local','analista@px.local');"
 */
// Raiz do projeto que tem playwright + jsonwebtoken instalados (REPO=/abs/do/projeto).
const REPO = process.env.REPO || process.cwd();
const { chromium } = require(REPO + '/node_modules/playwright');
const jwt = require(REPO + '/node_modules/jsonwebtoken');
const fs = require('fs'); const path = require('path');

// ===================== CONFIG =====================
const OUT = process.env.SHOTS_OUT || '/tmp/px-deck-shots';
const SECRET = process.env.JWT_SECRET || 'dev-jwt-secret-please-change';   // dev compose default
const TENANT = '00000000-0000-4000-8000-000000000001';                      // tenant px-internal

// um "alvo" por app: base, storageKey, JWT claims, e as rotas a capturar.
const TARGETS = [
  {
    name: 'admin', base: 'http://localhost:5173', storageKey: 'px-agents.admin.jwt',
    claims: { sub: '<ADMIN_USER_ID>', tenantId: TENANT, role: 'PLATFORM_ADMIN', scopes: [] },
    shots: [
      ['admin-01-dashboard', '/admin'],
      ['admin-02-processos', '/admin/lawsuits'],
      // ['admin-03-processo', '/admin/lawsuits/<LAWSUIT_ID>'],
      // ['admin-07-run', '/admin/runs/<RUN_ID>'],
      ['admin-08-cutover', '/admin/cutover'],
    ],
  },
  {
    name: 'portal', base: 'http://localhost:5174', storageKey: 'px-agents.portal.jwt',
    claims: { sub: '<ANALISTA_USER_ID>', tenantId: TENANT, role: 'TENANT_ADMIN',
      scopes: ['lawsuits:read', 'lawsuits:write', 'reports:read', 'reviews:read', 'reviews:write'] },
    shots: [
      ['portal-01-processos', '/processos'],
      ['portal-02-novo', '/processos/novo'],
      // ['portal-03-processo', '/processos/<LAWSUIT_ID>'],
      // ['portal-04-acompanhamento', '/processos/<LAWSUIT_ID>/acompanhamento'],
      ['portal-05-organizacao', '/organizacao'],
    ],
  },
];
// ==================================================

fs.mkdirSync(OUT, { recursive: true });

async function shoot(browser, t) {
  const token = jwt.sign(t.claims, SECRET, { algorithm: 'HS256', expiresIn: '3h' });
  const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 });
  await ctx.addInitScript(([k, v]) => { try { localStorage.setItem(k, v); } catch (e) {} }, [t.storageKey, token]);
  const page = await ctx.newPage();
  for (const [name, route] of t.shots) {
    try {
      await page.goto(t.base + route, { waitUntil: 'domcontentloaded', timeout: 30000 });
      await page.waitForLoadState('networkidle', { timeout: 15000 }).catch(() => {});
      await page.waitForTimeout(2800);  // deixa o React Query hidratar
      await page.screenshot({ path: path.join(OUT, name + '.png') });
      console.log(`OK  ${name}  -> ${page.url().replace(t.base, '')}`);
    } catch (e) { console.log(`ERR ${name}  ${String(e).slice(0, 90)}`); }
  }
  await ctx.close();
}

(async () => {
  const browser = await chromium.launch();
  for (const t of TARGETS) { console.log(`--- ${t.name} ---`); await shoot(browser, t); }
  await browser.close();
  console.log('shots em', OUT, '\nConfira 2-3 com Read antes de embutir (não devem cair em /login nem skeleton).');
})();
