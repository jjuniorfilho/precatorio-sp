// FOR-173 — testes de TEXTO dos SQLs 1 e 2 (lead avulso). Não executam SQL: travam as decisões que já
// custaram caro (sem DROP VIEW, `origem` reaproveitada em vez de criada, coluna nova SEMPRE no fim da view).
// Roda via `npm test` (node:test).
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const sql = (n: string) => readFileSync(new URL(`../../sql/${n}`, import.meta.url), "utf-8");
/** Sem comentários `--` e com espaços colapsados, para casar só código executável. */
const codigo = (s: string) =>
  s
    .split("\n")
    .filter((l) => !l.trim().startsWith("--"))
    .join("\n")
    .replace(/\s+/g, " ");

const LEADS = codigo(sql("2026-09-28_for173_1_leads_avulso.sql"));
const VIEW = codigo(sql("2026-09-28_for173_2_view_leads_processos_origem.sql"));
const RPC4 = codigo(sql("2026-09-28_for173_4_rpcs_progresso.sql"));

test("SQL 1: colunas novas são idempotentes (criado_por, documento)", () => {
  assert.match(LEADS, /ADD COLUMN IF NOT EXISTS criado_por uuid/);
  assert.match(LEADS, /ADD COLUMN IF NOT EXISTS documento text/);
});

test("SQL 1: email e relacao passam a aceitar NULL; nome/telefone não são tocados", () => {
  assert.match(LEADS, /ALTER COLUMN email DROP NOT NULL/);
  assert.match(LEADS, /ALTER COLUMN relacao DROP NOT NULL/);
  assert.doesNotMatch(LEADS, /ALTER COLUMN (nome|telefone|processo_depre) /);
});

test("SQL 1: NÃO cria `origem` nem CHECK que RESTRINJA os valores dela (a coluna já existe e é livre)", () => {
  assert.doesNotMatch(LEADS, /ADD COLUMN[^;]*\borigem\b/i);
  // CHECKs que só CONDICIONAM outras colunas a origem='avulso' são permitidos (invariantes do avulso);
  // o que não pode existir é `CHECK (origem IN (...))`/`origem = ...` limitando os valores livres do fluxo público.
  assert.doesNotMatch(LEADS, /CHECK \(origem (IN|=|<>|!=|~)/i);
});

test("SQL 1: nada destrutivo (sem DROP TABLE/COLUMN/VIEW/CONSTRAINT nem DELETE)", () => {
  assert.doesNotMatch(LEADS, /\bDROP (TABLE|COLUMN|VIEW|CONSTRAINT)\b/i);
  assert.doesNotMatch(LEADS, /\bDELETE\b/i);
});

test("SQL 1: índice único PARCIAL — um avulso por DEPRE", () => {
  assert.match(
    LEADS,
    /CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_avulso_processo_depre ON public\.leads \(processo_depre\) WHERE origem = 'avulso'/,
  );
});

test("SQL 1: documento só aceita null ou 11/14 dígitos, criado de forma idempotente", () => {
  assert.match(LEADS, /IF NOT EXISTS \( SELECT 1 FROM pg_constraint WHERE conrelid = 'public\.leads'::regclass AND conname = 'leads_documento_check' \)/);
  assert.match(LEADS, /CHECK \(documento IS NULL OR documento ~ '\^\\d\{11\}\(\\d\{3\}\)\?\$'\)/);
});

test("SQL 1: invariantes do avulso no BANCO (sem consentimento; um único DEPRE)", () => {
  assert.match(LEADS, /conname = 'leads_avulso_sem_consent_check'/);
  assert.match(LEADS, /CHECK \(origem IS DISTINCT FROM 'avulso' OR lgpd_consent = false\)/);
  assert.match(LEADS, /conname = 'leads_avulso_um_depre_check'/);
  assert.match(LEADS, /CHECK \(origem IS DISTINCT FROM 'avulso' OR \(processo_depre IS NOT NULL AND processo_depre !~ ','\)\)/);
});

test("SQL 1: o anon NÃO consegue forjar avulso nem gravar colunas novas; email/relacao seguem obrigatórios pra ele", () => {
  assert.match(
    LEADS,
    /ALTER POLICY anon_insert_leads ON public\.leads WITH CHECK \( lgpd_consent = true AND origem IS DISTINCT FROM 'avulso' AND criado_por IS NULL AND documento IS NULL AND email IS NOT NULL AND relacao IS NOT NULL \)/,
  );
  // ALTER POLICY é atômico: nunca DROP POLICY (haveria um instante sem policy e o cadastro do site falharia).
  assert.doesNotMatch(LEADS, /DROP POLICY/i);
});

test("SQL 1: não mexe em views (criado_por/documento ficam fora delas)", () => {
  assert.doesNotMatch(LEADS, /VIEW/i);
});

// ---- SQL 2 ------------------------------------------------------------------------------------------
const SELECT_ITENS = (() => {
  const m = VIEW.match(/CREATE OR REPLACE VIEW public\.leads_processos WITH \(security_invoker = true\) AS SELECT (.*?) FROM public\.leads_com_progresso lp/);
  assert.ok(m, "não achou o SELECT da view");
  return m![1]!.split(",").map((s) => s.trim());
})();

const COLUNAS_VIVAS = [
  "lp.id", "lp.nome", "lp.email", "lp.telefone", "lp.relacao", "lp.processo_depre", "lp.saldo_consultado",
  "lp.devedora", "lp.status_crm", "lp.notas", "lp.token_email_validado", "lp.token_telefone_validado",
  "lp.relatorio_enviado_at", "lp.session_id", "lp.intent", "lp.created_at", "lp.updated_at", "lp.verified_at",
  "lp.nivel_funil", "lp.etapa1_busca", "lp.etapa2_cadastro", "lp.etapa3_token_email", "lp.etapa4_email_validado",
  "lp.etapa5_whatsapp_validado", "lp.etapa6_relatorio", "p.processo", "dj.valor_causa", "pr.saldo_depre",
  "pr.valor_pago", "pr.pagamentos_consultado_em", "dj.acordo_homologado", "inc.cessao_credito",
];

test("SQL 2: é CREATE OR REPLACE (nunca DROP VIEW) e mantém security_invoker", () => {
  assert.match(VIEW, /CREATE OR REPLACE VIEW public\.leads_processos WITH \(security_invoker = true\)/);
  assert.doesNotMatch(VIEW, /\bDROP\b/i);
});

test("SQL 2: as 32 colunas vivas ficam idênticas e na mesma ordem; `lp.origem` é a ÚLTIMA", () => {
  assert.deepEqual(SELECT_ITENS.slice(0, COLUNAS_VIVAS.length), COLUNAS_VIVAS);
  assert.equal(SELECT_ITENS.length, COLUNAS_VIVAS.length + 1);
  assert.equal(SELECT_ITENS[SELECT_ITENS.length - 1], "lp.origem");
});

test("SQL 2: só service_role enxerga a view (PII)", () => {
  assert.match(VIEW, /REVOKE ALL ON public\.leads_processos FROM PUBLIC, anon, authenticated;/);
  assert.match(VIEW, /GRANT ALL ON public\.leads_processos TO service_role;/);
  assert.doesNotMatch(VIEW, /GRANT[^;]*\b(anon|authenticated)\b/i);
});

test("SQL 2: mantém os 4 LATERAL JOINs da definição viva (processo, precatorios, djen_depre, incidentes)", () => {
  assert.equal((VIEW.match(/LEFT JOIN LATERAL/g) ?? []).length, 4);
  assert.match(VIEW, /FROM public\.precatorios r WHERE r\.processo_depre = p\.processo ORDER BY r\.updated_at DESC NULLS LAST LIMIT 1/);
  assert.match(VIEW, /FROM public\.djen_depre d WHERE d\.cnj_normalizado = regexp_replace\(p\.processo, '\\D', '', 'g'\)/);
  assert.match(VIEW, /FROM public\.incidentes i WHERE i\.numero_depre = p\.processo/);
});

// ---- SQLs de diagnóstico e verificação: têm que ser SOMENTE LEITURA -------------------------------------
test("SQLs 0 (diagnóstico) e 5 (verificação) são somente leitura", () => {
  for (const n of ["2026-09-28_for173_0_diag_leads_ddl.sql", "2026-09-28_for173_5_verifica_aplicacao.sql"]) {
    // tira comentários e o CONTEÚDO de strings ('INSERT' em has_table_privilege não é DML)
    const semLiterais = sql(n)
      .split("\n").filter((l) => !l.trim().startsWith("--")).join("\n")
      .replace(/'[^']*'/g, "''");
    assert.doesNotMatch(semLiterais, /\b(INSERT|UPDATE|DELETE|ALTER|CREATE|DROP|GRANT|REVOKE|TRUNCATE|COMMENT|NOTIFY)\b/i, n);
  }
});

test("SQL 5: nunca usa LIKE com barra invertida (em LIKE ela é o escape e o check viraria sempre falso)", () => {
  const v = sql("2026-09-28_for173_5_verifica_aplicacao.sql").split("\n").filter((l) => !l.trim().startsWith("--")).join("\n");
  assert.doesNotMatch(v, /LIKE\s+'[^']*\\/i);
  assert.match(v, /strpos\(/);
});

test("SQL 5: confere os MESMOS nomes que o SQL 1 cria (constraints, índice, policy) — sem check inútil por erro de digitação", () => {
  const v5 = sql("2026-09-28_for173_5_verifica_aplicacao.sql");
  for (const nome of ["leads_documento_check", "leads_avulso_sem_consent_check", "leads_avulso_um_depre_check", "uq_leads_avulso_processo_depre", "anon_insert_leads"]) {
    assert.ok(LEADS.includes(nome), `SQL 1 não menciona ${nome}`);
    assert.ok(v5.includes(nome), `SQL 5 não confere ${nome}`);
  }
});

test("SQL 6 (roteiro): rollback garantido por construção — sem COMMIT, sem BEGIN/ROLLBACK, termina com RAISE EXCEPTION", () => {
  const raw = sql("2026-09-28_for173_6_roteiro_teste_transacional.sql");
  const cod = raw.split("\n").filter((l) => !l.trim().startsWith("--")).join("\n");
  assert.doesNotMatch(cod, /\bCOMMIT\b/i, "nada pode ser confirmado");
  assert.doesNotMatch(cod, /^\s*(BEGIN|START TRANSACTION|ROLLBACK)\s*;/im, "o SQL Editor mostra só a última instrução: nada de BEGIN/ROLLBACK soltos");
  // o ÚLTIMO comando do DO é o RAISE EXCEPTION que carrega o relatório e desfaz tudo
  assert.match(cod.trim(), /RAISE EXCEPTION E'FOR-173 roteiro transacional[\s\S]*END\s*\$do\$;\s*$/);
  // só pg_temp para helpers (somem com a sessão e são desfeitos pelo erro)
  assert.doesNotMatch(cod, /CREATE (OR REPLACE )?FUNCTION (?!pg_temp\.)/i);
  // usa now() fixo por transação corretamente: recua iniciada_em à mão antes de provar preserva/renova
  assert.match(cod, /UPDATE public\.pagamentos_consultas_progresso SET iniciada_em = now\(\) - interval '1 hour'/);
});

test("SQL 6: os nomes das RPCs e das constraints que ele exercita existem nos SQLs 1 e 4", () => {
  const cod = sql("2026-09-28_for173_6_roteiro_teste_transacional.sql");
  assert.ok(cod.includes("registrar_progresso_consulta_pagamento") && RPC4.includes("registrar_progresso_consulta_pagamento"));
  assert.ok(cod.includes("obter_progresso_consulta_pagamento") && RPC4.includes("obter_progresso_consulta_pagamento"));
});
