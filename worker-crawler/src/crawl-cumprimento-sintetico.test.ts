// FOR-196 — regressão: o cumprimento "sintético" (execução correndo direto na raiz, sem CNJ
// próprio — ver isCumprimento/directIncidentLinks em crawl.ts) gravava `cnj: null` em vez do
// CNJ da própria raiz (`capa.cnj`, já extraído por extractCapa). Isso deixava "Cumprimento de
// Sentença" em branco em 347.482 incidentes (quase metade da base). Correção: `cnj: capa.cnj`
// nas duas ramificações que criam o cumprimento sintético (linha 141: incidentes pendurados
// direto na raiz; linhas 148-149: raiz sem incidente nenhum, só placeholder).
//
// crawlSeed fala com a rede via esaj.js/comunica.js/supabase.js — aqui essas três dependências
// são substituídas via `mock.module` (node:test; precisa do flag --experimental-test-module-
// mocks, só em Node ≥22.3 — o projeto declara "engines": ">=20"/README "Node ≥20" para o
// `npm test` default, então NÃO mexemos nesse script nem no piso de versão). A extração em si
// (parse.ts) continua real e já é coberta por parse.test.ts; o alvo aqui é a ORQUESTRAÇÃO em
// crawl.ts. Rode explicitamente com `npm run test:module-mocks` (script novo, não entra no
// `npm test` default). Sob `npm test` normal (sem o flag), os testes abaixo se auto-detectam
// e pulam (skip) em vez de falhar — mock.module só existe com o flag ativo.
process.env.DELAY_MS = "0"; // sem throttle real entre os fetches mockados

import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { isCnj, parseCnj, type Session } from "./esaj.js";

const moduleMockDisponivel = typeof (mock as unknown as { module?: unknown }).module === "function";
const skip = moduleMockDisponivel
  ? false
  : "precisa de --experimental-test-module-mocks (Node ≥22.3) — rode `npm run test:module-mocks`";

const SESSION: Session = { csrf: null, cookie: "" };
const SEED = "0001234-56.2020.8.26.0100"; // CNJ da raiz (seed = o próprio CNJ)
const ROOT_CODIGO = "1H0000ROOT";
const FORO = "0100";

const rootHtmlComIncidenteDireto = `<html><body>
  <script>saj.env.queryString='processo.codigo=${ROOT_CODIGO}&processo.foro=${FORO}';</script>
  <span id="numeroProcesso">${SEED}</span>
  <a class="incidente" href="show.do?processo.codigo=1H0000INC1&amp;processo.foro=${FORO}">Precatório - 00001</a>
</body></html>`;

const rootHtmlSemNada = `<html><body>
  <script>saj.env.queryString='processo.codigo=${ROOT_CODIGO}&processo.foro=${FORO}';</script>
  <span id="numeroProcesso">${SEED}</span>
</body></html>`;

const incidenteHtmlVazio = `<html><body></body></html>`;

/** Reinstala os 3 mocks de rede para o cenário do teste e devolve um crawlSeed "fresco"
 * (query string cache-busting força o re-import do grafo de crawl.ts com os mocks atuais).
 * `mock.module` recusa mockar o mesmo specifier duas vezes ("already mocked") — por isso
 * cada chamada primeiro restaura os mocks da chamada anterior (no-op na primeira vez). */
let mocksAtivos: Array<{ restore(): void }> = [];
async function crawlSeedComRoot(rootHtml: string) {
  for (const m of mocksAtivos) m.restore();
  mocksAtivos = [];
  mocksAtivos.push(mock.module("./esaj.js", {
    namedExports: {
      isCnj, parseCnj,
      getSession: async () => SESSION,
      getRequisitorioSession: async () => SESSION,
      searchRequisitorioByCnj: async () => { throw new Error("não usado neste teste"); },
      reqReferer: () => "",
      searchByCnj: async () => rootHtml,
      showByCodigo: async (codigo: string) => (codigo === ROOT_CODIGO ? rootHtml : incidenteHtmlVazio),
    },
  }));
  mocksAtivos.push(mock.module("./comunica.js", {
    namedExports: {
      normNome: (s: string) => s.trim().toUpperCase(),
      fetchAdvogadosByCnj: async () => new Map(),
    },
  }));
  mocksAtivos.push(mock.module("./supabase.js", {
    namedExports: { djenAdvogadosByCnj: async () => new Map() },
  }));
  const { crawlSeed } = await import(`./crawl.js?t=${Date.now()}-${Math.random()}`);
  return crawlSeed as (seed: string, session?: Session) => ReturnType<typeof import("./crawl.js").crawlSeed>;
}

test("crawlSeed: cumprimento sintético (incidentes pendurados direto na raiz) grava cnj = capa.cnj, não null (FOR-196)", { skip }, async () => {
  const crawlSeed = await crawlSeedComRoot(rootHtmlComIncidenteDireto);
  const tree = await crawlSeed(SEED, SESSION);
  assert.equal(tree.cnj, SEED);
  assert.equal(tree.cumprimentos.length, 1);
  assert.equal(tree.cumprimentos[0]!.processo_codigo, `${ROOT_CODIGO}#cumprimento`);
  assert.equal(
    tree.cumprimentos[0]!.cnj,
    SEED,
    "cumprimento sintético deveria herdar o CNJ da raiz (capa.cnj) — regressão FOR-196 gravava null",
  );
  assert.equal(tree.cumprimentos[0]!.incidentes.length, 1);
});

test("crawlSeed: raiz sem incidente nenhum (placeholder) também grava cnj = capa.cnj, não null (FOR-196)", { skip }, async () => {
  const crawlSeed = await crawlSeedComRoot(rootHtmlSemNada);
  const tree = await crawlSeed(SEED, SESSION);
  assert.equal(tree.cumprimentos.length, 1);
  assert.equal(tree.cumprimentos[0]!.processo_codigo, `${ROOT_CODIGO}#cumprimento`);
  assert.equal(
    tree.cumprimentos[0]!.cnj,
    SEED,
    "placeholder de raiz sem nada também deveria herdar capa.cnj — regressão FOR-196 gravava null",
  );
});
