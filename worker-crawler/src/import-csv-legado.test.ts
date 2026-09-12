// Testes da lógica pura de src/import-csv-legado.ts (parsing de CSV, normalização e as funções
// de agrupamento/match extraídas do fluxo de import — ver README.md "Import de CSV legado
// (FOR-143)"). O script em si é one-off e já rodou em produção (24.755 registros); a parte que
// fala com o Supabase (leitura/escrita real) continua validada só manualmente, como documentado
// em .claude/sessions/for-143-importar-precatorios-csv-legado/plan.md. Aqui cobrimos só as
// funções sem I/O, incluindo regressão dos bugs reais encontrados no code-review (FASE 4/6, C3).
//
// Importante: `import-csv-legado.ts` importa (transitivamente) `supabase.ts`, que cria o client
// Supabase no top-level do módulo — por isso o script `test` do package.json seta
// SUPABASE_URL/SUPABASE_SERVICE_ROLE_KEY dummy antes de rodar (só precisa ser uma URL válida;
// nenhuma chamada de rede acontece nestes testes). `main()` só roda quando o arquivo é executado
// diretamente (guard de entrypoint no fim do arquivo), nunca ao importar — ver o `if
// (import.meta.url === ...)` em import-csv-legado.ts.
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseCsvLine,
  normIncidente,
  parseValorCentavos,
  cnjNorm,
  agruparPorChave,
  separarJaExistemEAInserir,
  resolverProcessoRealPorCnj,
  type LinhaCandidata,
  type LinhaCsv,
} from "./import-csv-legado.js";

// ---- parseCsvLine (RFC4180) --------------------------------------------------

test("parseCsvLine: campos simples separados por vírgula", () => {
  assert.deepEqual(parseCsvLine("a,b,c"), ["a", "b", "c"]);
});

test("parseCsvLine: campo entre aspas com vírgula interna não separa", () => {
  assert.deepEqual(parseCsvLine('a,"b,b2",c'), ["a", "b,b2", "c"]);
});

test("parseCsvLine: aspas duplicadas escapam uma aspa literal dentro do campo", () => {
  assert.deepEqual(parseCsvLine('a,"ele disse ""oi""",c'), ["a", 'ele disse "oi"', "c"]);
});

test("parseCsvLine: campo vazio (vírgulas consecutivas) e linha vazia", () => {
  assert.deepEqual(parseCsvLine("a,,c"), ["a", "", "c"]);
  assert.deepEqual(parseCsvLine(""), [""]);
});

test("parseCsvLine: header real do dump legado", () => {
  const header = "depre_number,creditor_name,creditor_document,creditor_total_amount,update_base_date,order_number,oc_number,origin_process_number,incident_number,debtor_entity,decision_date";
  assert.deepEqual(parseCsvLine(header), [
    "depre_number", "creditor_name", "creditor_document", "creditor_total_amount", "update_base_date",
    "order_number", "oc_number", "origin_process_number", "incident_number", "debtor_entity", "decision_date",
  ]);
});

// ---- normIncidente ------------------------------------------------------------

// Regressão FASE 4 (plan.md): numero_incidente vem com padding diferente por fonte — banco usa
// 5 dígitos ("00003"), CSV legado usa 4 ("0003"). Comparação de string exata fazia todo match
// falhar na primeira rodada em produção; fix foi comparar pelo valor numérico.
test("normIncidente: tolera padding diferente entre fontes (regressão FASE 4)", () => {
  assert.equal(normIncidente("00003"), normIncidente("0003"));
  assert.equal(normIncidente("00003"), "3");
  assert.equal(normIncidente("0003"), "3");
});

test("normIncidente: null/vazio vira string vazia (nunca colide com um número real)", () => {
  assert.equal(normIncidente(null), "");
  assert.equal(normIncidente(""), "");
  assert.notEqual(normIncidente(null), normIncidente("0"));
});

// ---- parseValorCentavos --------------------------------------------------------

test("parseValorCentavos: converte string decimal (ponto) para centavos, arredondando", () => {
  assert.equal(parseValorCentavos("1234.56"), 123456);
  assert.equal(parseValorCentavos("0.01"), 1);
  assert.equal(parseValorCentavos("100"), 10000);
});

test("parseValorCentavos: string vazia -> null (campo ausente no CSV)", () => {
  assert.equal(parseValorCentavos(""), null);
});

// Regressão do achado do code-review citado no comentário da função: `Math.round(parseFloat(...))`
// sem validação aceitava qualquer lixo e gravava um valor truncado/errado silenciosamente (ex.:
// formato pt-BR "1234,56" seria parseado como 1234, perdendo os centavos sem erro nenhum).
test("parseValorCentavos: formato inesperado (ex.: vírgula decimal pt-BR) lança em vez de truncar silenciosamente", () => {
  assert.throws(() => parseValorCentavos("1234,56"), /formato inesperado/);
  assert.throws(() => parseValorCentavos("R$ 1234.56"), /formato inesperado/);
  assert.throws(() => parseValorCentavos("abc"), /formato inesperado/);
});

// ---- cnjNorm --------------------------------------------------------------------

test("cnjNorm: remove tudo que não é dígito", () => {
  assert.equal(cnjNorm("0015695-63.2022.8.26.0053"), "00156956320228260053");
  assert.equal(cnjNorm("00156956320228260053").length, 20);
});

// ---- agruparPorChave -------------------------------------------------------------

// Regressão FASE 6 (plan.md): o código original usava `Map<chave, valor único>` — uma colisão de
// chave sobrescrevia a linha anterior e perdia matches (achado real em produção: numero_depre
// repetido em 2 incidentes de processos diferentes gerou 3.069 falsos "a inserir"). O fix agrupa
// TODAS as ocorrências por chave, nunca sobrescrevendo.
test("agruparPorChave: preserva todas as linhas em colisão de chave (regressão FASE 6)", () => {
  const rows = [
    { id: "inc-A", numero_depre: "999" },
    { id: "inc-B", numero_depre: "999" }, // mesmo numero_depre, processo/linha diferente
    { id: "inc-C", numero_depre: "111" },
  ];
  const grupos = agruparPorChave(rows, (r) => r.numero_depre);
  assert.equal(grupos.size, 2);
  assert.deepEqual(grupos.get("999")!.map((r) => r.id), ["inc-A", "inc-B"]);
  assert.deepEqual(grupos.get("111")!.map((r) => r.id), ["inc-C"]);
});

test("agruparPorChave: ignora linhas sem chave (null/undefined/vazio)", () => {
  const rows = [{ id: "1", k: "x" }, { id: "2", k: null }, { id: "3", k: "" }];
  const grupos = agruparPorChave(rows, (r) => r.k);
  assert.deepEqual([...grupos.keys()], ["x"]);
});

// ---- separarJaExistemEAInserir ----------------------------------------------------

function candidata(over: Partial<LinhaCandidata> & Pick<LinhaCandidata, "cnjNorm" | "numeroIncidente" | "numeroDepre">): LinhaCandidata {
  const linhaBase: LinhaCsv = {
    depre_number: over.numeroDepre, creditor_name: "CREDOR TESTE", creditor_document: "",
    creditor_total_amount: "", update_base_date: "", order_number: "", oc_number: "",
    origin_process_number: "", incident_number: over.numeroIncidente, debtor_entity: "", decision_date: "",
  };
  return { linha: linhaBase, cnjRaiz: over.cnjNorm, ...over } as LinhaCandidata;
}

test("separarJaExistemEAInserir: match exige MESMO processo_id nos dois mapas, não só numero_depre igual (regressão FASE 6/C2)", () => {
  // Dois processos distintos (A e B) têm incidentes com o MESMO numero_depre "999" — cenário
  // real confirmado em produção (numero_depre não é UNIQUE). A candidata pertence ao processo A;
  // não pode "casar" com o incidente do processo B só por coincidência de numero_depre.
  const c = candidata({ cnjNorm: "cnjA", numeroIncidente: "0003", numeroDepre: "999" });
  const processosPorCnj = new Map([
    ["cnjA", [{ id: "proc-A", processoCodigo: "REAL-A" }]],
  ]);
  const incidentesPorDepre = new Map([
    ["999", [
      { processo_id: "proc-B", numero_incidente: "00003" }, // processo B, não relacionado — não deve casar
    ]],
  ]);
  const { jaExistem, aInserir } = separarJaExistemEAInserir([c], processosPorCnj, incidentesPorDepre);
  assert.equal(jaExistem.length, 0);
  assert.equal(aInserir.length, 1);
});

test("separarJaExistemEAInserir: casa quando processo_id bate E numero_incidente bate (com padding diferente)", () => {
  const c = candidata({ cnjNorm: "cnjA", numeroIncidente: "0003", numeroDepre: "999" });
  const processosPorCnj = new Map([
    ["cnjA", [{ id: "proc-A", processoCodigo: "REAL-A" }]],
  ]);
  const incidentesPorDepre = new Map([
    ["999", [{ processo_id: "proc-A", numero_incidente: "00003" }]], // 5 dígitos no banco vs. 4 no CSV
  ]);
  const { jaExistem, aInserir } = separarJaExistemEAInserir([c], processosPorCnj, incidentesPorDepre);
  assert.equal(jaExistem.length, 1);
  assert.equal(aInserir.length, 0);
});

test("separarJaExistemEAInserir: sem nenhum match (cnj novo) vai pra aInserir", () => {
  const c = candidata({ cnjNorm: "cnjZ", numeroIncidente: "0001", numeroDepre: "123" });
  const { jaExistem, aInserir } = separarJaExistemEAInserir([c], new Map(), new Map());
  assert.equal(jaExistem.length, 0);
  assert.equal(aInserir.length, 1);
});

// ---- resolverProcessoRealPorCnj ----------------------------------------------------

// Regressão C3 (plan.md): import criava um `processos` LEGADO- duplicado quando um processo REAL
// (não-LEGADO) já existia pro mesmo cnj_normalizado — confirmado em produção (96 duplicatas).
// O fix resolve o id real primeiro (por cnj_normalizado), pra reusar em vez de duplicar.
test("resolverProcessoRealPorCnj: prefere a linha REAL quando LEGADO- e real coexistem pro mesmo cnj (regressão C3)", () => {
  const processosPorCnj = new Map([
    ["cnjA", [
      { id: "id-legado", processoCodigo: "LEGADO-cnjA" },
      { id: "id-real", processoCodigo: "1234567-89.2020.8.26.0053" },
    ]],
  ]);
  const real = resolverProcessoRealPorCnj(processosPorCnj);
  assert.equal(real.get("cnjA"), "id-real");
});

test("resolverProcessoRealPorCnj: só LEGADO- (sem real ainda) não entra no mapa — cria placeholder normalmente", () => {
  const processosPorCnj = new Map([
    ["cnjB", [{ id: "id-legado", processoCodigo: "LEGADO-cnjB" }]],
  ]);
  const real = resolverProcessoRealPorCnj(processosPorCnj);
  assert.equal(real.has("cnjB"), false);
});
