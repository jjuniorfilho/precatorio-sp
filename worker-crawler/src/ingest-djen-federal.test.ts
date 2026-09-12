// Testes da lógica pura de src/ingest-djen-federal.ts. Roda via `npm test` (node:test nativo).
import { test } from "node:test";
import assert from "node:assert/strict";
import { sistemaFromLink, classificaPorNomeClasse, enteFederalPublico, deveCapturar, detectaEnteFederal, planoPersistencia } from "./ingest-djen-federal.js";

const CLASSES_RELEVANTES = [
  "Cumprimento de Sentença contra a Fazenda Pública",
  "Cumprimento Provisório de Sentença contra a Fazenda Pública",
  "Execução contra a Fazenda Pública",
  "Precatório",
  "Requisição de Pequeno Valor",
  "Procedimento do Juizado Especial da Fazenda Pública",
];

test("classificaPorNomeClasse: as 6 classes relevantes mapeiam pro balde certo", () => {
  assert.equal(classificaPorNomeClasse("Precatório", CLASSES_RELEVANTES), "precatorio");
  assert.equal(classificaPorNomeClasse("Requisição de Pequeno Valor", CLASSES_RELEVANTES), "rpv");
  assert.equal(classificaPorNomeClasse("Cumprimento de Sentença contra a Fazenda Pública", CLASSES_RELEVANTES), "cumprimento_sentenca");
  assert.equal(classificaPorNomeClasse("Cumprimento Provisório de Sentença contra a Fazenda Pública", CLASSES_RELEVANTES), "cumprimento_sentenca");
  assert.equal(classificaPorNomeClasse("Execução contra a Fazenda Pública", CLASSES_RELEVANTES), "cumprimento_sentenca");
  assert.equal(classificaPorNomeClasse("Procedimento do Juizado Especial da Fazenda Pública", CLASSES_RELEVANTES), "conhecimento");
});

test("classificaPorNomeClasse: case/acento não importa (amostra real usa caixa alta)", () => {
  assert.equal(classificaPorNomeClasse("PRECATORIO", CLASSES_RELEVANTES), "precatorio");
  assert.equal(classificaPorNomeClasse("execucao contra a fazenda publica", CLASSES_RELEVANTES), "cumprimento_sentenca");
});

test("classificaPorNomeClasse: classe não relevante -> null (ignorada, não vira conhecimento)", () => {
  assert.equal(classificaPorNomeClasse("PROCEDIMENTO DO JUIZADO ESPECIAL CÍVEL", CLASSES_RELEVANTES), null);
  assert.equal(classificaPorNomeClasse("Ação Penal", CLASSES_RELEVANTES), null);
  assert.equal(classificaPorNomeClasse(null, CLASSES_RELEVANTES), null);
});

test("classificaPorNomeClasse: regressão 2026-09-06 — 'CUMPRIMENTO DE SENTENÇA' genérico (privado) NÃO deve bater a classe pública (achado em amostra real do TRF3)", () => {
  assert.equal(classificaPorNomeClasse("CUMPRIMENTO DE SENTENÇA", CLASSES_RELEVANTES), null);
  assert.equal(classificaPorNomeClasse("EXECUÇÃO", CLASSES_RELEVANTES), null);
});

test("enteFederalPublico: reconhece entes federais comuns", () => {
  assert.equal(enteFederalPublico("INSTITUTO NACIONAL DO SEGURO SOCIAL - INSS"), true);
  assert.equal(enteFederalPublico("UNIÃO FEDERAL"), true);
  assert.equal(enteFederalPublico("CAIXA ECONÔMICA FEDERAL"), true);
  assert.equal(enteFederalPublico("EMPRESA BRASILEIRA DE CORREIOS E TELÉGRAFOS"), true);
});

test("enteFederalPublico: parte privada ou estadual não bate", () => {
  assert.equal(enteFederalPublico("MARIA DO SOCORRO DOS SANTOS FORNAZIER"), false);
  assert.equal(enteFederalPublico("FAZENDA PÚBLICA DO ESTADO DE SÃO PAULO"), false);
  assert.equal(enteFederalPublico(null), false);
});

test("enteFederalPublico: extras vindos de coleta_config.params.entes_federais", () => {
  assert.equal(enteFederalPublico("SERVICO FLORESTAL BRASILEIRO", []), false);
  assert.equal(enteFederalPublico("SERVICO FLORESTAL BRASILEIRO", ["SERVICO FLORESTAL BRASILEIRO"]), true);
});

test("deveCapturar: decide só pela classe (amostra real mostrou que destinatarios não confirma parte passiva)", () => {
  assert.equal(deveCapturar({ nomeClasse: "Cumprimento de Sentença contra a Fazenda Pública" }, CLASSES_RELEVANTES), "cumprimento_sentenca");
  assert.equal(deveCapturar({ nomeClasse: "Ação Penal" }, CLASSES_RELEVANTES), null);
});

test("detectaEnteFederal: acha via destinatarios (polo P) quando presente", () => {
  const item = { destinatarios: [{ polo: "A", nome: "FULANO DE TAL" }, { polo: "P", nome: "INSS" }] };
  assert.equal(detectaEnteFederal(item), "INSS");
});

test("detectaEnteFederal: fallback pro teor quando destinatarios não tem o réu (caso real/comum)", () => {
  const item = {
    destinatarios: [{ polo: "A", nome: "MARIA DO SOCORRO DOS SANTOS FORNAZIER" }],
    texto: "REU: INSTITUTO NACIONAL DO SEGURO SOCIAL - INSS ATO ORDINATÓRIO...",
  };
  assert.equal(detectaEnteFederal(item), "INSS"); // primeiro match na lista (ordem importa, não afeta o resultado prático)
});

test("detectaEnteFederal: null quando não acha em lugar nenhum (não bloqueia deveCapturar)", () => {
  const item = { destinatarios: [{ polo: "A", nome: "FULANO" }], texto: "algum texto sem ente reconhecido" };
  assert.equal(detectaEnteFederal(item), null);
});

test("planoPersistencia: balde conhecimento vira só processos (sem cumprimento/incidente/andamento)", () => {
  const plano = planoPersistencia(
    { numeroprocessocommascara: "5000000-00.2026.4.03.6100", nomeClasse: "Procedimento do Juizado Especial da Fazenda Pública" },
    "conhecimento", "TRF3", "pje", "2026-09-01",
  );
  assert.ok(plano);
  assert.equal(plano!.processo.processo_codigo, "5000000-00.2026.4.03.6100");
  assert.equal(plano!.processo.cnj, "5000000-00.2026.4.03.6100");
  assert.equal(plano!.processo.cnj_normalizado, "50000000020264036100");
  assert.equal(plano!.cumprimento, undefined);
  assert.equal(plano!.incidenteVaso, undefined);
  assert.equal(plano!.andamento, undefined);
});

test("planoPersistencia: balde cumprimento_sentenca vira processo placeholder + cumprimento + incidente vaso (Indefinido) + andamento", () => {
  const plano = planoPersistencia(
    { numeroprocessocommascara: "5000000-00.2026.4.03.6100", nomeClasse: "Cumprimento de Sentença contra a Fazenda Pública", link: "https://pje1g.trf3.jus.br/x", texto: "teor da publicação" },
    "cumprimento_sentenca", "TRF3", "pje", "2026-09-01",
  );
  assert.ok(plano);
  assert.equal(plano!.processo.processo_codigo, "FEDPLACEHOLDER-50000000020264036100");
  assert.equal(plano!.processo.cnj, null);
  assert.equal(plano!.cumprimento?.processo_codigo, "5000000-00.2026.4.03.6100");
  assert.equal(plano!.cumprimento?.cnj_normalizado, "50000000020264036100");
  assert.equal(plano!.incidenteVaso?.processo_codigo, "5000000-00.2026.4.03.6100-VASO");
  assert.equal(plano!.incidenteVaso?.tipo_previsto, "Indefinido");
  assert.equal(plano!.andamento?.descricao, "teor da publicação");
  assert.equal(plano!.andamento?.arquivo_url, "https://pje1g.trf3.jus.br/x");
});

test("planoPersistencia: balde precatorio/rpv seta tipo_previsto certo no incidente vaso", () => {
  const base = { numeroprocessocommascara: "5000000-00.2026.4.03.6100", nomeClasse: "Precatório" };
  assert.equal(planoPersistencia(base, "precatorio", "TRF3", "pje", "2026-09-01")!.incidenteVaso?.tipo_previsto, "Precatorio");
  assert.equal(planoPersistencia(base, "rpv", "TRF3", "pje", "2026-09-01")!.incidenteVaso?.tipo_previsto, "RPV");
});

test("planoPersistencia: sem CNJ no item -> null (não persiste nada)", () => {
  assert.equal(planoPersistencia({ numeroprocessocommascara: null }, "cumprimento_sentenca", "TRF3", "pje", "2026-09-01"), null);
});

test("sistemaFromLink: pje (TRF1/TRF3/TRF5, amostra real 2026-09-01)", () => {
  assert.equal(sistemaFromLink("https://pje1g.trf1.jus.br:443/pje/Processo/ConsultaDocumento/listView.seam?x=1"), "pje");
  assert.equal(sistemaFromLink("https://pje1g.trf3.jus.br:443/pje/Processo/ConsultaDocumento/listView.seam?x=1"), "pje");
  assert.equal(sistemaFromLink("https://pje1g.trf5.jus.br/pje/Processo/ConsultaDocumento/listView.seam?x=1"), "pje");
});

test("sistemaFromLink: eproc (TRF2/TRF4/TRF6, amostra real 2026-09-01)", () => {
  assert.equal(sistemaFromLink("https://eproc.jfes.jus.br/eproc/externo_controlador.php?acao=x"), "eproc");
  assert.equal(sistemaFromLink("https://eproc.jfpr.jus.br/eprocV2/externo_controlador.php?acao=x"), "eproc");
  assert.equal(sistemaFromLink("https://eproc1g.trf6.jus.br/eproc/externo_controlador.php?acao=x"), "eproc");
});

test("sistemaFromLink: sem link ou domínio desconhecido -> outro", () => {
  assert.equal(sistemaFromLink(null), "outro");
  assert.equal(sistemaFromLink(""), "outro");
  assert.equal(sistemaFromLink("https://www.dje.tjsp.jus.br/algum-link"), "outro");
});
