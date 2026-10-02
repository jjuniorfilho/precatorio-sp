// FOR-195 — buscarCandidatos (backfill-legado-cumprimento-principal.ts): seleção dos `processos`
// rows que hoje representam, por engano, o CUMPRIMENTO como se fosse a raiz. Banco fake em
// memória, mesmo padrão dos demais testes de orquestração do worker.
import { test } from "node:test";
import assert from "node:assert/strict";
import { supabase } from "./supabase.js";
import { buscarCandidatos } from "./backfill-legado-cumprimento-principal.js";

type Row = Record<string, unknown>;
type Db = Record<string, Row[]>;

// ---- Fake query builder (só o mínimo que este script usa: select/like/not/in) ---------------
class FakeQuery implements PromiseLike<{ data: unknown; error: null }> {
  private filtros: Array<(r: Row) => boolean> = [];
  constructor(private db: Db, private table: string) {}
  select(_cols?: string) { return this; }
  like(col: string, pattern: string) {
    const re = new RegExp("^" + pattern.split("%").map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$");
    this.filtros.push((r) => typeof r[col] === "string" && re.test(r[col] as string));
    return this;
  }
  not(col: string, op: string, _val: unknown) {
    if (op === "is") this.filtros.push((r) => r[col] !== null && r[col] !== undefined);
    return this;
  }
  in(col: string, vals: unknown[]) {
    const set = new Set(vals);
    this.filtros.push((r) => set.has(r[col]));
    return this;
  }
  then<A = { data: unknown; error: null }, B = never>(ok?: ((v: { data: unknown; error: null }) => A | PromiseLike<A>) | null, ko?: ((e: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    const t = this.db[this.table] ?? [];
    const out = t.filter((r) => this.filtros.every((f) => f(r)));
    return Promise.resolve().then(() => ({ data: out, error: null as null })).then(ok, ko);
  }
}

function instala(t: import("node:test").TestContext, db: Db) {
  t.mock.method(supabase, "from", (table: string) => new FakeQuery(db, table));
}

test("buscarCandidatos: pega processos distintos por trás de incidentes LEGADO-% com cumprimento_id preenchido", async (t) => {
  const db: Db = {
    processos: [
      { id: "p1", processo_codigo: "1H0000CUMP1", foro: "0562" },
      { id: "p2", processo_codigo: "1H0000CUMP2", foro: "0100" },
      { id: "p3", processo_codigo: "1H0000NAO_CANDIDATO", foro: "0053" },
    ],
    incidentes: [
      { processo_id: "p1", processo_codigo: "LEGADO-x-00001", cumprimento_id: "c1" },
      { processo_id: "p1", processo_codigo: "LEGADO-x-00002", cumprimento_id: "c1" }, // dedup: mesmo processo 2x
      { processo_id: "p2", processo_codigo: "LEGADO-y-00001", cumprimento_id: "c2" },
      { processo_id: "p3", processo_codigo: "LEGADO-z-00001", cumprimento_id: null }, // sem cumprimento_id -> fora
      { processo_id: "p3", processo_codigo: "1H0000REAL-00001", cumprimento_id: "c3" }, // não-legado -> fora
    ],
  };
  instala(t, db);

  const candidatos = await buscarCandidatos();

  assert.equal(candidatos.length, 2, "dedup por processo_id + exclui cumprimento_id NULL e não-legado");
  const codigos = candidatos.map((c) => c.processoCodigo).sort();
  assert.deepEqual(codigos, ["1H0000CUMP1", "1H0000CUMP2"]);
  const p1 = candidatos.find((c) => c.processoId === "p1")!;
  assert.equal(p1.foro, "0562");
});

test("buscarCandidatos: foro NULL no banco -> string vazia (nunca undefined/null pro caller)", async (t) => {
  const db: Db = {
    processos: [{ id: "p1", processo_codigo: "1H0000SEM_FORO", foro: null }],
    incidentes: [{ processo_id: "p1", processo_codigo: "LEGADO-x-00001", cumprimento_id: "c1" }],
  };
  instala(t, db);

  const [c] = await buscarCandidatos();
  assert.equal(c!.foro, "");
});

test("buscarCandidatos: nenhum incidente legado reconciliado -> lista vazia", async (t) => {
  instala(t, { processos: [], incidentes: [] });
  assert.deepEqual(await buscarCandidatos(), []);
});
