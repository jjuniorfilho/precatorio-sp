// FOR-198 — testes do classificador de erro. Mensagens copiadas VERBATIM dos pontos reais de
// `throw` em esaj.ts/pagamentos-tjsp.ts/crawl.ts (não inventadas) — ver comentário em cada caso.
import { test } from "node:test";
import assert from "node:assert/strict";
import { classificarErro, ERRO_CATEGORIAS } from "./erro-categoria.js";

test("rate_limit: HTTP 429 (esaj.ts::fetchHtml, retry esgotado)", () => {
  const err = new Error(
    "fetchHtml falhou após retries: https://esaj.tjsp.jus.br/cpopg/show.do?x :: Error: HTTP 429",
  );
  assert.equal(classificarErro(err), "rate_limit");
});

test("rate_limit: HTTP 503 (5xx — mesmo sinal que pareceSessaoMorta já trata)", () => {
  const err = new Error("HTTP 503");
  assert.equal(classificarErro(err), "rate_limit");
});

test("captcha: captcha não resolvido após N tentativas (pagamentos-tjsp.ts::consultarInterno)", () => {
  const err = new Error("consultarPagamentos: captcha não resolvido após 4 tentativas");
  assert.equal(classificarErro(err), "captcha");
});

test("captcha: imagem do captcha não encontrada (pagamentos-tjsp.ts::tentarBusca)", () => {
  const err = new Error("imagem do captcha não encontrada");
  assert.equal(classificarErro(err), "captcha");
});

test("timeout: Playwright 'Timeout Nms exceeded' (page.waitForURL)", () => {
  const err = new Error('page.waitForURL: Timeout 25000ms exceeded.\n=========================== logs ===========================');
  assert.equal(classificarErro(err), "timeout");
});

test("timeout: AbortSignal.timeout do undici (esaj.ts fetchHtml, timeout de requisição)", () => {
  const err = new Error("This operation was aborted due to timeout");
  assert.equal(classificarErro(err), "timeout");
});

test("site_indisponivel: browser/contexto fechado (crash documentado — VPS com pouca memória)", () => {
  const err = new Error("Target page, context or browser has been closed");
  assert.equal(classificarErro(err), "site_indisponivel");
});

test("site_indisponivel: conexão recusada (rede indisponível)", () => {
  const err = new Error("connect ECONNREFUSED 200.144.1.1:443");
  assert.equal(classificarErro(err), "site_indisponivel");
});

test("bloqueio_suspeito: flag explícita do chamador (200 OK sem conteúdo esperado) vence qualquer regex", () => {
  // mensagem deliberadamente genérica — a categoria vem só da flag, não de inferência textual
  const err = new Error("link de Pagamentos Precatórios não encontrado no menu");
  assert.equal(classificarErro(err, { conteudoInesperado: true }), "bloqueio_suspeito");
});

test("bloqueio_suspeito: ambíguo real do e-SAJ (crawl.ts::crawlSeed, ANTES da última tentativa)", () => {
  const err = new Error('busca não retornou página de detalhe para seed=1234567 :: corpo=""');
  assert.equal(classificarErro(err, { conteudoInesperado: true, naoEncontrado: false }), "bloqueio_suspeito");
});

test("cnj_nao_encontrado: naoEncontrado vence conteudoInesperado (mesmo erro ambíguo, ÚLTIMA tentativa)", () => {
  const err = new Error('busca não retornou página de detalhe para seed=1234567 :: corpo=""');
  assert.equal(classificarErro(err, { conteudoInesperado: true, naoEncontrado: true }), "cnj_nao_encontrado");
});

test("outro: falha de persistência no banco (bug interno, não é nenhuma das 6 categorias externas)", () => {
  const err = new Error("persistência falhou (falha ao gravar o resultado no banco)");
  assert.equal(classificarErro(err), "outro");
});

test("outro: ícone 'Selecionar' não encontrado na grade (anomalia específica de extração, não bloqueio genérico)", () => {
  const err = new Error('ícone "Selecionar" da grade não encontrado');
  assert.equal(classificarErro(err), "outro");
});

test("outro: erro sem Error (string crua) cai no default seguro", () => {
  assert.equal(classificarErro("alguma coisa totalmente inesperada"), "outro");
});

test("aceita valor não-Error (ex.: string lançada) sem lançar", () => {
  assert.doesNotThrow(() => classificarErro("erro cru"));
});

test("ERRO_CATEGORIAS lista as 7 categorias, sem duplicatas", () => {
  assert.equal(ERRO_CATEGORIAS.length, 7);
  assert.equal(new Set(ERRO_CATEGORIAS).size, 7);
});
