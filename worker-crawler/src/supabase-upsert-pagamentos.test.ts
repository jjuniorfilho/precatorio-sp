// FOR-174 (achado em produção, 2026-09-29) — `upsertPagamentos` não tinha NENHUM teste direto
// (só é exercitada via mock de dependência em pagamentos-tjsp.test.ts). Isso deixou passar, sem
// nenhum teste quebrando, uma troca de `.from(...).upsert(...)` direto (que sempre falhava com
// RLS quando o worker roda sem SUPABASE_SERVICE_ROLE_KEY — ver sql/2026-09-29_for174_fix_upsert_
// pagamentos_rls.sql) por uma RPC `SECURITY DEFINER`. Este teste mocka `supabase.rpc` (não a rede,
// não o Postgres real — isso é papel de sql/sandbox/for174_validate_local.sh) e prova o CONTRATO:
// nome da RPC, shape do payload, filtro de data=null e propagação de erro.
import { test } from "node:test";
import assert from "node:assert/strict";
import { mock } from "node:test";
import { supabase, upsertPagamentos } from "./supabase.js";

const DEP = "0253361-73.2018.8.26.0500";

test("upsertPagamentos: nada a fazer com lista vazia (não chama a RPC)", async (t) => {
  const rpc = t.mock.method(supabase, "rpc", async () => ({ error: null }));
  await upsertPagamentos(DEP, []);
  assert.equal(rpc.mock.calls.length, 0);
});

test("upsertPagamentos: chama a RPC upsert_precatorios_pagamentos com o shape certo", async (t) => {
  const rpc = t.mock.method(supabase, "rpc", async () => ({ error: null }));
  await upsertPagamentos(DEP, [
    { data: "2020-01-01", valorCentavos: 100000, tipo: "Preferência" },
    { data: "2020-02-01", valorCentavos: 50000, tipo: null },
  ]);
  assert.equal(rpc.mock.calls.length, 1);
  const [nome, args] = rpc.mock.calls[0]!.arguments as [string, Record<string, unknown>];
  assert.equal(nome, "upsert_precatorios_pagamentos");
  assert.equal(args.p_processo_depre, DEP);
  assert.deepEqual(args.p_pagamentos, [
    { data: "2020-01-01", valor: 100000, tipo: "Preferência" },
    { data: "2020-02-01", valor: 50000, tipo: "" }, // tipo null vira "" (índice único não aceita NULL)
  ]);
});

test("upsertPagamentos: filtra pagamento sem data ANTES de mandar pra RPC (data_pagamento é NOT NULL)", async (t) => {
  const rpc = t.mock.method(supabase, "rpc", async () => ({ error: null }));
  await upsertPagamentos(DEP, [
    { data: null, valorCentavos: 999, tipo: "x" },
    { data: "2020-01-01", valorCentavos: 1, tipo: null },
  ]);
  const [, args] = rpc.mock.calls[0]!.arguments as [string, { p_pagamentos: unknown[] }];
  assert.equal(args.p_pagamentos.length, 1);
});

test("upsertPagamentos: erro da RPC propaga com o nome da RPC na mensagem (não mais 'upsert precatorios_pagamentos')", async (t) => {
  t.mock.method(supabase, "rpc", async () => ({ error: { message: "role authenticated sem permissão" } }));
  await assert.rejects(
    () => upsertPagamentos(DEP, [{ data: "2020-01-01", valorCentavos: 1, tipo: null }]),
    /upsert_precatorios_pagamentos: role authenticated sem permissão/,
  );
});
