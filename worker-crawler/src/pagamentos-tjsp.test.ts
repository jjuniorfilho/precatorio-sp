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

// ---- FOR-173: progresso incremental (deps injetadas, sem portal) ----
import { criarReporter, type ProgressoReporter } from "./pagamentos-progresso.js";
import type { RegistroProgressoPagamento } from "./supabase.js";

/** Reporter fake que só anota a ordem das chamadas (junto com as demais dependências). */
function reporterFake(linha: string[]): ProgressoReporter {
  return {
    naFila: () => { linha.push("naFila"); },
    ligar: () => { linha.push("ligar"); },
    concluir: (r) => { linha.push(`concluir:${r}`); },
    falhar: (e) => { linha.push(`falhar:${e}`); },
    drenar: async () => { linha.push("drenar"); },
  };
}

test("progresso (manual): na_fila ANTES de consultar; estado final e drenar ANTES do log", async () => {
  const linha: string[] = [];
  const { deps } = fakeDeps({ resultado: "nao_consta" });
  const consultar = deps.consultar;
  deps.consultar = async (...a) => { linha.push("consultar"); return consultar(...a); };
  deps.registrar = async () => { linha.push("log"); };
  deps.progresso = () => reporterFake(linha);
  await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps);
  assert.deepEqual(linha, ["ligar", "naFila", "consultar", "concluir:nao_consta", "drenar", "log"]);
});

test("progresso (manual): falha grava falhar(etapa) antes do log e a consulta relança o erro", async () => {
  const linha: string[] = [];
  const { deps } = fakeDeps({ erro: new Error("timeout") });
  deps.registrar = async () => { linha.push("log"); };
  deps.progresso = () => reporterFake(linha);
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps), /timeout/);
  assert.deepEqual(linha, ["ligar", "naFila", "falhar:busca", "drenar", "log"]);
});

test("progresso: crawler e busca_publica NÃO criam reporter (só o disparo manual publica progresso)", async () => {
  for (const origem of ["crawler", "busca_publica"] as const) {
    let fabricas = 0;
    const { deps } = fakeDeps({ resultado: "encontrado" });
    deps.progresso = () => { fabricas++; return reporterFake([]); };
    await consultarEPersistirPagamentos(DEPRE, { origem }, deps);
    assert.equal(fabricas, 0, origem);
  }
});

test("progresso: fábrica ou reporter que LANÇAM não derrubam a consulta nem o log", async () => {
  for (const quebra of ["fabrica", "naFila", "concluir"] as const) {
    const { deps, chamadas } = fakeDeps({ resultado: "nao_consta" });
    deps.progresso = () => {
      if (quebra === "fabrica") throw new Error("bug na fábrica");
      return { ...reporterFake([]), ...(quebra === "naFila" && { naFila: () => { throw new Error("bug"); } }), ...(quebra === "concluir" && { concluir: () => { throw new Error("bug"); } }) };
    };
    const r = await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps);
    assert.equal(r.resultado, "nao_consta", quebra);
    assert.equal(chamadas.marcar, 1, quebra);
    assert.equal(chamadas.registrar.length, 1, `${quebra}: o log do FOR-171 ainda é gravado`);
  }
});

test("progresso: o LOG do FOR-171 fica idêntico com e sem progresso (tentativa()/iniciar() não viram passo)", async () => {
  const emiteEventos = async (_d: string, _m: number, passos: PassosCollector) => {
    passos.iniciar();
    passos.passo("abrir_portal", "ok", "Abriu o portal");
    passos.tentativa(1);
    passos.passo("busca", "info", "Tentativa 1: captcha rejeitado ou sem resultado");
    passos.tentativa(2);
    passos.passo("busca", "ok", "Tentativa 2: busca executada");
    return { ...consultaBase("nao_consta"), tentativas: passos.tentativas };
  };
  const logados: unknown[] = [];
  const captura = (deps: DepsPersistencia) => { deps.registrar = async (r) => { logados.push({ passos: r.passos.map((p) => (p as { etapa: string; status: string; detalhe?: string }).detalhe ?? ""), tentativas: r.tentativas, resultado: r.resultado }); }; };

  const sem = fakeDeps({}); sem.deps.consultar = emiteEventos; captura(sem.deps);
  await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, sem.deps);

  const com = fakeDeps({}); com.deps.consultar = emiteEventos; captura(com.deps);
  com.deps.progresso = (a) => criarReporter({ ...a, registrar: async () => {} });
  await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, com.deps);

  assert.equal(logados.length, 2);
  assert.deepEqual(logados[1], logados[0], "log idêntico com e sem progresso");
  // 3 passos emitidos pelo fake + o passo real `persistir` que o próprio consultarEPersistirPagamentos acrescenta.
  // Nenhum vem de tentativa()/iniciar().
  assert.equal((logados[0] as { passos: string[] }).passos.length, 4, "3 passos do fake + `persistir`; nada de tentativa()/iniciar()");
});

test("progresso (reporter real + fake): sequência gravada de ponta a ponta sem tocar no portal", async () => {
  const registros: RegistroProgressoPagamento[] = [];
  const { deps } = fakeDeps({});
  deps.consultar = async (_d, _m, passos) => {
    passos.iniciar();
    passos.tentativa(1);
    passos.passo("busca", "ok", "Tentativa 1: busca executada");
    passos.passo("resultado_carregou", "ok");
    passos.passo("ler_resultado", "ok", "grade com pagamento");
    return { ...consultaBase("encontrado"), tentativas: 1 };
  };
  deps.progresso = (a) => criarReporter({ ...a, registrar: async (r) => { registros.push(r); } });
  await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps);
  assert.deepEqual(
    registros.map((r) => `${r.estado}/${r.etapa}/${r.tentativa}`),
    ["na_fila/na_fila/0", "em_andamento/iniciando/0", "em_andamento/busca/1", "em_andamento/resultado_carregou/1", "em_andamento/ler_resultado/1", "em_andamento/extrair_pagamentos/1", "em_andamento/persistir/1", "concluida/persistir/1"],
  );
  assert.equal(registros[0]!.nova, true);
  assert.equal(registros.at(-1)!.resultado, "encontrado");
});

// ---- FOR-173: lacunas apontadas pela revisão de cobertura ----
function gravadorReal() {
  const registros: RegistroProgressoPagamento[] = [];
  const fabrica = (over: { registrar?: (r: RegistroProgressoPagamento) => Promise<void>; drenarMs?: number } = {}) =>
    (a: { processoDepre: string; origem: "manual" | "busca_publica" | "crawler"; maxTentativas: number }) =>
      criarReporter({ ...a, registrar: over.registrar ?? (async (r) => { registros.push(r); }), log: () => {}, drenarMs: over.drenarMs });
  return { registros, fabrica };
}

test("progresso: falha ao PERSISTIR grava falha/persistir e a mensagem crua do banco não vaza", async () => {
  const { registros, fabrica } = gravadorReal();
  const { deps } = fakeDeps({ resultado: "nao_consta", marcar: async () => { throw new Error("SEGREDO do banco"); } });
  deps.consultar = async (_d, _m, passos) => { passos.iniciar(); passos.tentativa(1); passos.passo("busca", "ok", "Tentativa 1: busca executada"); return consultaBase("nao_consta"); };
  deps.progresso = fabrica();
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps));
  const fim = registros.at(-1)!;
  assert.equal(fim.estado, "falha");
  assert.equal(fim.etapaFalha, "persistir");
  assert.ok(!JSON.stringify(registros).includes("SEGREDO"));
  assert.ok(!registros.some((r) => r.estado === "em_andamento" && r.etapa === "persistir"), "o passo persistir com erro não é publicado");
});

test("progresso: Error simples (não ConsultaPagamentoErro) → falha/desconhecida", async () => {
  const { registros, fabrica } = gravadorReal();
  const { deps } = fakeDeps({});
  deps.consultar = async () => { throw new Error("boom"); };
  deps.progresso = fabrica();
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps), /boom/);
  const fim = registros.at(-1)!;
  assert.deepEqual([fim.estado, fim.etapa, fim.etapaFalha, fim.resultado], ["falha", "desconhecida", "desconhecida", "falha"]);
});

test("progresso: registrar TRAVADO não prende a consulta (drenar tem teto) e o log FOR-171 ainda é gravado", async () => {
  const { fabrica } = gravadorReal();
  const { deps, chamadas } = fakeDeps({ resultado: "nao_consta" });
  deps.progresso = fabrica({ registrar: () => new Promise<void>(() => { /* nunca resolve */ }), drenarMs: 40 });
  const t0 = Date.now();
  const r = await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps);
  assert.equal(r.resultado, "nao_consta");
  assert.equal(chamadas.registrar.length, 1, "o log do FOR-171 foi gravado");
  assert.ok(Date.now() - t0 < 1000, "a resposta não ficou refém do progresso");
});

test("progresso: registrar do progresso lançando + consulta falhando → relança o erro ORIGINAL e loga a etapa", async () => {
  const { fabrica } = gravadorReal();
  const { deps, chamadas } = fakeDeps({ erro: new Error("timeout do portal") });
  deps.progresso = fabrica({ registrar: async () => { throw new Error("rpc de progresso fora do ar"); } });
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps), /timeout do portal/);
  assert.equal(chamadas.marcar, 0);
  assert.deepEqual(chamadas.registrar, [{ resultado: "falha", origem: "manual", etapaFalha: "busca" }]);
});

test("progresso: falhar() que LANÇA também não derruba a consulta nem troca o erro", async () => {
  const { deps, chamadas } = fakeDeps({ erro: new Error("timeout do portal") });
  deps.progresso = () => ({ ...reporterFake([]), falhar: () => { throw new Error("bug no falhar"); } });
  await assert.rejects(() => consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps), /timeout do portal/);
  assert.equal(chamadas.registrar.length, 1);
});

test("progresso: maxTentativas numérico chega à fábrica e ao detalhe; sem opções vale manual/4", async () => {
  const recebidos: Array<{ origem: string; maxTentativas: number }> = [];
  const { registros, fabrica } = gravadorReal();
  const real = fabrica();
  const { deps } = fakeDeps({});
  deps.consultar = async (_d, _m, passos) => { passos.tentativa(1); return consultaBase("encontrado"); };
  deps.progresso = (a) => { recebidos.push({ origem: a.origem, maxTentativas: a.maxTentativas }); return real(a); };

  await consultarEPersistirPagamentos(DEPRE, 2, deps); // forma numérica = maxTentativas
  assert.deepEqual(recebidos[0], { origem: "manual", maxTentativas: 2 });
  assert.equal(registros.find((r) => r.etapa === "busca")!.detalhe, "Tentativa 1 de 2");
  assert.ok(registros.every((r) => r.maxTentativas === 2));

  await consultarEPersistirPagamentos(DEPRE, {}, deps);
  await consultarEPersistirPagamentos(DEPRE, undefined, deps);
  assert.deepEqual(recebidos.slice(1), [{ origem: "manual", maxTentativas: 4 }, { origem: "manual", maxTentativas: 4 }]);
});

test("progresso: resultado 'falha' que chega SEM lançar vira falha no progresso (nunca concluida/falha)", async () => {
  const linha: string[] = [];
  const { deps } = fakeDeps({});
  deps.consultar = async () => ({ ...consultaBase("nao_consta"), resultado: "falha" as const });
  deps.progresso = () => reporterFake(linha);
  await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps);
  assert.ok(linha.includes("falhar:null") && !linha.some((l) => l.startsWith("concluir")), linha.join(","));
});

test("progresso: encontrado com o fluxo REAL de passos (extrair_pagamentos + persistir) — sequência exata", async () => {
  const { registros, fabrica } = gravadorReal();
  const { deps } = fakeDeps({});
  deps.consultar = async (_d, _m, passos) => {
    passos.iniciar();
    passos.passo("abrir_portal", "ok"); passos.passo("obter_link", "ok"); passos.passo("abrir_pesquisa", "ok");
    passos.tentativa(1); passos.passo("busca", "ok", "Tentativa 1: busca executada");
    passos.passo("resultado_carregou", "ok"); passos.passo("ler_resultado", "ok", "grade com pagamento");
    passos.passo("extrair_pagamentos", "ok", "3 pagamento(s) no relatório");
    return { ...consultaBase("encontrado"), tentativas: 1 };
  };
  deps.progresso = fabrica();
  await consultarEPersistirPagamentos(DEPRE, { origem: "manual" }, deps);
  assert.deepEqual(registros.map((r) => `${r.estado}/${r.etapa}`), [
    "na_fila/na_fila", "em_andamento/iniciando", "em_andamento/obter_link", "em_andamento/abrir_pesquisa",
    "em_andamento/busca", "em_andamento/busca", "em_andamento/resultado_carregou", "em_andamento/ler_resultado",
    "em_andamento/extrair_pagamentos", "em_andamento/persistir", "em_andamento/persistir", "concluida/persistir",
  ]);
  assert.equal(registros.at(-1)!.resultado, "encontrado");
});
