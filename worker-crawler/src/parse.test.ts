// Testes da lógica pura de src/parse.ts. Roda via `npm test` (node:test nativo, sem
// dependência nova — ver README.md).
import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyEsfera, extractOrigemInfo, extractOrigemCnjs, extractPartes, load, temAcordoHomologado } from "./parse.js";

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

// Regressão: credores conjuntos (comum em ação coletiva) geram várias linhas
// "Exeqte/Reqte" na mesma #tablePartesPrincipais. A implementação original fazia
// `ativa = {...}` (reatribuição) dentro do loop — cada linha nova sobrescrevia a
// anterior, então só o último credor (e seu advogado) sobrevivia, mesmo com
// múltiplos credores/advogados distintos na página. extractPartes agora acumula.
test("extractPartes: credores conjuntos — acumula todas as linhas 'ativa', não só a última", () => {
  const $ = load(`<body><table id="tablePartesPrincipais">
    <tr><td class="label">Exequente:</td><td>Maria da Silva
    <span>Advogado:</span> Fulano de Tal OAB: 111111/SP</td></tr>
    <tr><td class="label">Exequente:</td><td>João Souza
    <span>Advogado:</span> Ciclano Pereira OAB: 222222/SP</td></tr>
    <tr><td class="label">Reqdo:</td><td>MUNICÍPIO DE SÃO PAULO</td></tr>
  </table></body>`);
  const { ativas, passiva } = extractPartes($);
  assert.equal(ativas.length, 2, "esperava 2 credores, um por linha 'Exequente'");
  assert.equal(ativas[0]!.nome, "Maria da Silva");
  assert.equal(ativas[0]!.advogados[0]!.nome, "Fulano de Tal");
  assert.equal(ativas[0]!.advogados[0]!.oab_normalizada, "111111SP");
  assert.equal(ativas[1]!.nome, "João Souza");
  assert.equal(ativas[1]!.advogados[0]!.nome, "Ciclano Pereira");
  assert.equal(ativas[1]!.advogados[0]!.oab_normalizada, "222222SP");
  assert.equal(passiva?.nome, "MUNICÍPIO DE SÃO PAULO");
});

test("extractPartes: um único credor continua funcionando (caso comum)", () => {
  const $ = load(`<body><table id="tablePartesPrincipais">
    <tr><td class="label">Reqte:</td><td>Maria da Silva<br/><span>Advogado:</span> Fulano de Tal OAB: 111111/SP</td></tr>
    <tr><td class="label">Reqdo:</td><td>FAZENDA PUBLICA DO ESTADO DE SAO PAULO</td></tr>
  </table></body>`);
  const { ativas } = extractPartes($);
  assert.equal(ativas.length, 1);
  assert.equal(ativas[0]!.advogados.length, 1);
});

// FOR-159 — djen_depre.acordo_homologado é calculado a partir da ficha inteira do
// .0500 (Movimentação + Petições diversas mescladas). false aqui tem que significar
// "verificado, não achou" (não "não verificado ainda" — essa distinção é feita por
// fora, comparando ficha_crawled_at, não pelo retorno desta função).
test("temAcordoHomologado: acha o andamento na lista mesclada", () => {
  const andamentos = [
    { data: "2023-01-26", descricao: "Atualização das informações bancárias - DEPRE", arquivo_url: null },
    { data: "2026-07-30", descricao: "Comunicado de Acordo de Requisitório", arquivo_url: null },
    { data: "2026-08-26", descricao: "Atualização das informações bancárias - DEPRE", arquivo_url: null },
  ];
  assert.equal(temAcordoHomologado(andamentos), true);
});

test("temAcordoHomologado: outros andamentos presentes, mas não esse -> false", () => {
  const andamentos = [
    { data: "2023-01-26", descricao: "Atualização das informações bancárias - DEPRE", arquivo_url: null },
    { data: "2024-05-10", descricao: "Certidão de Objeto e Pé expedida", arquivo_url: null },
  ];
  assert.equal(temAcordoHomologado(andamentos), false);
});

test("temAcordoHomologado: lista vazia -> false (verificado, não achou)", () => {
  assert.equal(temAcordoHomologado([]), false);
});

test("temAcordoHomologado: não confunde com frase genérica 'de acordo com' (falso positivo já visto nesta investigação)", () => {
  const andamentos = [
    { data: "2024-01-01", descricao: "Manifestação da parte, de acordo com o despacho anterior", arquivo_url: null },
  ];
  assert.equal(temAcordoHomologado(andamentos), false);
});
