// FOR-195 — fetchProcessoPrincipal (crawl.ts): busca só a página indicada (sem climb, sem
// árvore) e segue a.processoPrinc pra achar a AÇÃO PRINCIPAL REAL acima do cumprimento, pros
// ~11.202 `processos` legado (ver backfill-legado-cumprimento-principal.ts).
//
// Caso real: página do cumprimento 0018028-13.2022.8.26.0562 (código interno 1H0000CUMP) linka
// via a.processoPrinc pra 1000594-91.2022.8.26.0562 (código interno 1H0000PRINC).
//
// fetchProcessoPrincipal fala com a rede via esaj.js — aqui substituída via `mock.module`
// (node:test; precisa de --experimental-test-module-mocks, Node ≥22.3 — mesmo padrão
// introduzido em crawl-cumprimento-sintetico.test.ts pro FOR-196). Rode explicitamente com
// `npm run test:module-mocks`. Sob `npm test` normal (sem o flag), os testes abaixo se
// auto-detectam e pulam.
process.env.DELAY_MS = "0"; // sem throttle real entre os 2 fetches mockados

import { test, mock } from "node:test";
import assert from "node:assert/strict";
import { isCnj as isCnjReal, parseCnj as parseCnjReal, type Session } from "./esaj.js";

const moduleMockDisponivel = typeof (mock as unknown as { module?: unknown }).module === "function";
const skip = moduleMockDisponivel
  ? false
  : "precisa de --experimental-test-module-mocks (Node ≥22.3) — rode `npm run test:module-mocks`";

const SESSION: Session = { csrf: null, cookie: "" };
const FORO_CUMP = "0562";
const CUMP_CODIGO = "1H0000CUMP";
const PRINC_CODIGO = "1H0000PRINC";
const CNJ_PRINCIPAL = "1000594-91.2022.8.26.0562";
const CNJ_CUMPRIMENTO = "0018028-13.2022.8.26.0562";

const htmlCumprimentoComLink = `<html><body>
  <a class="processoPrinc" href="show.do?processo.codigo=${PRINC_CODIGO}&amp;processo.foro=${FORO_CUMP}">${CNJ_PRINCIPAL}</a>
</body></html>`;

const htmlCumprimentoSemLink = `<html><body>
  <span id="numeroProcesso">${CNJ_CUMPRIMENTO}</span>
</body></html>`;

const htmlPrincipal = `<html><body>
  <span id="numeroProcesso">${CNJ_PRINCIPAL}</span>
  <span id="classeProcesso">Procedimento Comum Cível</span>
  <table id="tablePartesPrincipais">
    <tr><td class="label">Reqte:</td><td>CREDOR DA AÇÃO PRINCIPAL</td></tr>
    <tr><td class="label">Reqdo:</td><td>FAZENDA PUBLICA DO ESTADO DE SAO PAULO</td></tr>
  </table>
</body></html>`;

// Caminho por CNJ (FOR-195, achado do code-review: ~98% da população real só tem o cnj
// conhecido, não um código e-SAJ — ver backfill-legado-cumprimento-principal.ts). A busca por CNJ
// cai direto na ficha do cumprimento (com os marcadores de `selfCodigo`, diferente de uma lista de
// resultados) — já contém o link pra ação principal.
const htmlCumprimentoViaCnjComLink = `<html><body>
  <input type="hidden" name="processo.codigo" value="${CUMP_CODIGO}">
  <input type="hidden" name="processo.foro" value="${FORO_CUMP}">
  <a class="processoPrinc" href="show.do?processo.codigo=${PRINC_CODIGO}&amp;processo.foro=${FORO_CUMP}">${CNJ_PRINCIPAL}</a>
</body></html>`;

// Busca por CNJ cai numa lista de resultados em vez da ficha direta (sem marcadores de
// `selfCodigo`) — a blindagem segue o 1º link de processo da lista.
const htmlListaDeResultados = `<html><body>
  <a href="show.do?processo.codigo=${CUMP_CODIGO}&amp;processo.foro=${FORO_CUMP}">${CNJ_CUMPRIMENTO}</a>
</body></html>`;

let mocksAtivos: Array<{ restore(): void }> = [];
/** Reinstala o mock de esaj.js para o cenário do teste e devolve um fetchProcessoPrincipal
 * "fresco" (query string cache-busting força o re-import de crawl.ts com o mock atual —
 * mock.module recusa mockar o mesmo specifier 2x, por isso cada chamada restaura a anterior).
 * `isCnj`/`parseCnj` são os REAIS (regex puro, sem rede) — necessário pro caminho por CNJ
 * (FOR-195) funcionar nos testes exatamente como em produção; só `porCodigo`/`porCnj` (as
 * páginas servidas por `showByCodigo`/`searchByCnj`) são fake. */
async function fetchProcessoPrincipalComPaginas(porCodigo: Record<string, string>, porCnj: Record<string, string> = {}) {
  for (const m of mocksAtivos) m.restore();
  mocksAtivos = [];
  mocksAtivos.push(mock.module("./esaj.js", {
    namedExports: {
      showByCodigo: async (codigo: string) => {
        const html = porCodigo[codigo];
        if (!html) throw new Error(`showByCodigo inesperado no teste: ${codigo}`);
        return html;
      },
      searchByCnj: async (cnj: string) => {
        const html = porCnj[cnj];
        if (!html) throw new Error(`searchByCnj inesperado no teste: ${cnj}`);
        return html;
      },
      // não usados por fetchProcessoPrincipal, mas crawl.ts importa do mesmo módulo.
      getSession: async () => SESSION,
      getRequisitorioSession: async () => SESSION,
      searchRequisitorioByCnj: async () => { throw new Error("não usado neste teste"); },
      reqReferer: () => "",
      isCnj: isCnjReal,
      parseCnj: parseCnjReal,
    },
  }));
  const { fetchProcessoPrincipal } = await import(`./crawl.js?t=${Date.now()}-${Math.random()}`);
  return fetchProcessoPrincipal as typeof import("./crawl.js").fetchProcessoPrincipal;
}

test("fetchProcessoPrincipal: achou a.processoPrinc -> busca a 2ª página e devolve a capa da ação principal", { skip }, async () => {
  const fetchProcessoPrincipal = await fetchProcessoPrincipalComPaginas({
    [CUMP_CODIGO]: htmlCumprimentoComLink,
    [PRINC_CODIGO]: htmlPrincipal,
  });
  const info = await fetchProcessoPrincipal(CUMP_CODIGO, FORO_CUMP, SESSION);
  assert.ok(info, "deveria ter achado a ação principal");
  assert.equal(info!.processo_codigo, PRINC_CODIGO);
  assert.equal(info!.cnj, CNJ_PRINCIPAL);
  assert.equal(info!.classe, "Procedimento Comum Cível");
  assert.equal(info!.ente_nome, "FAZENDA PUBLICA DO ESTADO DE SAO PAULO");
  assert.equal(info!.ente_esfera, "Estadual");
  assert.equal(info!.flag_sp, true);
});

test("fetchProcessoPrincipal: sem a.processoPrinc -> null, SEM buscar 2ª página (já é raiz, regra da FOR-196)", { skip }, async () => {
  // só CUMP_CODIGO no mapa: se o código tentasse buscar qualquer outra página (ex.: a
  // principal, por engano), showByCodigo lançaria "showByCodigo inesperado no teste" e o
  // teste falharia — não precisa de um contador/flag separado.
  const fetchProcessoPrincipal = await fetchProcessoPrincipalComPaginas({
    [CUMP_CODIGO]: htmlCumprimentoSemLink,
  });
  const info = await fetchProcessoPrincipal(CUMP_CODIGO, FORO_CUMP, SESSION);
  assert.equal(info, null);
});

test("fetchProcessoPrincipal: seed é CNJ (caminho de ~98% da população real) -> searchByCnj, acha o link direto na ficha", { skip }, async () => {
  const fetchProcessoPrincipal = await fetchProcessoPrincipalComPaginas(
    { [PRINC_CODIGO]: htmlPrincipal },
    { [CNJ_CUMPRIMENTO]: htmlCumprimentoViaCnjComLink },
  );
  const info = await fetchProcessoPrincipal(CNJ_CUMPRIMENTO, "", SESSION);
  assert.ok(info, "deveria ter achado a ação principal a partir do CNJ");
  assert.equal(info!.processo_codigo, PRINC_CODIGO);
  assert.equal(info!.cnj, CNJ_PRINCIPAL);
});

test("fetchProcessoPrincipal: seed é CNJ e a busca cai numa lista de resultados -> segue o 1º link (blindagem igual normalizeToRoot)", { skip }, async () => {
  const fetchProcessoPrincipal = await fetchProcessoPrincipalComPaginas(
    { [CUMP_CODIGO]: htmlCumprimentoComLink, [PRINC_CODIGO]: htmlPrincipal },
    { [CNJ_CUMPRIMENTO]: htmlListaDeResultados },
  );
  const info = await fetchProcessoPrincipal(CNJ_CUMPRIMENTO, "", SESSION);
  assert.ok(info, "deveria ter seguido a lista até achar a ação principal");
  assert.equal(info!.processo_codigo, PRINC_CODIGO);
  assert.equal(info!.cnj, CNJ_PRINCIPAL);
});

test("fetchProcessoPrincipal: seed é CNJ, não encontrado no e-SAJ (sem link nenhum na lista) -> null", { skip }, async () => {
  const fetchProcessoPrincipal = await fetchProcessoPrincipalComPaginas(
    {},
    { [CNJ_CUMPRIMENTO]: "<html><body>nenhum resultado</body></html>" },
  );
  const info = await fetchProcessoPrincipal(CNJ_CUMPRIMENTO, "", SESSION);
  assert.equal(info, null);
});
