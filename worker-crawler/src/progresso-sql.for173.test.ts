// FOR-173 — testes de TEXTO dos SQLs 3 e 4 (tabela e RPCs de progresso). Não executam SQL: travam o
// contrato fixado no plan.md (assinaturas, GRANTs, SECURITY DEFINER, listas de estados/etapas), que o
// worker (Fase 3) e o frontend (FOR-174) usam. Roda via `npm test` (node:test).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql = (n: string) => readFileSync(new URL(`../../sql/${n}`, import.meta.url), "utf-8");
const codigo = (s: string) =>
  s
    .split("\n")
    .filter((l) => !l.trim().startsWith("--"))
    .join("\n")
    .replace(/\s+/g, " ");

const TABELA = codigo(sql("2026-09-28_for173_3_tabela_progresso.sql"));
const RPCS = codigo(sql("2026-09-28_for173_4_rpcs_progresso.sql"));

test("tabela: idempotente, uma linha por processo_depre (PK)", () => {
  assert.match(TABELA, /CREATE TABLE IF NOT EXISTS public\.pagamentos_consultas_progresso/);
  assert.match(TABELA, /processo_depre text PRIMARY KEY/);
});

test("tabela: RLS ligado, sem GRANT para anon/authenticated (acesso só por RPC)", () => {
  assert.match(TABELA, /ALTER TABLE public\.pagamentos_consultas_progresso ENABLE ROW LEVEL SECURITY/);
  assert.match(TABELA, /REVOKE ALL ON public\.pagamentos_consultas_progresso FROM anon, authenticated/);
  assert.doesNotMatch(TABELA, /\bGRANT\b/i);
  assert.doesNotMatch(TABELA, /CREATE POLICY/i);
});

test("tabela: estados e origens com CHECK", () => {
  assert.match(TABELA, /estado text NOT NULL CHECK \(estado IN \('na_fila', 'em_andamento', 'concluida', 'falha'\)\)/);
  assert.match(TABELA, /resultado text CHECK \(resultado IN \('encontrado', 'nao_consta', 'falha'\)\)/);
  assert.match(TABELA, /origem text CHECK \(origem IN \('manual', 'busca_publica', 'crawler'\)\)/);
});

test("tabela: NÃO guarda PII (sem cpf/cnpj/documento/nome/email)", () => {
  assert.doesNotMatch(TABELA, /\b(cpf|cnpj|documento|nome|email|telefone)\b/i);
});

test("RPC de escrita: assinatura do contrato do plan.md", () => {
  assert.ok(
    RPCS.includes(
      "registrar_progresso_consulta_pagamento( p_processo_depre text, p_estado text, p_etapa text, p_tentativa integer, p_max_tentativas integer, p_detalhe text, p_resultado text, p_etapa_falha text, p_origem text, p_nova boolean DEFAULT false )",
    ),
  );
  assert.match(RPCS, /obter_progresso_consulta_pagamento\(p_processo_depre text\) RETURNS jsonb/);
});

test("RPCs: SECURITY DEFINER com search_path fixo, plpgsql (nunca language sql: não inlina)", () => {
  assert.equal((RPCS.match(/SECURITY DEFINER SET search_path = public/g) ?? []).length, 2);
  assert.equal((RPCS.match(/LANGUAGE plpgsql/g) ?? []).length, 2);
  assert.doesNotMatch(RPCS, /LANGUAGE sql/i);
});

test("RPC de escrita: grants = authenticated + service_role, nunca anon", () => {
  assert.match(
    RPCS,
    /REVOKE ALL ON FUNCTION public\.registrar_progresso_consulta_pagamento\(text, text, text, integer, integer, text, text, text, text, boolean\) FROM PUBLIC, anon;/,
  );
  assert.match(
    RPCS,
    /GRANT EXECUTE ON FUNCTION public\.registrar_progresso_consulta_pagamento\(text, text, text, integer, integer, text, text, text, text, boolean\) TO authenticated, service_role;/,
  );
});

test("RPC de leitura: SÓ service_role (o front lê por server function)", () => {
  assert.match(RPCS, /REVOKE ALL ON FUNCTION public\.obter_progresso_consulta_pagamento\(text\) FROM PUBLIC, anon, authenticated;/);
  assert.match(RPCS, /GRANT EXECUTE ON FUNCTION public\.obter_progresso_consulta_pagamento\(text\) TO service_role;/);
  assert.doesNotMatch(RPCS, /obter_progresso_consulta_pagamento\(text\) TO [^;]*\b(anon|authenticated)\b/);
});

test("RPC de escrita: valida DEPRE .0500 e estado; etapas fora da lista viram 'desconhecida'", () => {
  assert.ok(RPCS.includes(String.raw`p_processo_depre !~ '^\d{7}-\d{2}\.\d{4}\.8\.26\.0500$'`), "DEPRE completo, não só o sufixo");
  assert.match(RPCS, /p_estado NOT IN \('na_fila', 'em_andamento', 'concluida', 'falha'\)/);
  const etapas = ["na_fila", "iniciando", "abrir_portal", "obter_link", "abrir_pesquisa", "busca", "resultado_carregou", "ler_resultado", "extrair_pagamentos", "persistir"];
  assert.ok(RPCS.includes(`p_etapa IN (${etapas.map((e) => `'${e}'`).join(", ")})`));
  assert.match(RPCS, /ELSE 'desconhecida'/);
});

test("RPC de escrita: p_nova renova iniciada_em; textos truncados; limpeza preguiçosa de 7 dias", () => {
  assert.match(RPCS, /iniciada_em = CASE WHEN COALESCE\(p_nova, false\) THEN now\(\) ELSE t\.iniciada_em END/);
  assert.match(RPCS, /left\(p_detalhe, 200\)/);
  assert.match(RPCS, /estado IN \('concluida', 'falha'\) AND atualizado_em < now\(\) - interval '7 days'/);
  assert.match(RPCS, /estado IN \('na_fila', 'em_andamento'\) AND atualizado_em < now\(\) - interval '1 day'/, "órfãs de worker morto");
});

test("RPC de escrita: etapa_falha também é validada contra a lista (não guarda texto livre)", () => {
  assert.match(RPCS, /v_etapa_falha := CASE WHEN p_etapa_falha IS NULL THEN NULL WHEN p_etapa_falha IN \(/);
  assert.doesNotMatch(RPCS, /left\(p_etapa_falha/);
});

test("CONTRATO worker↔SQL: os 10 nomes p_* de registrarProgressoPagamento são exatamente os da RPC", () => {
  const ts = readFileSync(new URL("./supabase.ts", import.meta.url), "utf-8");
  const bloco = ts.match(/registrarProgressoPagamento\(r: RegistroProgressoPagamento\)[\s\S]*?\.abortSignal/);
  assert.ok(bloco, "não achou registrarProgressoPagamento em supabase.ts");
  const doTs = [...bloco![0].matchAll(/\b(p_[a-z_]+):/g)].map((m) => m[1]!).sort();
  const assinatura = RPCS.match(/registrar_progresso_consulta_pagamento\( (.*?) \) RETURNS void/);
  assert.ok(assinatura, "não achou a assinatura da RPC");
  const doSql = [...assinatura![1]!.matchAll(/\b(p_[a-z_]+) /g)].map((m) => m[1]!).sort();
  assert.equal(doTs.length, 10);
  assert.deepEqual(doTs, doSql, "divergência de nome faria TODA escrita de progresso falhar em silêncio");
});
