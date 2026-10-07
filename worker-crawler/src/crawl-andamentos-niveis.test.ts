// FOR-201 — regressão: quando um cumprimento de sentença (ou a raiz) tem incidente-filho
// REAL, crawlSeed deixava de extrair os andamentos da própria página do cumprimento/raiz —
// só o fazia no caso-limite sem filho nenhum (placeholder, FOR-196). Como a página do
// cumprimento ($c) já é buscada de qualquer forma nesse caso, e a página raiz (root.$) já
// está em memória, o fix não pede nenhuma requisição nova — só para de descartar o parse.
//
// Mesma infra de mock.module de crawl-cumprimento-sintetico.test.ts (ver comentário lá para
// detalhes do flag --experimental-test-module-mocks / Node ≥22.3). Roda via
// `npm run test:module-mocks`, não entra no `npm test` default.
process.env.DELAY_MS = "0";

import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { isCnj, parseCnj, type Session } from "./esaj.js";

const moduleMockDisponivel = typeof (mock as unknown as { module?: unknown }).module === "function";
const skip = moduleMockDisponivel
  ? false
  : "precisa de --experimental-test-module-mocks (Node ≥22.3) — rode `npm run test:module-mocks`";

const SESSION: Session = { csrf: null, cookie: "" };
const SEED = "0001234-56.2020.8.26.0100";
const ROOT_CODIGO = "1H0000ROOT";
const CUMP_CODIGO = "1H0000CUMP";
const INC_CODIGO = "1H0000INC1";
const FORO = "0100";

const movimentacao = (data: string, descricao: string) =>
  `<tr><td class="dataMovimentacao">${data}</td><td>${descricao}</td></tr>`;

const rootHtml = `<html><body>
  <script>saj.env.queryString='processo.codigo=${ROOT_CODIGO}&processo.foro=${FORO}';</script>
  <span id="numeroProcesso">${SEED}</span>
  <a class="incidente" href="show.do?processo.codigo=${CUMP_CODIGO}&amp;processo.foro=${FORO}">Cumprimento de Sentença</a>
  <table id="tabelaTodasMovimentacoes">
    ${movimentacao("01/01/2023", "Distribuído")}
  </table>
</body></html>`;

const cumprimentoHtmlComIncidenteReal = `<html><body>
  <a class="incidente" href="show.do?processo.codigo=${INC_CODIGO}&amp;processo.foro=${FORO}">Precatório - 00001</a>
  <table id="tabelaTodasMovimentacoes">
    ${movimentacao("02/02/2023", "Ofício Requisitório - Cessão de Crédito Homologada")}
  </table>
</body></html>`;

const incidenteHtml = `<html><body>
  <table id="tabelaTodasMovimentacoes">
    ${movimentacao("03/03/2023", "Expedido ofício requisitório")}
  </table>
</body></html>`;

async function crawlSeedComPaginas(porCodigo: Record<string, string>) {
  mock.module("./esaj.js", {
    namedExports: {
      isCnj, parseCnj,
      getSession: async () => SESSION,
      getRequisitorioSession: async () => SESSION,
      searchRequisitorioByCnj: async () => { throw new Error("não usado neste teste"); },
      reqReferer: () => "",
      searchByCnj: async () => porCodigo[ROOT_CODIGO],
      showByCodigo: async (codigo: string) => porCodigo[codigo] ?? "<html><body></body></html>",
    },
  });
  mock.module("./comunica.js", {
    namedExports: {
      normNome: (s: string) => s.trim().toUpperCase(),
      fetchAdvogadosByCnj: async () => new Map(),
    },
  });
  mock.module("./supabase.js", {
    namedExports: { djenAdvogadosByCnj: async () => new Map() },
  });
  const { crawlSeed } = await import(`./crawl.js?t=${Date.now()}-${Math.random()}`);
  return crawlSeed as (seed: string, session?: Session) => ReturnType<typeof import("./crawl.js").crawlSeed>;
}

test(
  "crawlSeed: cumprimento COM incidente-filho real ainda assim persiste os andamentos da própria página (FOR-201)",
  { skip },
  async () => {
    const crawlSeed = await crawlSeedComPaginas({
      [ROOT_CODIGO]: rootHtml,
      [CUMP_CODIGO]: cumprimentoHtmlComIncidenteReal,
      [INC_CODIGO]: incidenteHtml,
    });
    const tree = await crawlSeed(SEED, SESSION);

    assert.equal(tree.cumprimentos.length, 1);
    const cump = tree.cumprimentos[0]!;
    assert.equal(cump.incidentes.length, 1, "incidente-filho real, não placeholder");

    assert.equal(
      tree.andamentos.length, 1,
      "raiz deveria ter seus próprios andamentos capturados mesmo tendo cumprimento",
    );
    assert.equal(tree.andamentos[0]!.descricao, "Distribuído");

    assert.equal(
      cump.andamentos.length, 1,
      "cumprimento com incidente-filho REAL não deveria mais descartar seus próprios andamentos",
    );
    assert.equal(cump.andamentos[0]!.descricao, "Ofício Requisitório - Cessão de Crédito Homologada");

    assert.equal(cump.incidentes[0]!.andamentos.length, 1, "incidente continua com os seus, inalterado");
    assert.equal(cump.incidentes[0]!.andamentos[0]!.descricao, "Expedido ofício requisitório");
  },
);
