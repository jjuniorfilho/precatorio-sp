// Testes da lógica pura de src/ingest-djen.ts (FOR-146). Roda via `npm test`
// (node:test nativo, sem dependência nova — mesmo padrão de parse.test.ts).
import { test } from "node:test";
import assert from "node:assert/strict";
import { classeOk } from "./ingest-djen.js";

// classesConfig já chega normalizado (map(norm)) na chamada real de ingestDay — os
// testes replicam isso passando as configs em minúsculo/sem acento, como o código faz.
const CLASSES_ORIGINAIS = [
  "cumprimento de sentenca contra a fazenda publica",
  "cumprimento provisorio de sentenca contra a fazenda publica",
  "execucao contra a fazenda publica",
  "precatorio",
  "requisicao de pequeno valor",
  "procedimento do juizado especial da fazenda publica",
].map((s) => s.normalize("NFD").replace(/[̀-ͯ]/g, ""));

test("classeOk: nomeClasse identico a uma config (apos normalizacao) -> passa", () => {
  assert.equal(classeOk("Precatório", CLASSES_ORIGINAIS), true);
  assert.equal(classeOk("Requisição de Pequeno Valor", CLASSES_ORIGINAIS), true);
});

test("classeOk: nomeClasse mais especifico que a config (contem a config + sufixo extra) -> passa", () => {
  assert.equal(
    classeOk("Cumprimento de Sentença contra a Fazenda Pública em Autos Suplementares", CLASSES_ORIGINAIS),
    true,
  );
});

test("classeOk: nomeClasse generico que e prefixo/substring de uma config mais longa (bug FOR-146) -> NAO deve passar", () => {
  // Antes do fix, isso passava só porque a config ("...contra a Fazenda Pública")
  // continha "CUMPRIMENTO DE SENTENÇA" como substring (c.includes(alvo)).
  assert.equal(classeOk("CUMPRIMENTO DE SENTENÇA", CLASSES_ORIGINAIS), false);
  assert.equal(classeOk("CUMPRIMENTO PROVISÓRIO DE SENTENÇA", CLASSES_ORIGINAIS), false);
});

test("classeOk: nomeClasse sem nenhuma relacao com nenhuma config -> nao passa", () => {
  assert.equal(classeOk("Ação de Despejo por Falta de Pagamento", CLASSES_ORIGINAIS), false);
  assert.equal(classeOk(null, CLASSES_ORIGINAIS), false);
  assert.equal(classeOk(undefined, CLASSES_ORIGINAIS), false);
});

test("classeOk: classesConfig vazio -> passa sempre (sem filtro)", () => {
  assert.equal(classeOk("Qualquer Coisa", []), true);
  assert.equal(classeOk(null, []), true);
});

test("classeOk: com as 2 classes genericas da Fase 2 adicionadas, o nomeClasse generico volta a passar", () => {
  const classesComGenericas = [
    ...CLASSES_ORIGINAIS,
    "cumprimento de sentenca",
    "cumprimento provisorio de sentenca",
  ];
  assert.equal(classeOk("CUMPRIMENTO DE SENTENÇA", classesComGenericas), true);
  assert.equal(classeOk("CUMPRIMENTO PROVISÓRIO DE SENTENÇA", classesComGenericas), true);
  // Continua não abrindo brecha para o caso oposto (bug antigo): um nomeClasse que
  // seja só prefixo de uma config ainda não deve passar por acidente de substring.
  assert.equal(classeOk("Execução", classesComGenericas), false);
});

test("classeOk: NAO normaliza classesConfig sozinha (contrato: caller precisa normalizar antes)", () => {
  // classeOk só normaliza `nomeClasse` (via norm(nomeClasse ?? "")); `classesConfig` é
  // usado como veio. Se algum dia o call site em ingestDay parar de fazer
  // `classes_relevantes.map(norm)` antes de chamar classeOk, esse teste falha e denuncia
  // a quebra silenciosa (senão toda a config com acento/maiúscula deixaria de casar).
  assert.equal(classeOk("Precatório", ["Precatório"]), false);
  assert.equal(classeOk("Precatório", ["precatorio"]), true);
});
