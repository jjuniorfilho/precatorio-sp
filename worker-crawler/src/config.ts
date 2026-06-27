// Configuração via env (ver .env.example). Defaults conservadores.
function num(name: string, def: number): number {
  const v = process.env[name];
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) ? n : def;
}

export const config = {
  supabaseUrl: process.env.SUPABASE_URL ?? "",
  serviceRoleKey: process.env.SUPABASE_SERVICE_ROLE_KEY ?? "",
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
  if (!config.supabaseUrl || !config.serviceRoleKey) {
    throw new Error("SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios (ver .env.example).");
  }
}

export const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
