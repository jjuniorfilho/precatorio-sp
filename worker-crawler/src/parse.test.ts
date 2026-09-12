// Testes da lógica pura de src/parse.ts. Roda via `npm test` (node:test nativo, sem
// dependência nova — ver README.md).
import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyEsfera, extractOrigemInfo, extractOrigemCnjs, load } from "./parse.js";

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

// FOR-156 — regressão do achado real em 0003201-62.2017.8.26.0500: "Processo de Origem:
// CNJ/NNNN" traz o número do incidente de origem (qual "Precatório - 0000X" gerou esse
// .0500) — sem capturar esse sufixo não dá pra saber qual dos vários incidentes da mesma
// ação corresponde a este requisitório específico.
test("extractOrigemInfo: captura o sufixo /NNNN de 'Processo de Origem: CNJ/NNNN'", () => {
  const $ = load(`<body>
    Remetido ao DJE
    Relação: 0011/2025 Teor do ato: Processo de Origem: 0410665-90.1996.8.26.0053/0001
    Unidade de Processamento das Execuções contra a Fazenda Pública
  </body>`);
  assert.deepEqual(extractOrigemInfo($), [
    { cnj: "0410665-90.1996.8.26.0053", numeroIncidente: "0001" },
  ]);
});

test("extractOrigemInfo: sem sufixo (ex.: 'Outros números' da capa) -> numeroIncidente null", () => {
  const $ = load(`<body>Outros números: 0001234-56.2020.8.26.0100</body>`);
  assert.deepEqual(extractOrigemInfo($), [
    { cnj: "0001234-56.2020.8.26.0100", numeroIncidente: null },
  ]);
});

test("extractOrigemInfo: dedup por CNJ preferindo a ocorrência com sufixo", () => {
  const $ = load(`<body>
    Outros números: 0410665-90.1996.8.26.0053
    Processo de Origem: 0410665-90.1996.8.26.0053/0003
  </body>`);
  assert.deepEqual(extractOrigemInfo($), [
    { cnj: "0410665-90.1996.8.26.0053", numeroIncidente: "0003" },
  ]);
});

test("extractOrigemInfo: exclui o próprio .0500 do texto", () => {
  const $ = load(`<body>0003201-62.2017.8.26.0500 Processo de Origem: 0410665-90.1996.8.26.0053/0001</body>`);
  assert.deepEqual(extractOrigemInfo($), [
    { cnj: "0410665-90.1996.8.26.0053", numeroIncidente: "0001" },
  ]);
});

test("extractOrigemCnjs: continua devolvendo só os CNJs, sem o sufixo (compat)", () => {
  const $ = load(`<body>Processo de Origem: 0410665-90.1996.8.26.0053/0001</body>`);
  assert.deepEqual(extractOrigemCnjs($), ["0410665-90.1996.8.26.0053"]);
});
