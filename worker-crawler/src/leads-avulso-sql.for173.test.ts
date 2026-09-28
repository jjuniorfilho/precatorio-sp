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
