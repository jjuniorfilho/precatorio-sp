// FOR-173 — testes do observador do coletor de passos e do reporter de progresso. Sem rede, sem portal:
// o `registrar` é sempre um fake. Roda via `npm test` (node:test).
import { test } from "node:test";
import assert from "node:assert/strict";
import { PassosCollector, type EventoColetor } from "./pagamentos-passos.js";
import { criarReporter, proximaEtapa } from "./pagamentos-progresso.js";
import type { RegistroProgressoPagamento } from "./supabase.js";

const DEPRE = "0145616-63.2020.8.26.0500";

// ---- PassosCollector: observador ---------------------------------------------------------------------
test("coletor: passo notifica DEPOIS de registrar, com as tentativas atuais", () => {
  const p = new PassosCollector();
  const vistos: Array<{ n: number; e: EventoColetor }> = [];
  p.observar((e) => vistos.push({ n: p.passos.length, e }));
  p.tentativas = 2;
  p.passo("busca", "ok", "Tentativa 2: busca executada");
  assert.equal(vistos.length, 1);
  assert.equal(vistos[0]!.n, 1, "o passo já estava na lista quando o observador foi chamado");
  const e = vistos[0]!.e;
  assert.ok(e.tipo === "passo" && e.tentativas === 2 && e.passo.etapa === "busca");
});

test("coletor: iniciar() e tentativa(n) notificam mas NÃO viram passo (log do FOR-171 idêntico)", () => {
  const p = new PassosCollector();
  const tipos: string[] = [];
  p.observar((e) => tipos.push(e.tipo));
  p.iniciar();
  p.tentativa(1);
  p.tentativa(2);
  assert.deepEqual(tipos, ["iniciar", "tentativa", "tentativa"]);
  assert.equal(p.passos.length, 0);
  assert.equal(p.tentativas, 2, "tentativa(n) atribui `tentativas`");
});

test("coletor: observador que lança NÃO propaga e não impede os outros", () => {
  const p = new PassosCollector();
  const vistos: string[] = [];
  p.observar(() => { throw new Error("bug do observador"); });
  p.observar((e) => vistos.push(e.tipo));
  assert.doesNotThrow(() => { p.iniciar(); p.tentativa(1); p.passo("abrir_portal", "ok"); });
  assert.deepEqual(vistos, ["iniciar", "tentativa", "passo"]);
  assert.equal(p.passos.length, 1);
});

test("coletor: sem observadores se comporta como antes", () => {
  const p = new PassosCollector();
  p.passo("abrir_portal", "ok");
  p.passo("busca", "erro", "timeout");
  assert.equal(p.etapaDoErro(), "busca");
});

// ---- proximaEtapa -------------------------------------------------------------------------------------
test("proximaEtapa: 'concluí X' → etapa em andamento", () => {
  assert.equal(proximaEtapa("abrir_portal", "ok"), "obter_link");
  assert.equal(proximaEtapa("obter_link", "ok"), "abrir_pesquisa");
  assert.equal(proximaEtapa("abrir_pesquisa", "ok"), "busca");
  assert.equal(proximaEtapa("busca", "info"), "busca", "captcha rejeitado: continua na busca (próxima tentativa)");
  assert.equal(proximaEtapa("busca", "ok"), "resultado_carregou");
  assert.equal(proximaEtapa("resultado_carregou", "ok"), "ler_resultado");
  assert.equal(proximaEtapa("ler_resultado", "ok"), "extrair_pagamentos");
  assert.equal(proximaEtapa("extrair_pagamentos", "ok"), "persistir");
  assert.equal(proximaEtapa("persistir", "ok"), "persistir");
});

// ---- reporter -----------------------------------------------------------------------------------------
function gravador() {
  const registros: RegistroProgressoPagamento[] = [];
  const registrar = async (r: RegistroProgressoPagamento) => { registros.push(r); };
  return { registros, registrar };
}
const resumo = (rs: RegistroProgressoPagamento[]) => rs.map((r) => `${r.estado}/${r.etapa}/${r.tentativa}${r.nova ? "/nova" : ""}`);

test("reporter: sequência completa na_fila → iniciando → tentativas de captcha → concluida", async () => {
  const { registros, registrar } = gravador();
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar });
  const passos = new PassosCollector();
  rep.ligar(passos);
  rep.naFila();
  passos.iniciar();
  passos.passo("abrir_portal", "ok", "Abriu o portal TJSP (Pagamentos Precatórios)");
  passos.passo("obter_link", "ok");
  passos.passo("abrir_pesquisa", "ok", "Abriu a pesquisa por Processo DEPRE");
  passos.tentativa(1);
  passos.passo("busca", "info", "Tentativa 1: captcha rejeitado ou sem resultado");
  passos.tentativa(2);
  passos.passo("busca", "ok", "Tentativa 2: busca executada");
  passos.passo("resultado_carregou", "ok", "Página de resultado carregou");
  passos.passo("ler_resultado", "ok", "mensagem visível");
  passos.passo("persistir", "ok", "0 pagamento(s); marcado como consultado");
  rep.concluir("nao_consta");
  await rep.drenar();

  assert.deepEqual(resumo(registros), [
    "na_fila/na_fila/0/nova",
    "em_andamento/iniciando/0",
    "em_andamento/obter_link/0",
    "em_andamento/abrir_pesquisa/0",
    "em_andamento/busca/0",
    "em_andamento/busca/1",   // tentativa(1)
    "em_andamento/busca/1",   // busca info (rejeitado)
    "em_andamento/busca/2",   // tentativa(2)
    "em_andamento/resultado_carregou/2",
    "em_andamento/ler_resultado/2",
    "em_andamento/extrair_pagamentos/2",
    "em_andamento/persistir/2",
    "concluida/persistir/2",
  ]);
  assert.equal(registros.filter((r) => r.nova).length, 1, "só o na_fila renova iniciada_em");
  assert.ok(registros.every((r) => r.processoDepre === DEPRE && r.origem === "manual" && r.maxTentativas === 4));
  const fim = registros[registros.length - 1]!;
  assert.equal(fim.resultado, "nao_consta");
  assert.equal(registros[5]!.detalhe, "Tentativa 1 de 4");
});

test("reporter: passo de ERRO não publica (nada de mensagem crua); falhar() grava etapa_falha", async () => {
  const { registros, registrar } = gravador();
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar });
  const passos = new PassosCollector();
  rep.ligar(passos);
  passos.tentativa(4);
  passos.passo("busca", "erro", "SEGREDO: stack com url interna");
  rep.falhar("busca");
  await rep.drenar();

  assert.ok(!JSON.stringify(registros).includes("SEGREDO"), "detalhe de passo `erro` nunca sai");
  // Sem naFila() prévio, a 1ª escrita ainda vai com nova=true (nenhuma foi confirmada); a 2ª não.
  assert.deepEqual(resumo(registros), ["em_andamento/busca/4/nova", "falha/busca/4"]);
  const fim = registros[1]!;
  assert.equal(fim.etapaFalha, "busca");
  assert.equal(fim.resultado, "falha");
});

test("reporter: falhar(null) usa 'desconhecida'", async () => {
  const { registros, registrar } = gravador();
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar });
  rep.falhar(null);
  await rep.drenar();
  assert.equal(registros[0]!.etapa, "desconhecida");
  assert.equal(registros[0]!.etapaFalha, null);
});

test("reporter: escritas saem EM ORDEM e nunca em paralelo (mesmo com registrar de latência variável)", async () => {
  const saida: string[] = [];
  let ativos = 0;
  let maxAtivos = 0;
  const atrasos = [40, 5, 25, 0, 10];
  let i = 0;
  const registrar = async (r: RegistroProgressoPagamento) => {
    const atraso = atrasos[i++ % atrasos.length]!;
    ativos++; maxAtivos = Math.max(maxAtivos, ativos);
    await new Promise((res) => setTimeout(res, atraso));
    saida.push(`${r.estado}/${r.etapa}`);
    ativos--;
  };
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar });
  const passos = new PassosCollector();
  rep.ligar(passos);
  rep.naFila();
  passos.iniciar();
  passos.passo("abrir_portal", "ok");
  passos.passo("obter_link", "ok");
  rep.concluir("encontrado");
  await rep.drenar(2000);
  assert.deepEqual(saida, ["na_fila/na_fila", "em_andamento/iniciando", "em_andamento/obter_link", "em_andamento/abrir_pesquisa", "concluida/persistir"]);
  assert.equal(maxAtivos, 1, "nunca duas escritas em paralelo");
});

test("reporter: registrar que LANÇA não propaga, é logado e as escritas seguintes continuam", async () => {
  const logados: string[] = [];
  const recebidos: string[] = [];
  let n = 0;
  const registrar = async (r: RegistroProgressoPagamento) => {
    n++;
    if (n === 1) throw new Error("rpc fora do ar");
    recebidos.push(`${r.estado}/${r.etapa}`);
  };
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar, log: (m) => logados.push(m) });
  assert.doesNotThrow(() => rep.naFila());
  rep.concluir("encontrado");
  await assert.doesNotReject(() => rep.drenar());
  assert.equal(logados.length, 1);
  assert.deepEqual(recebidos, ["concluida/persistir"], "a falha do 1º não derrubou a cadeia");
});

test("reporter: drenar respeita o teto quando o registrar trava", async () => {
  const registrar = () => new Promise<void>(() => { /* nunca resolve */ });
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar });
  rep.naFila();
  const t0 = Date.now();
  await rep.drenar(60);
  const dt = Date.now() - t0;
  assert.ok(dt >= 50 && dt < 1000, `drenar deveria voltar pelo teto (levou ${dt}ms)`);
});

test("reporter: se o na_fila FALHAR, a escrita seguinte ainda renova iniciada_em (nova=true) até uma dar certo", async () => {
  const recebidas: Array<{ etapa: string; nova: boolean }> = [];
  let n = 0;
  const registrar = async (r: RegistroProgressoPagamento) => {
    n++;
    if (n === 1) throw new Error("rpc fora do ar no na_fila");
    recebidas.push({ etapa: r.etapa, nova: r.nova });
  };
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar, log: () => {} });
  const passos = new PassosCollector();
  rep.ligar(passos);
  rep.naFila();          // falha
  passos.iniciar();      // 2ª escrita: deve sair com nova=true (a 1ª não foi confirmada)
  passos.tentativa(1);   // 3ª: já confirmada → nova=false
  rep.concluir("nao_consta");
  await rep.drenar();
  assert.deepEqual(recebidas, [
    { etapa: "iniciando", nova: true },
    { etapa: "busca", nova: false },
    { etapa: "persistir", nova: false },
  ]);
});

test("reporter: `log` injetado que LANÇA não gera unhandled rejection nem quebra a cadeia", async () => {
  let naoTratadas = 0;
  const h = () => { naoTratadas++; };
  process.on("unhandledRejection", h);
  try {
    const recebidas: string[] = [];
    let n = 0;
    const registrar = async (r: RegistroProgressoPagamento) => { n++; if (n === 1) throw new Error("x"); recebidas.push(r.estado); };
    const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar, log: () => { throw new Error("log quebrado"); } });
    rep.naFila();
    rep.concluir("encontrado");
    await rep.drenar();
    await new Promise((res) => setTimeout(res, 30));
    assert.equal(naoTratadas, 0);
    assert.deepEqual(recebidas, ["concluida"]);
  } finally {
    process.off("unhandledRejection", h);
  }
});

// ---- Guarda da FIAÇÃO que só roda com o Chromium (não dá para exercitar em teste unitário) -------------
import { readFileSync } from "node:fs";
const FONTE = readFileSync(new URL("./pagamentos-tjsp.ts", import.meta.url), "utf-8");

test("fiação: passos.iniciar() é a 1ª coisa DENTRO do callback da fila do Playwright", () => {
  assert.match(FONTE, /comFilaPlaywright\(\(\) => \{\s*passos\.iniciar\(\);[^\n]*\n\s*return consultarInterno\(/);
});

test("fiação: passos.tentativa(n) vem ANTES de tentarBusca e ninguém mais atribui `tentativas` direto no loop", () => {
  assert.match(FONTE, /passos\.tentativa\(tentativa\);[^\n]*\n\s*const ok = await tentarBusca\(/);
  assert.doesNotMatch(FONTE, /passos\.tentativas = tentativa;/);
});

test("fiação: a origem que publica progresso é só 'manual'", () => {
  assert.match(FONTE, /ORIGENS_COM_PROGRESSO: readonly OrigemConsulta\[\] = \["manual"\]/);
});

test("reporter: bordas de tentativa — 0 antes da busca; 4 rejeitadas terminam em falha/busca/4 sem texto do passo erro", async () => {
  const registros: RegistroProgressoPagamento[] = [];
  const rep = criarReporter({ processoDepre: DEPRE, origem: "manual", maxTentativas: 4, registrar: async (r) => { registros.push(r); } });
  const passos = new PassosCollector();
  rep.ligar(passos);
  rep.naFila();
  passos.iniciar();
  for (let n = 1; n <= 4; n++) {
    passos.tentativa(n);
    passos.passo("busca", "info", `Tentativa ${n}: captcha rejeitado ou sem resultado`);
  }
  passos.passo("busca", "erro", "captcha não resolvido após 4 tentativas SEGREDO");
  rep.falhar("busca");
  await rep.drenar();
  assert.equal(registros[0]!.tentativa, 0);
  assert.equal(registros[1]!.tentativa, 0);
  const fim = registros.at(-1)!;
  assert.deepEqual([fim.estado, fim.etapa, fim.tentativa, fim.etapaFalha], ["falha", "busca", 4, "busca"]);
  assert.equal(registros.at(-2)!.detalhe, "Tentativa 4: captcha rejeitado ou sem resultado");
  assert.ok(!JSON.stringify(registros).includes("SEGREDO"));
});

test("fiação: depsPadrao liga o reporter ao registrarProgressoPagamento real (senão a produção fica sem barra em silêncio)", () => {
  assert.match(FONTE, /progresso: \(a\) => criarReporter\(\{ \.\.\.a, registrar: registrarProgressoPagamento \}\)/);
  assert.match(FONTE, /import \{[^}]*registrarProgressoPagamento[^}]*\} from "\.\/supabase\.js"/);
});

test("CONTRATO worker↔SQL: toda etapa que o reporter pode emitir está na lista da RPC; etapa e etapa_falha usam a MESMA lista", () => {
  const passosTs = readFileSync(new URL("./pagamentos-passos.ts", import.meta.url), "utf-8");
  const uniao = passosTs.match(/export type Etapa =([\s\S]*?);/);
  assert.ok(uniao, "não achou a união Etapa");
  const etapas = [...uniao![1]!.matchAll(/"([a-z_]+)"/g)].map((m) => m[1]!);
  assert.ok(etapas.length >= 9);

  const rpc = readFileSync(new URL("../../sql/2026-09-28_for173_4_rpcs_progresso.sql", import.meta.url), "utf-8")
    .split("\n").filter((l) => !l.trim().startsWith("--")).join("\n").replace(/\s+/g, " ");
  const lista = (re: RegExp) => [...(rpc.match(re)![1]!.matchAll(/'([a-z_]+)'/g))].map((m) => m[1]!).sort();
  const daEtapa = lista(/p_etapa IN \(([^)]*)\)/);
  const daFalha = lista(/p_etapa_falha IN \(([^)]*)\)/);
  assert.deepEqual(daEtapa, daFalha, "etapa e etapa_falha divergem");

  const emitidas = new Set<string>(["na_fila", "iniciando"]);
  for (const e of etapas) for (const st of ["ok", "info"] as const) emitidas.add(proximaEtapa(e as never, st));
  for (const e of emitidas) {
    // `desconhecida` é o coringa da RPC e pode ser emitida (Etapa "desconhecida"); o resto TEM que estar na lista.
    assert.ok(e === "desconhecida" || daEtapa.includes(e), `etapa '${e}' emitida pelo reporter mas ausente da lista da RPC (viraria 'desconhecida' em silêncio)`);
  }
});
