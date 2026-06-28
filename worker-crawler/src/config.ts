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
