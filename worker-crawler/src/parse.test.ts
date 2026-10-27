// Testes da lógica pura de src/parse.ts. Roda via `npm test` (node:test nativo, sem
// dependência nova — ver README.md).
import { test } from "node:test";
import assert from "node:assert/strict";
import { classifyEsfera, extractOrigemInfo, extractOrigemCnjs, extractPartes, temAcordoHomologado, extractAndamentos, extractPeticoesDiversas, extractMovimentacoesAjax, movimentacoesViaAjax, classificarAcordoHomologado, fichaSemConteudo, buscaRequisitorioUtil, processoPrincLink, codigoForoFromHref, load } from "./parse.js";

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

// FOR-195 — processoPrincLink/codigoForoFromHref não tinham cobertura (usados dentro de
// normalizeToRoot desde o início do crawler, e agora também por fetchProcessoPrincipal em
// crawl.ts). Caso real: página do cumprimento 0018028-13.2022.8.26.0562 linkando de volta pra
// ação principal 1000594-91.2022.8.26.0562.
test("codigoForoFromHref: extrai codigo/foro de um href show.do, decodificando %2E etc.", () => {
  const href = "show.do?processo.codigo=1H0000PRINC&processo.foro=0562";
  assert.deepEqual(codigoForoFromHref(href), { codigo: "1H0000PRINC", foro: "0562" });
});

test("codigoForoFromHref: foro ausente vira string vazia (não undefined/null) quando só há codigo", () => {
  const href = "show.do?processo.codigo=1H0000PRINC";
  assert.deepEqual(codigoForoFromHref(href), { codigo: "1H0000PRINC", foro: "" });
});

test("codigoForoFromHref: href undefined/vazio -> null", () => {
  assert.equal(codigoForoFromHref(undefined), null);
  assert.equal(codigoForoFromHref(""), null);
});

test("processoPrincLink: página do cumprimento com a.processoPrinc -> {codigo, foro} da ação principal", () => {
  const $ = load(`<html><body>
    <a class="processoPrinc" href="show.do?processo.codigo=1H0000PRINC&amp;processo.foro=0562">1000594-91.2022.8.26.0562</a>
  </body></html>`);
  assert.deepEqual(processoPrincLink($), { codigo: "1H0000PRINC", foro: "0562" });
});

test("processoPrincLink: página sem a.processoPrinc -> null (já é a raiz, mesma regra da FOR-196)", () => {
  const $ = load(`<html><body><span id="numeroProcesso">1000594-91.2022.8.26.0562</span></body></html>`);
  assert.equal(processoPrincLink($), null);
});

test("processoPrincLink: 2+ links a.processoPrinc na página -> usa o PRIMEIRO (mesma convenção de .first() usada pro resto do parser)", () => {
  const $ = load(`<html><body>
    <a class="processoPrinc" href="show.do?processo.codigo=1H0000PRINC&amp;processo.foro=0562">principal</a>
    <a class="processoPrinc" href="show.do?processo.codigo=1H0000OUTRO&amp;processo.foro=0100">outro</a>
  </body></html>`);
  assert.deepEqual(processoPrincLink($), { codigo: "1H0000PRINC", foro: "0562" });
});

// Regra de acordo homologado: frase de homologação do juiz na ficha do .0500, não o
// comunicado de acordo (petição). Textos reais do 7009845-09.2011.8.26.0500.
const and = (descricao: string) => ({ data: null, descricao, arquivo_url: null });

test("temAcordoHomologado: decisão publicável com 'Homologo o acordo'", () => {
  assert.equal(temAcordoHomologado([and("DEPRE Decisão Publicável Processo de Origem: 0414235-79.1999.8.26.0053 Vistos. Páginas 972/1011: Homologo o acordo, celebrado entre as partes, nos seguintes termos: Beneficiário: Asthor")]), true);
  assert.equal(temAcordoHomologado([and("Remetido ao DJE Relação: 2152/2026 Teor do ato: Vistos. Homologo o acordo, celebrado entre as partes. Homologo o acordo, celebrado")]), true);
  assert.equal(temAcordoHomologado([and("Vistos. Homologo os acordos celebrados entre as partes.")]), true);
});

test("temAcordoHomologado: comunicado de acordo (petição) NÃO prova homologação", () => {
  assert.equal(temAcordoHomologado([and("Comunicado de Acordo de Requisitório")]), false);
});

test("temAcordoHomologado: boilerplate de pagamento ('texto de acordo celebrado') não conta", () => {
  assert.equal(temAcordoHomologado([and("mesmo que tenham sido informados por ocasião do ofício requisitório ou do texto de acordo celebrado, é obrigatório que novamente")]), false);
  assert.equal(temAcordoHomologado([and("Ofício - Cart.Dig. Acordo - Juízo - DEPRE1")]), false);
});

test("temAcordoHomologado: negações e acordo de compensação ficam de fora", () => {
  assert.equal(temAcordoHomologado([and("Vistos. Não homologo o acordo, subscrito pelo Dr. Fulano.")]), false);
  assert.equal(temAcordoHomologado([and("Vistos. Deixo de homologar o acordo celebrado entre as partes.")]), false);
  assert.equal(temAcordoHomologado([and("Vistos. Homologo os acordos de compensação celebrados entre as partes.")]), false);
  assert.equal(temAcordoHomologado([]), false);
});

// Layout atual da ficha do .0500: movimentações paginadas por cursor (carregarMovimentacoesAjax.do).
// Marcação das linhas copiada de uma ficha real; textos encurtados/anonimizados.
const linha = (data: string, titulo: string, teor = "", cls = "fundoClaro") => `
  <tr class="${cls} containerMovimentacao"><td class="dataMovimentacao" width="120">${data}</td><td width="20"></td>
  <td class="descricaoMovimentacao"><a class="linkMovVincProc" href="#liberarAutoPorSenha">${titulo}</a><br><span style="font-style: italic;">${teor}</span></td></tr>`;

test("extractAndamentos: lê 1ª página + outras páginas do layout paginado; ignora a linha de cursor", () => {
  const $ = load(`<table><tbody id="tabelaPrimeiraPaginaMovimentacoes">${linha("13/10/2026", "Petição Juntada")}</tbody>
    <tbody id="tabelaOutrasPaginasMovimentacoes">${linha("14/09/2026", "DEPRE Decisão Publicável", "Vistos. Homologo o acordo, celebrado entre as partes.")}
    <tr id="trCursorMovimentacoes" data-cursor="abc"><td></td></tr></tbody></table>
    <input type="hidden" id="cursorMovimentacoesPaginado" value="abc">`);
  const a = extractAndamentos($);
  assert.equal(a.length, 2);
  assert.equal(a[1]!.data, "2026-09-14");
  assert.match(a[1]!.descricao, /^DEPRE Decisão Publicável Vistos\. Homologo o acordo/);
  assert.equal(movimentacoesViaAjax($), true);
  assert.equal(temAcordoHomologado(a), true);
});

test("movimentacoesViaAjax: página só com o botão 'Exibir movimentações' (HTML inicial do .0500)", () => {
  const $ = load(`<div id="containerMovimentacoes"><div id="containerExibirMovimentacoes"><button id="btnExibirMovimentacoes">Exibir movimentações</button></div></div>`);
  assert.deepEqual(extractAndamentos($), []);
  assert.equal(movimentacoesViaAjax($), true);
});

test("movimentacoesViaAjax: layout antigo (#tabelaTodasMovimentacoes completa) não pagina", () => {
  const $ = load(`<table id="tabelaTodasMovimentacoes"><tbody>${linha("01/01/2020", "Documento Juntado")}</tbody></table>`);
  assert.equal(extractAndamentos($).length, 1);
  assert.equal(movimentacoesViaAjax($), false);
});

test("extractMovimentacoesAjax: <tr> soltas (páginas seguintes) + cursor da próxima página", () => {
  const html = `${linha("10/06/2024", "Remetido ao DJE", "Teor")}${linha("08/06/2024", "Pagamento")}
    <tr id="trCursorMovimentacoes" data-cursor="PROX" style="display:none"><td></td></tr>`;
  const r = extractMovimentacoesAjax(html);
  assert.equal(r.andamentos.length, 2);
  assert.equal(r.cursor, "PROX");
});

test("extractMovimentacoesAjax: última página (sem linha de cursor) → cursor null", () => {
  const r = extractMovimentacoesAjax(linha("19/12/2011", "ENCAMINHADO AO DEPRE 2.1 EM", "Remetente: 1.1"));
  assert.equal(r.andamentos.length, 1);
  assert.equal(r.cursor, null);
});

test("extractMovimentacoesAjax: 1ª página como bloco completo traz o cursor do input oculto", () => {
  const r = extractMovimentacoesAjax(`<table><tbody id="tabelaPrimeiraPaginaMovimentacoes">${linha("13/10/2026", "X")}</tbody></table>
    <input type="hidden" id="cursorMovimentacoesPaginado" value="C1">`);
  assert.equal(r.andamentos.length, 1);
  assert.equal(r.cursor, "C1");
});

test("extractPeticoesDiversas: tabela após o <h2> 'Petições diversas'", () => {
  const $ = load(`<div><h2 class="subtitle tituloDoBloco">Petições diversas</h2></div>
    <table><tbody><tr><td>31/05/2022</td><td>Comunicado de Acordo de Requisitório <br> </td></tr></tbody></table>`);
  const p = extractPeticoesDiversas($);
  assert.equal(p.length, 1);
  assert.equal(p[0]!.descricao, "Comunicado de Acordo de Requisitório");
  assert.equal(temAcordoHomologado(p), false);
});

test("extractMovimentacoesAjax: resposta de erro do e-SAJ (200 + div de erro) lança, não vira lista vazia", () => {
  assert.throws(
    () => extractMovimentacoesAjax('<div class="mensagemErroMovimentacoes"> Não foi possível realizar a operação requisitada, tente novamente mais tarde. </div>'),
    /e-SAJ recusou/,
  );
});

test("classificarAcordoHomologado: tri-state (true com prova; false só com leitura completa; senão null)", () => {
  const prova = [and("DEPRE Decisão Publicável Vistos. Homologo o acordo, celebrado entre as partes.")];
  const semProva = [and("Documento Juntado"), and("Comunicado de Acordo de Requisitório")];
  assert.equal(classificarAcordoHomologado(prova, true), true);
  assert.equal(classificarAcordoHomologado(prova, false), true); // prova basta, mesmo sem leitura completa
  assert.equal(classificarAcordoHomologado(semProva, true), false);
  assert.equal(classificarAcordoHomologado(semProva, false), null);
  assert.equal(classificarAcordoHomologado([], false), null);
});

test("fichaSemConteudo: página só com o aviso de senha (sem capa/partes/seções) é 'sem conteúdo'", () => {
  const vazia = load(`<div id="popupSenha">Atendendo a resolução 121 do CNJ. digite a senha do processo</div><script>saj.env.queryString='processo.codigo=ABC'</script>`);
  assert.equal(fichaSemConteudo(vazia), true);
});

test("fichaSemConteudo: ficha real (capa, partes ou seções) NÃO é 'sem conteúdo'", () => {
  assert.equal(fichaSemConteudo(load(`<span id="numeroProcesso">7009845-09.2011.8.26.0500</span>`)), false);
  assert.equal(fichaSemConteudo(load(`<table id="tablePartesPrincipais"></table>`)), false);
  assert.equal(fichaSemConteudo(load(`<h2 class="subtitle tituloDoBloco">Movimentações</h2>`)), false);
});

test("buscaRequisitorioUtil: stub (só aviso de senha) NÃO serve; ficha serve", () => {
  assert.equal(buscaRequisitorioUtil(load(`<div id="popupSenha">digite a senha do processo</div>`)), false);
  assert.equal(buscaRequisitorioUtil(load(`<span id="numeroProcesso">0314772-49.2020.8.26.0500</span>`)), true);
});
