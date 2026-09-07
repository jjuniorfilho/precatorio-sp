// Configuração via env (ver .env.example). Defaults conservadores.
import "dotenv/config"; // carrega .env (Node 18 não tem --env-file)
// Node < 20 não tem `File` global (cheerio/undici exigem). Polyfill via undici.
import { File as UndiciFile } from "undici";
if (!(globalThis as { File?: unknown }).File) {
  (globalThis as { File?: unknown }).File = UndiciFile;
}

function num(name: string, def: number): number {
  const v = process.env[name];
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) ? n : def;
}

export const config = {
  supabaseUrl: process.env.SUPABASE_URL ?? "",
  serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY ?? "",
  // Opção B (sem service_role): autentica como admin via anon key + email/senha
  anonKey: process.env.SUPABASE_ANON_KEY ?? "",
  adminEmail: process.env.ADMIN_EMAIL ?? "",
  adminPassword: process.env.ADMIN_PASSWORD ?? "",
  esajBase: process.env.ESAJ_BASE ?? "https://esaj.tjsp.jus.br/cpopg",

  claimBatch: num("CLAIM_BATCH", 25),
  pollEmptyMs: num("POLL_EMPTY_MS", 15_000),
  loopEnabled: (process.env.LOOP_ENABLED ?? "true") !== "false",

  concurrency: num("CONCURRENCY", 3),
  delayMs: num("DELAY_MS", 400),
  requestTimeoutMs: num("REQUEST_TIMEOUT_MS", 15_000),
  maxHttpRetry: num("MAX_HTTP_RETRY", 3),
  // FOR-116 — teto de tempo por job (não por requisição HTTP individual, que já tem
  // requestTimeoutMs/maxHttpRetry). Sem isso, um "mega-processo" (ex.: um caso já visto
  // com 8.513 incidentes) pode encadear milhares de fetches — cada um bounded, mas a soma
  // não — e travar uma vaga inteira do pool por horas, refém do lote inteiro junto.
  jobTimeoutMs: num("JOB_TIMEOUT_MS", 5 * 60_000),

  // FOR-102 — endpoint HTTP síncrono (buscar-precatorio + admin chamam /valor-pago).
  httpPort: num("HTTP_PORT", 3200),
  httpSecret: process.env.WORKER_HTTP_SECRET ?? "",

  // FOR-143 — reconciliação LEGADO→real em persistTree() (ver supabase.ts). Custa 1 SELECT
  // extra por processo crawleado, pra sempre — vale a pena enquanto houver processos "LEGADO-"
  // pendentes (~12k no ar em 2026-08-19), mas pode ser desligado (LEGADO_RECONCILE=false) depois
  // que o backfill do FOR-143 for absorvido, já que a partir daí é só overhead morto.
  legadoReconcile: (process.env.LEGADO_RECONCILE ?? "true") !== "false",

  // FOR-145 — teto de tempo por dia de ingestão federal (ingest-djen-federal.ts), mesmo
  // problema do FOR-116 (jobTimeoutMs) só que na escala de "dia inteiro" em vez de "1 job":
  // fetchPage já tem requestTimeoutMs/retry bounded, mas as escritas no Supabase dentro do
  // loop de página (persistFederal/classifyProcesso) não têm timeout nenhum — uma trava de
  // rede/lock numa dessas chamadas trava o dia inteiro sem limite. Confirmado em produção
  // 2026-09-07: backfill de TRF1 09-02 travou 11h+ na página 642/642 sem nunca dar erro nem
  // avançar. Teto generoso (bem acima do pior caso observado, ~461 páginas em poucos minutos
  // pro TRF1 09-01) pra nunca cortar um dia legítimo, só travas de verdade.
  dayTimeoutMs: num("DAY_TIMEOUT_MS", 20 * 60_000),
};

export function assertConfig(): void {
  if (!config.supabaseUrl) throw new Error("SUPABASE_URL é obrigatório.");
  const temServiceRole = !!config.serviceRoleKey;
  const temAdmin = !!(config.anonKey && config.adminEmail && config.adminPassword);
  if (!temServiceRole && !temAdmin) {
    throw new Error(
      "Defina SUPABASE_SERVICE_ROLE_KEY, OU (SUPABASE_ANON_KEY + ADMIN_EMAIL + ADMIN_PASSWORD) para login admin. Ver .env.example.",
    );
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
