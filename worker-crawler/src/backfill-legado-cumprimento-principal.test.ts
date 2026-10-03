// FOR-195 — buscarCandidatos + seedDoCandidato (backfill-legado-cumprimento-principal.ts):
// seleção dos `processos` rows que hoje representam, por engano, o CUMPRIMENTO como se fosse a
// raiz. Banco fake em memória, mesmo padrão dos demais testes de orquestração do worker.
//
// Achado de code-review (FOR-195): a 1ª versão filtrava via `incidentes.cumprimento_id IS NOT
// NULL` (proxy que só pegava ~200 dos ~11.202 candidatos reais). Estes testes cobrem a versão
// corrigida: direto em `processos.processo_codigo LIKE 'LEGADO-%'`, com paginação, e a derivação
// de seed (código real vs CNJ) que o bug também exigia.
import { test } from "node:test";
import assert from "node:assert/strict";
import { supabase } from "./supabase.js";
import { buscarCandidatos, seedDoCandidato } from "./backfill-legado-cumprimento-principal.js";

type Row = Record<string, unknown>;
type Db = Record<string, Row[]>;

// ---- Fake query builder (só o mínimo que este script usa: select/like/order/range) -------------
class FakeQuery implements PromiseLike<{ data: unknown; error: null }> {
  private filtros: Array<(r: Row) => boolean> = [];
  private rangeArgs: [number, number] | null = null;
  private orderCol: string | null = null;
  constructor(private db: Db, private table: string) {}
  select(_cols?: string) { return this; }
  like(col: string, pattern: string) {
    const re = new RegExp("^" + pattern.split("%").map((p) => p.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*") + "$");
    this.filtros.push((r) => typeof r[col] === "string" && re.test(r[col] as string));
    return this;
  }
  order(col: string) { this.orderCol = col; return this; }
  range(from: number, to: number) { this.rangeArgs = [from, to]; return this; }
  then<A = { data: unknown; error: null }, B = never>(ok?: ((v: { data: unknown; error: null }) => A | PromiseLike<A>) | null, ko?: ((e: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    const t = this.db[this.table] ?? [];
    let out = t.filter((r) => this.filtros.every((f) => f(r)));
    // Simula ORDER BY de verdade: sem isso, .range() em paginação repetida não tem como ser
    // testado fielmente (a instabilidade real só aparece no Postgres de produção — ver comentário
    // em buscarCandidatos). Com .order(), a fake ao menos garante que a paginação em si (slice
    // consecutivo sobre uma ordem FIXA) nem duplica nem pula linhas.
    if (this.orderCol) out = [...out].sort((a, b) => String(a[this.orderCol!]).localeCompare(String(b[this.orderCol!])));
    if (this.rangeArgs) out = out.slice(this.rangeArgs[0], this.rangeArgs[1] + 1);
    return Promise.resolve().then(() => ({ data: out, error: null as null })).then(ok, ko);
  }
}

function instala(t: import("node:test").TestContext, db: Db) {
  t.mock.method(supabase, "from", (table: string) => new FakeQuery(db, table));
}

test("buscarCandidatos: pega direto de processos.processo_codigo LIKE 'LEGADO-%' (sem depender de incidentes.cumprimento_id)", async (t) => {
  const db: Db = {
    processos: [
      { id: "p1", processo_codigo: "LEGADO-x-00001", cnj: "0018028-13.2022.8.26.0562", foro: "0562" },
      { id: "p2", processo_codigo: "LEGADO-y-00001", cnj: null, foro: "0100" },
      { id: "p3", processo_codigo: "1H0000NAO_CANDIDATO", cnj: "9999999-99.2022.8.26.0053", foro: "0053" },
    ],
  };
  instala(t, db);

  const candidatos = await buscarCandidatos();

  assert.equal(candidatos.length, 2, "só processo_codigo LEGADO-%, independente de incidentes");
  const ids = candidatos.map((c) => c.processoId).sort();
  assert.deepEqual(ids, ["p1", "p2"]);
});

test("buscarCandidatos: foro NULL no banco -> string vazia (nunca undefined/null pro caller)", async (t) => {
  const db: Db = { processos: [{ id: "p1", processo_codigo: "LEGADO-x-00001", cnj: null, foro: null }] };
  instala(t, db);

  const [c] = await buscarCandidatos();
  assert.equal(c!.foro, "");
});

test("buscarCandidatos: nenhum processo LEGADO- -> lista vazia", async (t) => {
  instala(t, { processos: [] });
  assert.deepEqual(await buscarCandidatos(), []);
});

test("buscarCandidatos: pagina em lotes de 1000 via .range() (população real ultrapassa o default do REST)", async (t) => {
  // Ordem de inserção INVERTIDA de propósito (id1499 primeiro, id0 por último) — sem
  // `.order("id")` na query real, a paginação por `.range()` não tem garantia de ordem estável
  // entre as 2 chamadas; este teste cobre que a dedupe/completude depende da ordenação explícita,
  // não da ordem "por acaso" de inserção.
  const processos: Row[] = Array.from({ length: 1500 }, (_, i) => 1499 - i)
    .map((i) => ({ id: `p${String(i).padStart(5, "0")}`, processo_codigo: `LEGADO-x-${String(i).padStart(5, "0")}`, cnj: null, foro: "0562" }));
  instala(t, { processos });

  const candidatos = await buscarCandidatos();
  assert.equal(candidatos.length, 1500, "junta as 2 páginas (1000 + 500) sem duplicar nem pular, mesmo com ordem de inserção embaralhada");
  const ids = new Set(candidatos.map((c) => c.processoId));
  assert.equal(ids.size, 1500, "nenhum id duplicado entre as páginas");
});

test("seedDoCandidato: processo_codigo LEGADO- -> usa o cnj como seed (não é um código e-SAJ válido)", () => {
  const seed = seedDoCandidato({ processoId: "p1", processoCodigo: "LEGADO-x-00001", cnj: "0018028-13.2022.8.26.0562", foro: "0562" });
  assert.equal(seed, "0018028-13.2022.8.26.0562");
});

test("seedDoCandidato: processo_codigo já é código e-SAJ real -> usa ele direto (caso já promovido por outro crawl)", () => {
  const seed = seedDoCandidato({ processoId: "p1", processoCodigo: "1H0000CUMP1", cnj: "0018028-13.2022.8.26.0562", foro: "0562" });
  assert.equal(seed, "1H0000CUMP1");
});

test("seedDoCandidato: LEGADO- sem cnj conhecido -> null (sem ponto de entrada no e-SAJ)", () => {
  const seed = seedDoCandidato({ processoId: "p1", processoCodigo: "LEGADO-x-00001", cnj: null, foro: "0562" });
  assert.equal(seed, null);
});
