// FOR-171 — testes do classificador do resultado do portal TJSP (fixtures REAIS capturados em
// 25/09/2026) e do coletor de passos. Roda via `npm test` (node:test).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { classificarHtml } from "./pagamentos-classificar.js";
import { PassosCollector, ConsultaPagamentoErro } from "./pagamentos-passos.js";

const URL_OK = "https://www.tjsp.jus.br/cac/scp/pesquisainternetnumanoep.aspx?abc";
const fx = (n: string) => readFileSync(new URL(`./__fixtures__/pagamentos/${n}`, import.meta.url), "utf-8");
const SEM = fx("resultado-sem-pagamento.html");
const COM = fx("resultado-com-pagamento.html");

test("sem pagamento: portal respondeu 'não consta' (mensagem visível, grade vazia, rodapé)", () => {
  const r = classificarHtml(SEM, URL_OK);
  assert.equal(r.resultado, "nao_consta");
  assert.equal(r.situacao, null);
  assert.match(r.dataConsultaPortal ?? "", /^\d{2}\/\d{2}\/\d{4}/);
});

test("com pagamento: encontrado, com a situação da grade", () => {
  const r = classificarHtml(COM, URL_OK);
  assert.equal(r.resultado, "encontrado");
  assert.equal(r.situacao, "Pendente de Pagamento");
});

test("falha: URL fora do padrão de resultado", () => {
  assert.equal(classificarHtml(SEM, "https://www.tjsp.jus.br/cac/scp/pesquisainternetv2.aspx").resultado, "falha");
  assert.equal(classificarHtml(COM, "about:blank").resultado, "falha");
});

test("falha: página sem rodapé 'Data da Consulta' e sem grade", () => {
  const semRodape = SEM.replace(/Data da Consulta/g, "Xxxx");
  assert.equal(classificarHtml(semRodape, URL_OK).resultado, "falha");
});

test("falha: TXTNENHUM_Visible=0 sem linha na grade (página inesperada)", () => {
  const html = SEM.replace(/TXTNENHUM_Visible&quot;:&quot;1/, "TXTNENHUM_Visible&quot;:&quot;0");
  assert.equal(classificarHtml(html, URL_OK).resultado, "falha");
});

test("falha: sem o estado GeneXus TXTNENHUM_Visible", () => {
  const html = SEM.replace(/TXTNENHUM_Visible/g, "OUTRA_Visible");
  assert.equal(classificarHtml(html, URL_OK).resultado, "falha");
});

test("falha: sinais divergentes (server-side visível, mas display:none inline)", () => {
  const html = SEM.replace(/style="(font-family[^"]*)" id="TXTNENHUM"/, 'style="display:none;$1" id="TXTNENHUM"');
  assert.notEqual(html, SEM, "o replace deve ter alterado o fixture");
  assert.equal(classificarHtml(html, URL_OK).resultado, "falha");
});

test("falha: página vazia", () => {
  assert.equal(classificarHtml("<html><body></body></html>", URL_OK).resultado, "falha");
});

test("PassosCollector: registra horário/etapa e a etapa do erro", () => {
  const p = new PassosCollector();
  p.passo("abrir_portal", "ok");
  p.passo("busca", "erro", "timeout");
  assert.equal(p.passos.length, 2);
  assert.match(p.passos[0]!.at, /^\d{4}-\d{2}-\d{2}T/);
  assert.equal(p.etapaDoErro(), "busca");
  const e = new ConsultaPagamentoErro("x", "busca", p);
  assert.equal(e.etapa, "busca");
});

// ---- consultarEPersistirPagamentos (com dependências injetadas) ----
import { consultarEPersistirPagamentos, origemValida, type ConsultaPagamento, type DepsPersistencia } from "./pagamentos-tjsp.js";

const DEPRE = "0145616-63.2020.8.26.0500";
const consultaBase = (resultado: ConsultaPagamento["resultado"]): ConsultaPagamento => ({
  encontrado: resultado === "encontrado", resultado, situacao: null, pagamentos: [],
  consultadoEm: new Date().toISOString(), dataConsultaPortal: null, tentativas: 1,
});
function fakeDeps(over: Partial<DepsPersistencia> & { resultado?: ConsultaPagamento["resultado"]; erro?: Error }) {
  const chamadas = { marcar: 0, upsert: 0, registrar: [] as Array<{ resultado: string; origem: string; etapaFalha: string | null }> };
  const deps: DepsPersistencia = {
    consultar: async () => {
      if (over.erro) throw new ConsultaPagamentoErro(over.erro.message, "busca", new PassosCollector());
      return consultaBase(over.resultado ?? "encontrado");
    },
    upsert: async () => { chamadas.upsert++; },
    marcar: async () => { chamadas.marcar++; },
    registrar: async (r) => { chamadas.registrar.push({ resultado: r.resultado, origem: r.origem, etapaFalha: r.etapaFalha }); },
    ...(over.upsert && { upsert: over.upsert }), ...(over.marcar && { marcar: over.marcar }), ...(over.registrar && { registrar: over.registrar }),
  };
  return { deps, chamadas };
}

test("nao_consta marca consultado e loga", async () => {
  const { deps, chamadas } = fakeDeps({ resultado: "nao_consta" });
  const r = await consultarEPersistirPagamentos(DEPRE, { origem: "crawler" }, deps);
  assert.equal(r.resultado, "nao_consta");
  assert.equal(chamadas.marcar, 1);
  assert.deepEqual(chamadas.registrar, [{ resultado: "nao_consta", origem: "crawler", etapaFalha: null }]);
});

test("encontrado marca consultado", async () => {
  const { deps, chamadas } = fakeDeps({ resultado: "encontrado" });
  await consultarEPersistirPagamentos(DEPRE, {}, deps);
  assert.equal(chamadas.marcar, 1);
  assert.equal(chamadas.registrar[0]!.origem, "manual");
});

test("falha NUNCA marca consultado, relança e loga a etapa", async () => {
  const { deps, chamadas } = fakeDeps({ erro: new Error("timeout") });
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, {}, deps), /timeout/);
  assert.equal(chamadas.marcar, 0);
  assert.equal(chamadas.upsert, 0);
  assert.deepEqual(chamadas.registrar, [{ resultado: "falha", origem: "manual", etapaFalha: "busca" }]);
});

test("erro ao gravar o log NÃO derruba a consulta (best-effort)", async () => {
  const { deps, chamadas } = fakeDeps({ resultado: "nao_consta", registrar: async () => { throw new Error("rpc fora do ar"); } });
  const r = await consultarEPersistirPagamentos(DEPRE, {}, deps);
  assert.equal(r.resultado, "nao_consta");
  assert.equal(chamadas.marcar, 1);
});

test("falha ao persistir vira falha na etapa persistir (sem vazar mensagem crua no log)", async () => {
  const { deps, chamadas } = fakeDeps({ resultado: "nao_consta", marcar: async () => { throw new Error("SEGREDO do banco"); } });
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, {}, deps), (e: Error) => !/SEGREDO/.test(e.message));
  assert.equal(chamadas.registrar[0]!.resultado, "falha");
  assert.equal(chamadas.registrar[0]!.etapaFalha, "persistir");
});

test("origemValida", () => {
  assert.ok(origemValida("manual") && origemValida("busca_publica") && origemValida("crawler"));
  assert.ok(!origemValida("x") && !origemValida(undefined) && !origemValida(1));
});
