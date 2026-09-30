// FOR-178 — persistTree reconcilia a linha `processos` LEGADO- cujo CNJ é o do CUMPRIMENTO (não da
// raiz). Não havia teste nenhum pra reconcileLegadoProcesso/persistTree. Este arquivo troca
// `supabase.from`/`supabase.rpc` por um banco FAKE em memória (query builder mínimo: select/eq/like/
// single/maybeSingle/upsert/update/delete/insert) e simula as 3 RPCs de merge em JS com a mesma
// semântica do SQL (sql/2026-08-19_for143_merge_legado_rpcs.sql e
// sql/2026-09-29_for178_merge_legado_processo_para_cumprimento.sql). O SQL real é validado à parte
// em sql/sandbox/for178_validate_local.sh — aqui o alvo é a ORQUESTRAÇÃO do worker (ordem das
// chamadas, recarga do Map de incidentes legado, idempotência).
//
// Caso real: DEPRE 0088499-12.2023.8.26.0500, cumprimento 0016525-29.2022.8.26.0053, raiz real
// 0023830-02.2001.8.26.0053.
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { supabase, persistTree } from "./supabase.js";
import { config } from "./config.js";
import type { ProcessoTree } from "./types.js";

type Row = Record<string, unknown> & { id: string };
type Db = Record<string, Row[]>;

const DEPRE = "0088499-12.2023.8.26.0500";
const CNJ_CUMP = "0016525-29.2022.8.26.0053";
const CNJ_RAIZ = "0023830-02.2001.8.26.0053";
const norm = (s: string) => s.replace(/\D/g, "");

const LEGADO_PROC_ID = "11111111-1111-1111-1111-111111111111";
const LEGADO_INC_ID = "22222222-2222-2222-2222-222222222222";

function novoDb(): Db {
  return { processos: [], cumprimentos: [], incidentes: [], partes: [], andamentos: [] };
}

/** Estado pós-import legado (FOR-143): processo "fake" com cnj = CUMPRIMENTO + incidente sem cumprimento_id. */
function semeiaLegado(db: Db): void {
  db.processos!.push({ id: LEGADO_PROC_ID, processo_codigo: `LEGADO-${norm(CNJ_CUMP)}`, cnj: CNJ_CUMP, cnj_normalizado: norm(CNJ_CUMP) });
  db.incidentes!.push({
    id: LEGADO_INC_ID, processo_id: LEGADO_PROC_ID, cumprimento_id: null,
    processo_codigo: `LEGADO-${norm(CNJ_CUMP)}-00001`, numero_depre: DEPRE, cnj: CNJ_CUMP,
  });
  db.partes!.push({ id: randomUUID(), incidente_id: LEGADO_INC_ID, processo_id: LEGADO_PROC_ID, papel: "ativa", nome: "CREDOR LEGADO" });
}

function arvore(cumprimentoCnj = CNJ_CUMP, raizCnj = CNJ_RAIZ): ProcessoTree {
  return {
    processo_codigo: "1H0000RAIZ", cnj: raizCnj, foro: null, classe: null, assunto: null,
    distribuicao: null, valor_acao: null, data_base: null, status: "ativo",
    cumprimentos: [{
      processo_codigo: "1H0000CUMP", cnj: cumprimentoCnj,
      incidentes: [{
        processo_codigo: "1H0000INC1", numero_incidente: "00001", tipo_previsto: "Precatorio",
        numero_depre: DEPRE, cnj: DEPRE, status: "ativo", tramitacao_prioritaria: false,
        valor_acao: 100000, data_base: null,
        partes_ativas: [{ nome: "CREDOR REAL", documento: null, advogados: [] }],
        parte_passiva: { nome: "ESTADO DE SÃO PAULO", ente_esfera: "Estadual" },
        andamentos: [{ data: "2023-01-01", descricao: "Expedido ofício", arquivo_url: null }],
      }],
    }],
  };
}

// ---- Fake query builder ------------------------------------------------------
type Filtro = (r: Row) => boolean;
class FakeQuery implements PromiseLike<{ data: unknown; error: null }> {
  private op: "select" | "upsert" | "update" | "delete" | "insert" = "select";
  private filtros: Filtro[] = [];
  private payload: Record<string, unknown>[] = [];
  private patch: Record<string, unknown> = {};
  private upsertOpts: { onConflict?: string; ignoreDuplicates?: boolean } = {};
  private modo: "many" | "single" | "maybe" = "many";
  constructor(private db: Db, private table: string) {}

  select(_cols?: string) { return this; }
  eq(col: string, v: unknown) { this.filtros.push((r) => r[col] === v); return this; }
  like(col: string, pattern: string) {
    const re = new RegExp("^" + pattern.split("%").map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$");
    this.filtros.push((r) => typeof r[col] === "string" && re.test(r[col] as string));
    return this;
  }
  single() { this.modo = "single"; return this; }
  maybeSingle() { this.modo = "maybe"; return this; }
  upsert(rows: Record<string, unknown> | Record<string, unknown>[], opts: { onConflict?: string; ignoreDuplicates?: boolean } = {}) {
    this.op = "upsert"; this.payload = Array.isArray(rows) ? rows : [rows]; this.upsertOpts = opts; return this;
  }
  update(patch: Record<string, unknown>) { this.op = "update"; this.patch = patch; return this; }
  delete() { this.op = "delete"; return this; }
  insert(rows: Record<string, unknown> | Record<string, unknown>[]) { this.op = "insert"; this.payload = Array.isArray(rows) ? rows : [rows]; return this; }

  private run(): unknown {
    const t = (this.db[this.table] ??= []);
    const match = (r: Row) => this.filtros.every((f) => f(r));
    let out: Row[] = [];
    switch (this.op) {
      case "select": out = t.filter(match); break;
      case "update": out = t.filter(match); out.forEach((r) => Object.assign(r, this.patch)); break;
      case "delete": this.db[this.table] = t.filter((r) => !match(r)); break;
      case "insert": out = this.payload.map((p) => ({ id: randomUUID(), ...p }) as Row); t.push(...out); break;
      case "upsert": {
        const keys = (this.upsertOpts.onConflict ?? "id").split(",");
        for (const p of this.payload) {
          const ex = t.find((r) => keys.every((k) => r[k] === p[k]));
          if (ex) { if (!this.upsertOpts.ignoreDuplicates) Object.assign(ex, p); out.push(ex); }
          else { const novo = { id: randomUUID(), ...p } as Row; t.push(novo); out.push(novo); }
        }
        // unique(processo_codigo) — o fake grita se o worker tentar violar (ex.: rename colidindo)
        const cods = t.map((r) => r.processo_codigo).filter((c) => c !== undefined);
        assert.equal(new Set(cods).size, cods.length, `unique processo_codigo violada em ${this.table}`);
        break;
      }
    }
    const copia = out.map((r) => ({ ...r }));
    if (this.modo === "single") { assert.equal(copia.length, 1, `.single() em ${this.table} sem exatamente 1 linha`); return copia[0]; }
    if (this.modo === "maybe") return copia[0] ?? null;
    return copia;
  }

  then<A = { data: unknown; error: null }, B = never>(ok?: ((v: { data: unknown; error: null }) => A | PromiseLike<A>) | null, ko?: ((e: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    return Promise.resolve().then(() => ({ data: this.run(), error: null as null })).then(ok, ko);
  }
}

// ---- RPCs fake (mesma semântica do SQL) -------------------------------------
function rpcFake(db: Db, chamadas: Array<[string, Record<string, string>]>, falhar?: string) {
  return async (nome: string, a: Record<string, string>) => {
    chamadas.push([nome, a]);
    if (nome === falhar) return { data: null, error: { message: "boom" } };
    if (nome === "merge_legado_processo") {
      if (a.p_legado_id === a.p_real_id) return { data: null, error: null };
      for (const t of ["incidentes", "partes"]) db[t]!.forEach((r) => { if (r.processo_id === a.p_legado_id) r.processo_id = a.p_real_id; });
      db.processos = db.processos!.filter((r) => r.id !== a.p_legado_id);
    } else if (nome === "merge_legado_incidente") {
      if (a.p_legado_id === a.p_real_id) return { data: null, error: null };
      db.partes = db.partes!.filter((r) => r.incidente_id !== a.p_legado_id);
      db.andamentos = db.andamentos!.filter((r) => r.incidente_id !== a.p_legado_id);
      db.incidentes = db.incidentes!.filter((r) => r.id !== a.p_legado_id);
    } else if (nome === "merge_legado_processo_para_cumprimento") {
      const { p_legado_processo_id: leg, p_real_processo_id: real, p_real_cumprimento_id: cump } = a;
      if (leg === real) return { data: null, error: null };
      if (!db.processos!.some((r) => r.id === leg && String(r.processo_codigo).startsWith("LEGADO-"))) return { data: null, error: null };
      if (!db.cumprimentos!.some((r) => r.id === cump && r.processo_id === real)) return { data: null, error: { message: "cumprimento não pertence ao processo" } };
      db.incidentes!.forEach((r) => { if (r.processo_id === leg) { r.processo_id = real; r.cumprimento_id = r.cumprimento_id ?? cump; } });
      db.partes!.forEach((r) => { if (r.processo_id === leg) r.processo_id = real; });
      db.cumprimentos!.forEach((r) => { if (r.processo_id === leg) r.processo_id = real; });
      db.processos = db.processos!.filter((r) => r.id !== leg);
    } else {
      throw new Error(`RPC inesperada no teste: ${nome}`);
    }
    return { data: null, error: null };
  };
}

function instala(t: import("node:test").TestContext, db: Db, falhar?: string) {
  const chamadas: Array<[string, Record<string, string>]> = [];
  t.mock.method(supabase, "from", (table: string) => new FakeQuery(db, table));
  t.mock.method(supabase, "rpc", rpcFake(db, chamadas, falhar));
  return chamadas;
}

function conferePosMerge(db: Db, rotulo: string): Row {
  const incs = db.incidentes!.filter((r) => r.numero_depre === DEPRE);
  assert.equal(incs.length, 1, `${rotulo}: exatamente 1 incidente pro numero_depre`);
  const inc = incs[0]!;
  const raiz = db.processos!.find((r) => r.cnj === CNJ_RAIZ)!;
  const cump = db.cumprimentos!.find((r) => r.cnj === CNJ_CUMP)!;
  assert.ok(raiz && cump, `${rotulo}: raiz e cumprimento reais existem`);
  assert.equal(inc.processo_id, raiz.id, `${rotulo}: processo_id = raiz real`);
  assert.equal(inc.cumprimento_id, cump.id, `${rotulo}: cumprimento_id preenchido com o cumprimento real`);
  assert.equal(inc.processo_codigo, "1H0000INC1", `${rotulo}: processo_codigo real do e-SAJ`);
  assert.equal(db.processos!.filter((r) => String(r.processo_codigo).startsWith("LEGADO-")).length, 0, `${rotulo}: sem processos LEGADO- órfão`);
  assert.equal(db.processos!.length, 1, `${rotulo}: só a raiz em processos`);
  assert.ok(db.partes!.every((p) => p.processo_id === raiz.id), `${rotulo}: nenhuma parte aponta pra processo inexistente`);
  return inc;
}

// ---- Cenários ----------------------------------------------------------------
test("FOR-178: 1º crawl funde a linha LEGADO- do CUMPRIMENTO — 1 incidente, com cumprimento_id, legado apagado", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const chamadas = instala(t, db);

  const processoId = await persistTree(arvore());

  const inc = conferePosMerge(db, "1º crawl");
  assert.equal(inc.id, LEGADO_INC_ID, "o incidente legado é COMPLETADO (rename + upsert), não recriado");
  assert.equal(db.processos![0]!.id, processoId);
  const merge = chamadas.filter(([n]) => n === "merge_legado_processo_para_cumprimento");
  assert.equal(merge.length, 1);
  assert.deepEqual(merge[0]![1], {
    p_legado_processo_id: LEGADO_PROC_ID,
    p_real_processo_id: processoId,
    p_real_cumprimento_id: db.cumprimentos![0]!.id,
  });
  assert.deepEqual(db.partes!.filter((p) => p.incidente_id === LEGADO_INC_ID).map((p) => p.nome), ["CREDOR REAL", "ESTADO DE SÃO PAULO"], "partes do e-SAJ substituem as do legado");
});

test("FOR-178: idempotente — 2º crawl da mesma árvore não duplica, não erra e não chama RPC de merge", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const chamadas = instala(t, db);

  await persistTree(arvore());
  const snapshot = JSON.stringify({ ...db, andamentos: db.andamentos!.length });
  const antes = chamadas.length;
  await persistTree(arvore());

  const inc = conferePosMerge(db, "2º crawl");
  assert.equal(inc.id, LEGADO_INC_ID);
  assert.equal(db.cumprimentos!.length, 1);
  assert.equal(db.andamentos!.length, 1, "andamentos idempotentes (hash)");
  assert.equal(chamadas.slice(antes).length, 0, "nenhuma RPC no 2º crawl");
  assert.equal(JSON.stringify({ ...db, andamentos: db.andamentos!.length }).replace(/"id":"[^"]+","incidente_id"/g, ""),
    snapshot.replace(/"id":"[^"]+","incidente_id"/g, ""), "estado igual (ids de partes recriadas à parte)");
});

test("FOR-178: hierarquia paralela já existente (crawl pré-fix) — merge limpa a duplicata e mantém o incidente REAL", async (t) => {
  const db = novoDb();
  const chamadas = instala(t, db);
  // Crawl antigo, SEM legado: cria raiz/cumprimento/incidente reais.
  const realProcId = await persistTree(arvore());
  const realIncId = db.incidentes![0]!.id;
  // Estado de produção hoje: legado órfão convivendo com a hierarquia real.
  semeiaLegado(db);
  assert.equal(db.incidentes!.filter((r) => r.numero_depre === DEPRE).length, 2, "reproduz a duplicata");

  const processoId = await persistTree(arvore());

  assert.equal(processoId, realProcId);
  const inc = conferePosMerge(db, "paralela");
  assert.equal(inc.id, realIncId, "sobrevive o incidente real (e-SAJ prevalece)");
  assert.ok(chamadas.some(([n, a]) => n === "merge_legado_incidente" && a.p_legado_id === LEGADO_INC_ID && a.p_real_id === realIncId));
});

test("FOR-178: cumprimento == raiz (legado já reconciliado no nível do processo) — não chama a RPC nova", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const chamadas = instala(t, db);

  // Árvore cujo CNJ raiz é o próprio CNJ legado: reconcileLegadoProcesso renomeia a linha legado.
  await persistTree(arvore(CNJ_CUMP, CNJ_CUMP));

  assert.equal(chamadas.filter(([n]) => n === "merge_legado_processo_para_cumprimento").length, 0);
  assert.equal(db.processos!.length, 1);
  assert.equal(db.processos![0]!.id, LEGADO_PROC_ID, "linha legado renomeada in-place (caminho FOR-143 inalterado)");
  assert.equal(db.incidentes!.length, 1);
  assert.ok(db.incidentes![0]!.cumprimento_id);
});

test("FOR-178: LEGADO_RECONCILE=false — não procura nem funde nada (gate do FOR-143 respeitado)", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const chamadas = instala(t, db);
  const antes = config.legadoReconcile;
  (config as { legadoReconcile: boolean }).legadoReconcile = false;
  t.after(() => { (config as { legadoReconcile: boolean }).legadoReconcile = antes; });

  await persistTree(arvore());

  assert.equal(chamadas.length, 0);
  assert.ok(db.processos!.some((r) => r.id === LEGADO_PROC_ID), "legado intocado");
});

test("FOR-178: erro da RPC nova propaga com o nome da RPC", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  instala(t, db, "merge_legado_processo_para_cumprimento");
  await assert.rejects(() => persistTree(arvore()), /merge_legado_processo_para_cumprimento: boom/);
});

// ---- Cenários extras (achados do code review / test planner no pre-pr) -------
const CNJ_OUTRO_CUMP = "0009999-11.2020.8.26.0053";
const DEPRE_Y = "0077777-00.2023.8.26.0500";

function incidente(processo_codigo: string, numero_depre: string): ProcessoTree["cumprimentos"][number]["incidentes"][number] {
  return { ...arvore().cumprimentos[0]!.incidentes[0]!, processo_codigo, numero_depre, cnj: numero_depre };
}
function arvoreCom(cumprimentos: ProcessoTree["cumprimentos"]): ProcessoTree {
  return { ...arvore(), cumprimentos };
}

test("FOR-178: 2 cumprimentos — legado pendurado no B, incidente real do mesmo DEPRE sob o A → 1 linha, sob o A", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const chamadas = instala(t, db);

  await persistTree(arvoreCom([
    { processo_codigo: "1H0000CUMPA", cnj: CNJ_OUTRO_CUMP, incidentes: [incidente("1H0000INC1", DEPRE)] },
    { processo_codigo: "1H0000CUMP", cnj: CNJ_CUMP, incidentes: [] },
  ]));

  const incs = db.incidentes!.filter((r) => r.numero_depre === DEPRE);
  assert.equal(incs.length, 1, "sem duplicata mesmo com o real num cumprimento anterior");
  const cumpA = db.cumprimentos!.find((r) => r.processo_codigo === "1H0000CUMPA")!;
  const cumpB = db.cumprimentos!.find((r) => r.processo_codigo === "1H0000CUMP")!;
  assert.equal(incs[0]!.cumprimento_id, cumpA.id, "fica no cumprimento onde o e-SAJ o mostra");
  const merge = chamadas.filter(([n]) => n === "merge_legado_processo_para_cumprimento");
  assert.equal(merge.length, 1);
  assert.equal(merge[0]![1].p_real_cumprimento_id, cumpB.id, "a RPC usa o cumprimento cujo CNJ casou com o legado");
  assert.equal(db.processos!.filter((r) => String(r.processo_codigo).startsWith("LEGADO-")).length, 0);
});

test("FOR-178: legado com DEPRE que o e-SAJ não devolveu — sobrevive, reapontado pra raiz/cumprimento reais, com partes", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const incY = "33333333-3333-3333-3333-333333333333";
  db.incidentes!.push({ id: incY, processo_id: LEGADO_PROC_ID, cumprimento_id: null, processo_codigo: `LEGADO-${norm(CNJ_CUMP)}-00002`, numero_depre: DEPRE_Y, cnj: CNJ_CUMP });
  db.partes!.push({ id: randomUUID(), incidente_id: incY, processo_id: LEGADO_PROC_ID, papel: "ativa", nome: "CREDOR Y" });
  instala(t, db);

  const processoId = await persistTree(arvore());

  const incsX = db.incidentes!.filter((r) => r.numero_depre === DEPRE);
  assert.equal(incsX.length, 1);
  assert.equal(incsX[0]!.cumprimento_id, db.cumprimentos![0]!.id);
  assert.equal(db.processos!.length, 1, "linha legado apagada");
  const y = db.incidentes!.find((r) => r.id === incY)!;
  assert.ok(y, "incidente Y não foi apagado em cascata");
  assert.equal(y.processo_id, processoId);
  assert.equal(y.cumprimento_id, db.cumprimentos![0]!.id);
  assert.ok(String(y.processo_codigo).startsWith("LEGADO-"), "continua LEGADO- (sem par no e-SAJ)");
  assert.deepEqual(db.partes!.filter((p) => p.incidente_id === incY).map((p) => p.nome), ["CREDOR Y"]);
  assert.ok(db.partes!.every((p) => p.processo_id === processoId));
});

test("FOR-178: LEGADO- na raiz E no cumprimento com o mesmo DEPRE — sem unique violation, 1 incidente", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const raizLegId = "44444444-4444-4444-4444-444444444444";
  db.processos!.push({ id: raizLegId, processo_codigo: `LEGADO-${norm(CNJ_RAIZ)}`, cnj: CNJ_RAIZ, cnj_normalizado: norm(CNJ_RAIZ) });
  db.incidentes!.push({ id: randomUUID(), processo_id: raizLegId, cumprimento_id: null, processo_codigo: `LEGADO-${norm(CNJ_RAIZ)}-00001`, numero_depre: DEPRE, cnj: CNJ_RAIZ });
  instala(t, db);

  const processoId = await persistTree(arvore());

  assert.equal(processoId, raizLegId, "legado da raiz renomeado in-place (FOR-143)");
  conferePosMerge(db, "raiz+cumprimento");
  await persistTree(arvore());
  conferePosMerge(db, "raiz+cumprimento 2º crawl");
});

test("FOR-178: 2 linhas LEGADO- com o mesmo cnj_normalizado (import duplicado) — funde ambas, 1 incidente", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  const dupId = "55555555-5555-5555-5555-555555555555";
  db.processos!.push({ id: dupId, processo_codigo: `LEGADO-${CNJ_CUMP}`, cnj: CNJ_CUMP, cnj_normalizado: norm(CNJ_CUMP) });
  db.incidentes!.push({ id: randomUUID(), processo_id: dupId, cumprimento_id: null, processo_codigo: `LEGADO-${CNJ_CUMP}-00001`, numero_depre: DEPRE, cnj: CNJ_CUMP });
  const chamadas = instala(t, db);

  await persistTree(arvore());

  conferePosMerge(db, "legado duplicado");
  assert.equal(chamadas.filter(([n]) => n === "merge_legado_processo_para_cumprimento").length, 2);
});

test("FOR-178: 2 incidentes crawleados com o mesmo DEPRE — o legado é consumido pelo 1º e não 'migra' pro 2º", async (t) => {
  const db = novoDb();
  semeiaLegado(db);
  instala(t, db);

  await persistTree(arvoreCom([
    { processo_codigo: "1H0000CUMP", cnj: CNJ_CUMP, incidentes: [incidente("1H0000INC1", DEPRE), incidente("1H0000INC2", DEPRE)] },
  ]));

  const inc1 = db.incidentes!.find((r) => r.processo_codigo === "1H0000INC1")!;
  const inc2 = db.incidentes!.find((r) => r.processo_codigo === "1H0000INC2")!;
  assert.equal(inc1.id, LEGADO_INC_ID, "o legado virou o INC1 e ficou nele");
  assert.notEqual(inc2.id, LEGADO_INC_ID);
  assert.equal(db.incidentes!.length, 2);
  assert.equal(db.incidentes!.filter((r) => String(r.processo_codigo).startsWith("LEGADO-")).length, 0);
});
