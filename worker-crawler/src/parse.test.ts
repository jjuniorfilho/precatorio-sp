// Testes da lógica pura de src/parse.ts. Roda via `npm test` (node:test nativo, sem
// dependência nova — ver README.md).
import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyEsfera } from "./parse.js";

test("classifyEsfera: tokens estaduais originais", () => {
  assert.equal(classifyEsfera("FAZENDA PUBLICA DO ESTADO DE SAO PAULO"), "Estadual");
  assert.equal(classifyEsfera("GOVERNO DO ESTADO DE SAO PAULO"), "Estadual");
  assert.equal(classifyEsfera("DER - DEPARTAMENTO DE ESTRADAS DE RODAGEM"), "Estadual");
  assert.equal(classifyEsfera("SPPREV"), "Estadual");
});

test("classifyEsfera: tokens municipais originais", () => {
  assert.equal(classifyEsfera("PREFEITURA MUNICIPAL DE CAMPINAS"), "Municipal");
  assert.equal(classifyEsfera("FAZENDA PUBLICA MUNICIPAL DE SANTOS"), "Municipal");
  assert.equal(classifyEsfera("CAMARA MUNICIPAL DE SOROCABA"), "Municipal");
});

test("classifyEsfera: sem match nenhum -> Outro", () => {
  assert.equal(classifyEsfera("BANCO DO BRASIL S.A."), "Outro");
  assert.equal(classifyEsfera(null), "Outro");
  assert.equal(classifyEsfera(""), "Outro");
});

// FOR-143 — acrônimos/autarquias adicionados a partir do dump legado (ver diff de
// classifyEsfera em parse.ts).
test("classifyEsfera: acrônimos estaduais novos (FOR-143)", () => {
  for (const nome of ["USP", "UNESP", "UNICAMP", "IAMSPE", "DETRAN", "ARTESP", "CEETEPS", "FDE", "FURP", "SUCEN", "ITESP", "JUCESP", "DAEE", "DERSA", "PROCON"]) {
    assert.equal(classifyEsfera(nome), "Estadual", `esperava Estadual para "${nome}"`);
  }
  assert.equal(classifyEsfera("FUNDACAO CASA"), "Estadual");
  assert.equal(classifyEsfera("HOSPITAL DAS CLINICAS DA FMUSP"), "Estadual");
  assert.equal(classifyEsfera("FAMEMA"), "Estadual");
  assert.equal(classifyEsfera("HCFAMEMA"), "Estadual");
});

test("classifyEsfera: tokens 'ESTADUAL'/'MUNICIPAL' soltos (sem 'ESTADO'/'MUNICÍPIO' por extenso, FOR-143)", () => {
  assert.equal(classifyEsfera("INSTITUTO ESTADUAL DE PREVIDENCIA"), "Estadual");
  assert.equal(classifyEsfera("INSTITUTO MUNICIPAL DE PREVIDENCIA"), "Municipal");
});

test("classifyEsfera: SPTrans/SP-Urbanismo -> Municipal (FOR-143)", () => {
  assert.equal(classifyEsfera("SPTRANS"), "Municipal");
  assert.equal(classifyEsfera("SP-URBANISMO"), "Municipal");
  assert.equal(classifyEsfera("SAO PAULO URBANISMO"), "Municipal");
});

// Regressão do bug documentado em plan.md (FASE 2): a primeira tentativa colocou "MUN\." dentro
// do mesmo grupo `\b(...)\b` dos outros tokens, mas `\b` logo depois de "." nunca casa quando
// seguido de espaço — esse token nunca funcionava até virar um regex separado
// `/\bMUN\.\s*DE\b/`. Trava essa forma abreviada como regressão.
test("classifyEsfera: 'MUN. DE <cidade>' (abreviação) -> Municipal (regressão FASE 2)", () => {
  assert.equal(classifyEsfera("INSTITUTO DE PREVIDENCIA MUN. DE SOROCABA"), "Municipal");
  assert.equal(classifyEsfera("MUN. DE CAMPINAS"), "Municipal");
});

test("classifyEsfera: case-insensitive (lowercase/misto também classifica)", () => {
  assert.equal(classifyEsfera("prefeitura municipal de são paulo"), "Municipal");
  assert.equal(classifyEsfera("Fazenda Pública do Estado de São Paulo"), "Estadual");
});
