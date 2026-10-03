// FOR-195 — reconcilePrincipalReal (supabase.ts): orquestração da reconciliação da AÇÃO
// PRINCIPAL REAL acima do cumprimento, pros ~24.292 incidentes legado que a FOR-178 já
// reconciliou até o nível do cumprimento. Mesmo padrão de teste de
// supabase-persist-tree-legado.test.ts: troca `supabase.from`/`supabase.rpc` por um banco FAKE
// em memória e simula a RPC nova (sql/2026-10-02_for195_merge_legado_cumprimento_para_principal.sql)
// em JS com a mesma semântica — o SQL real é validado à parte em
// sql/sandbox/for195_validate_local.sh.
//
// Caso real: DEPRE 0436868-90.2025.8.26.0500, cumprimento 0018028-13.2022.8.26.0562, ação
// principal 1000594-91.2022.8.26.0562.
import { test } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { supabase, reconcilePrincipalReal } from "./supabase.js";
import type { ProcessoPrincipalInfo } from "./types.js";

type Row = Record<string, unknown> & { id: string };
type Db = Record<string, Row[]>;

const CODIGO_CUMP = "1H0000CUMP";
const CODIGO_PRINC = "1H0000PRINC";
const CNJ_PRINCIPAL = "1000594-91.2022.8.26.0562";

const PROCESSO_ATUAL_ID = "11111111-1111-1111-1111-111111111111";
const CUMPRIMENTO_ID = "22222222-2222-2222-2222-222222222222";
const INCIDENTE_ID = "33333333-3333-3333-3333-333333333333";

function novoDb(): Db {
  return { processos: [], cumprimentos: [], incidentes: [], partes: [] };
}

/** Estado pós FOR-178: `processos` = o CUMPRIMENTO promovido a "raiz" por engano, com 1
 * cumprimento sintético e 1 incidente/parte pendurados nele. */
function semeiaHierarquiaErrada(db: Db): void {
  db.processos!.push({ id: PROCESSO_ATUAL_ID, processo_codigo: CODIGO_CUMP, cnj: "0018028-13.2022.8.26.0562", cnj_normalizado: "00180281320228260562" });
  db.cumprimentos!.push({ id: CUMPRIMENTO_ID, processo_id: PROCESSO_ATUAL_ID, processo_codigo: `${CODIGO_CUMP}#cumprimento`, cnj: "0018028-13.2022.8.26.0562" });
  db.incidentes!.push({ id: INCIDENTE_ID, processo_id: PROCESSO_ATUAL_ID, cumprimento_id: CUMPRIMENTO_ID, processo_codigo: "1H0000INC1", numero_depre: "0436868-90.2025.8.26.0500" });
  db.partes!.push({ id: randomUUID(), incidente_id: INCIDENTE_ID, processo_id: PROCESSO_ATUAL_ID, papel: "ativa", nome: "CREDOR LEGADO" });
}

function principalInfo(): ProcessoPrincipalInfo {
  return {
    processo_codigo: CODIGO_PRINC, foro: "0562", cnj: CNJ_PRINCIPAL,
    classe: "Procedimento Comum Cível", assunto: null, distribuicao: null,
    valor_acao: null, data_base: null, status: "ativo",
    ente_nome: "FAZENDA PUBLICA DO ESTADO DE SAO PAULO", ente_esfera: "Estadual", flag_sp: true,
  };
}

// ---- Fake query builder (mesmo mínimo de supabase-persist-tree-legado.test.ts) ---------------
type Filtro = (r: Row) => boolean;
class FakeQuery implements PromiseLike<{ data: unknown; error: null }> {
  private op: "select" | "upsert" = "select";
  private filtros: Filtro[] = [];
  private payload: Record<string, unknown>[] = [];
  private upsertOpts: { onConflict?: string } = {};
  private modo: "many" | "single" = "many";
  constructor(private db: Db, private table: string) {}

  select(_cols?: string) { return this; }
  eq(col: string, v: unknown) { this.filtros.push((r) => r[col] === v); return this; }
  single() { this.modo = "single"; return this; }
  upsert(rows: Record<string, unknown> | Record<string, unknown>[], opts: { onConflict?: string } = {}) {
    this.op = "upsert"; this.payload = Array.isArray(rows) ? rows : [rows]; this.upsertOpts = opts; return this;
  }

  private run(): unknown {
    const t = (this.db[this.table] ??= []);
    const match = (r: Row) => this.filtros.every((f) => f(r));
    let out: Row[] = [];
    switch (this.op) {
      case "select": out = t.filter(match); break;
      case "upsert": {
        const keys = (this.upsertOpts.onConflict ?? "id").split(",");
        for (const p of this.payload) {
          const ex = t.find((r) => keys.every((k) => r[k] === p[k]));
          if (ex) { Object.assign(ex, p); out.push(ex); }
          else { const novo = { id: randomUUID(), ...p } as Row; t.push(novo); out.push(novo); }
        }
        const cods = t.map((r) => r.processo_codigo).filter((c) => c !== undefined);
        assert.equal(new Set(cods).size, cods.length, `unique processo_codigo violada em ${this.table}`);
        break;
      }
    }
    const copia = out.map((r) => ({ ...r }));
    if (this.modo === "single") { assert.equal(copia.length, 1, `.single() em ${this.table} sem exatamente 1 linha`); return copia[0]; }
    return copia;
  }

  then<A = { data: unknown; error: null }, B = never>(ok?: ((v: { data: unknown; error: null }) => A | PromiseLike<A>) | null, ko?: ((e: unknown) => B | PromiseLike<B>) | null): PromiseLike<A | B> {
    return Promise.resolve().then(() => ({ data: this.run(), error: null as null })).then(ok, ko);
  }
}

/** Simula merge_legado_cumprimento_para_principal com a MESMA semântica do SQL real
 * (sql/2026-10-02_for195_merge_legado_cumprimento_para_principal.sql). */
function rpcFake(db: Db, chamadas: Array<[string, Record<string, string>]>, falhar?: string) {
  return async (nome: string, a: Record<string, string>) => {
    chamadas.push([nome, a]);
    if (nome === falhar) return { data: null, error: { message: "boom" } };
    if (nome !== "merge_legado_cumprimento_para_principal") throw new Error(`RPC inesperada no teste: ${nome}`);
    const { p_processo_atual_id: atual, p_processo_principal_id: principal } = a;
    if (atual === principal) return { data: null, error: null };
    const atualRow = db.processos!.find((r) => r.id === atual);
    if (!atualRow) return { data: null, error: null }; // idempotência: já reconciliado
    if (!db.processos!.some((r) => r.id === principal)) return { data: null, error: { message: "processo principal não existe" } };
    for (const t of ["cumprimentos", "incidentes", "partes"]) {
      db[t]!.forEach((r) => { if (r.processo_id === atual) r.processo_id = principal; });
    }
    const ex = db.cumprimentos!.find((r) => r.processo_codigo === atualRow.processo_codigo);
    if (ex) ex.processo_id = principal;
    else db.cumprimentos!.push({ id: randomUUID(), processo_id: principal, processo_codigo: atualRow.processo_codigo as string, cnj: atualRow.cnj, cnj_normalizado: atualRow.cnj_normalizado });
    db.processos = db.processos!.filter((r) => r.id !== atual);
    return { data: null, error: null };
  };
}

function instala(t: import("node:test").TestContext, db: Db, falhar?: string) {
  const chamadas: Array<[string, Record<string, string>]> = [];
  t.mock.method(supabase, "from", (table: string) => new FakeQuery(db, table));
  t.mock.method(supabase, "rpc", rpcFake(db, chamadas, falhar));
  return chamadas;
}

test("FOR-195: achou a ação principal -> upsert em processos + RPC de merge + hierarquia reorganizada", async (t) => {
  const db = novoDb();
  semeiaHierarquiaErrada(db);
  const chamadas = instala(t, db);

  const principalId = await reconcilePrincipalReal(PROCESSO_ATUAL_ID, principalInfo());

  assert.notEqual(principalId, PROCESSO_ATUAL_ID);
  const principal = db.processos!.find((r) => r.id === principalId)!;
  assert.equal(principal.processo_codigo, CODIGO_PRINC);
  assert.equal(principal.cnj, CNJ_PRINCIPAL);
  assert.equal(principal.cnj_normalizado, "10005949120228260562");
  assert.equal(db.processos!.length, 1, "o antigo 'processo' (cumprimento promovido por engano) foi apagado pela RPC");
  assert.equal(db.incidentes![0]!.processo_id, principalId, "incidente reapontado pro principal");
  assert.equal(db.partes![0]!.processo_id, principalId, "partes reapontadas pro principal");
  assert.equal(db.cumprimentos!.length, 2, "cumprimento original + o antigo 'processo' convertido em cumprimento");
  assert.ok(db.cumprimentos!.some((c) => c.processo_codigo === CODIGO_CUMP && c.processo_id === principalId));

  const merges = chamadas.filter(([n]) => n === "merge_legado_cumprimento_para_principal");
  assert.equal(merges.length, 1);
  assert.deepEqual(merges[0]![1], { p_processo_atual_id: PROCESSO_ATUAL_ID, p_processo_principal_id: principalId });
});

test("FOR-195: idempotente — 2ª chamada da mesma reconciliação não duplica nem chama a RPC de novo", async (t) => {
  const db = novoDb();
  semeiaHierarquiaErrada(db);
  const chamadas = instala(t, db);

  const principalId = await reconcilePrincipalReal(PROCESSO_ATUAL_ID, principalInfo());
  const antes = chamadas.length;
  const principalId2 = await reconcilePrincipalReal(PROCESSO_ATUAL_ID, principalInfo());

  assert.equal(principalId2, principalId, "upsert por processo_codigo devolve o MESMO id — nunca duplica processos");
  assert.equal(db.processos!.length, 1);
  // a RPC é chamada de novo (processoAtualId segue != principalId do ponto de vista do
  // caller), mas é um no-op idempotente no fake — assim como no SQL real.
  const merges = chamadas.slice(antes).filter(([n]) => n === "merge_legado_cumprimento_para_principal");
  assert.equal(merges.length, 1);
  assert.equal(db.cumprimentos!.length, 2, "2ª chamada não duplica a linha cumprimentos convertida");
});

test("FOR-195: 2 reconciliações diferentes resolvendo pro MESMO principal — upsert por processo_codigo não duplica processos", async (t) => {
  const db = novoDb();
  semeiaHierarquiaErrada(db);
  // 2ª árvore legado (outro cumprimento, mesma ação principal real).
  const PROCESSO_ATUAL_2 = "44444444-4444-4444-4444-444444444444";
  db.processos!.push({ id: PROCESSO_ATUAL_2, processo_codigo: "1H0000CUMP2", cnj: "0099999-00.2023.8.26.0562" });
  db.incidentes!.push({ id: "55555555-5555-5555-5555-555555555555", processo_id: PROCESSO_ATUAL_2, cumprimento_id: null, processo_codigo: "1H0000INC2", numero_depre: "0077777-00.2023.8.26.0500" });
  instala(t, db);

  const principalId1 = await reconcilePrincipalReal(PROCESSO_ATUAL_ID, principalInfo());
  const principalId2 = await reconcilePrincipalReal(PROCESSO_ATUAL_2, principalInfo());

  assert.equal(principalId2, principalId1, "mesma ação principal real -> mesmo id, sem duplicar processos");
  assert.equal(db.processos!.length, 1, "só o principal em processos, mesmo com 2 reconciliações de árvores legado distintas");
  assert.equal(db.incidentes!.filter((r) => r.processo_id === principalId1).length, 2, "incidentes das 2 árvores convergem pro mesmo principal");
});

test("FOR-195: erro da RPC propaga com o nome da RPC na mensagem", async (t) => {
  const db = novoDb();
  semeiaHierarquiaErrada(db);
  instala(t, db, "merge_legado_cumprimento_para_principal");

  await assert.rejects(
    () => reconcilePrincipalReal(PROCESSO_ATUAL_ID, principalInfo()),
    /merge_legado_cumprimento_para_principal: boom/,
  );
});
