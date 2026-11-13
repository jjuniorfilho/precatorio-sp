// Backfill de incidentes.{data_oficio_expedido, oficio_rejeitado, data_oficio_rejeitado, data_oficio_deferido}
// (sql/2026-11-12_oficio_expedido_rejeitado.sql). Roda do Mac chamando a RPC backfill_oficio_incidentes_lote
// em lotes pequenos, com pausa entre eles — o trabalho continua dentro do Postgres, mas aqui dá pra
// controlar o ritmo, parar/retomar e frear sozinho se o crawler da VPS desacelerar.
//
// Autentica com o login admin do worker (SUPABASE_ANON_KEY + ADMIN_EMAIL/ADMIN_PASSWORD do .env.mac) e chama
// backfill_oficio_incidentes_lote_worker (sql/2026-11-13_backfill_oficio_worker_grant.sql, teto de 3000 por lote).
//
// Uso: DOTENV_CONFIG_PATH=.env.mac tsx src/backfill-oficio.ts [--limit=500] [--max-limit=3000] [--sleep=2000]
//        [--after=<uuid>] [--guard-ssh=root@31.97.242.130] [--guard-ms=90000]
// Progresso fica em .backfill-oficio.cursor (retoma sozinho; apague o arquivo pra recomeçar). Ctrl+C é seguro:
// termina o lote corrente e salva o cursor.
import "dotenv/config";
import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, writeFileSync } from "node:fs";

const CURSOR_FILE = ".backfill-oficio.cursor";
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function arg(name: string): string | undefined {
  return process.argv.slice(2).find((a) => a.startsWith(`--${name}=`))?.slice(name.length + 3);
}
const num = (name: string, def: number) => {
  const v = arg(name);
  const n = v ? Number(v) : NaN;
  return Number.isFinite(n) && n > 0 ? n : def;
};
const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

const ARGS_CONHECIDOS = /^--(limit|max-limit|sleep|after|guard-ssh|guard-ms)=.+$/;
const desconhecido = process.argv.slice(2).find((a) => !ARGS_CONHECIDOS.test(a));
if (desconhecido) {
  console.error(`argumento não reconhecido: "${desconhecido}".`);
  process.exit(1);
}

const url = process.env.SUPABASE_URL ?? "";
const anonKey = process.env.SUPABASE_ANON_KEY ?? "";
const adminEmail = process.env.ADMIN_EMAIL ?? "";
const adminPassword = process.env.ADMIN_PASSWORD ?? "";
if (!url || !anonKey || !adminEmail || !adminPassword) {
  console.error("Defina SUPABASE_URL, SUPABASE_ANON_KEY, ADMIN_EMAIL e ADMIN_PASSWORD no .env.mac.");
  process.exit(1);
}

// Token do login admin: expira em ~1h — renova 5 min antes e quando a API devolve 401.
let token = "";
let tokenExpiraEm = 0;
async function login(): Promise<void> {
  const res = await fetch(`${url}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: anonKey, "Content-Type": "application/json" },
    body: JSON.stringify({ email: adminEmail, password: adminPassword }),
    signal: AbortSignal.timeout(30_000),
  });
  if (!res.ok) throw new Error(`login admin falhou: HTTP ${res.status}`);
  const j = (await res.json()) as { access_token: string; expires_in: number };
  token = j.access_token;
  tokenExpiraEm = Date.now() + (j.expires_in - 300) * 1000;
}

let limit = num("limit", 500);
const maxLimit = num("max-limit", 3000);
const pauseMs = num("sleep", 2000);
const guardSsh = arg("guard-ssh");
const guardMs = num("guard-ms", 90_000);

let cursor: string | null = arg("after") ?? (existsSync(CURSOR_FILE) ? readFileSync(CURSOR_FILE, "utf8").trim() || null : null);
if (cursor && !UUID_RE.test(cursor)) {
  console.error(`cursor inválido: "${cursor}"`);
  process.exit(1);
}

let parar = false;
process.on("SIGINT", () => {
  console.log("\nCtrl+C — termino o lote corrente e salvo o cursor...");
  parar = true;
});

/** Duração (ms) dos últimos lotes do crawler na VPS; null se não deu pra ler (guard desligado nessa volta). */
function duracaoMediaCrawler(): number | null {
  if (!guardSsh) return null;
  try {
    const out = execFileSync(
      "ssh",
      ["-o", "ConnectTimeout=10", guardSsh, "grep '\\[batch\\]' /root/.pm2/logs/precatorio-crawler-out.log | tail -3"],
      { encoding: "utf8", timeout: 20_000 },
    );
    const ms = [...out.matchAll(/\((\d+)ms\)/g)].map((m) => Number(m[1]));
    return ms.length ? ms.reduce((a, b) => a + b, 0) / ms.length : null;
  } catch {
    return null;
  }
}

async function chamarLote(after: string | null, p_limit: number): Promise<{ next: string | null } | { erro: string; timeout: boolean }> {
  if (!token || Date.now() > tokenExpiraEm) await login();
  const res = await fetch(`${url}/rest/v1/rpc/backfill_oficio_incidentes_lote_worker`, {
    method: "POST",
    headers: { apikey: anonKey, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify({ p_after: after, p_limit }),
    signal: AbortSignal.timeout(120_000),
  }).catch((e: Error) => e);
  if (res instanceof Error) return { erro: res.message, timeout: /timeout|abort/i.test(res.message) };
  const texto = await res.text();
  if (res.status === 401) tokenExpiraEm = 0; // força novo login na próxima tentativa
  if (!res.ok) return { erro: `HTTP ${res.status} ${texto.slice(0, 200)}`, timeout: /57014|statement timeout|504|502/i.test(`${res.status} ${texto}`) };
  const next = JSON.parse(texto) as string | null; // a RPC devolve o último id do lote, ou NULL quando acabou
  return { next };
}

async function main() {
  console.log(`backfill-oficio: início cursor=${cursor ?? "(começo)"} limit=${limit} (máx ${maxLimit}) pausa=${pauseMs}ms guard=${guardSsh ?? "off"}`);
  let lotes = 0, falhas = 0;
  const t0 = Date.now();

  while (!parar) {
    const media = duracaoMediaCrawler();
    if (media !== null && media > guardMs) {
      console.log(`  crawler lento (média ${(media / 1000).toFixed(0)}s por lote > ${guardMs / 1000}s) — pausando 60s`);
      await sleep(60_000);
      continue;
    }

    const t = Date.now();
    const r = await chamarLote(cursor, limit);
    if ("erro" in r) {
      falhas++;
      limit = Math.max(50, Math.floor(limit / 2));
      console.error(`  ✗ ${r.erro} — reduzindo lote pra ${limit} e tentando de novo em 10s (falha ${falhas}/8)`);
      if (falhas >= 8) { console.error("muitas falhas seguidas — abortando (cursor preservado)."); process.exit(1); }
      await sleep(10_000);
      continue;
    }
    falhas = 0;
    lotes++;
    const dt = Date.now() - t;
    if (r.next === null) {
      writeFileSync(CURSOR_FILE, "");
      console.log(`\n✓ backfill concluído: ${lotes} lote(s) em ${((Date.now() - t0) / 60000).toFixed(1)} min.`);
      return;
    }
    cursor = r.next;
    writeFileSync(CURSOR_FILE, cursor);
    console.log(`  lote ${lotes}: ${dt}ms (limit=${limit}) cursor=${cursor}`);
    // Lote rápido -> cresce devagar; lento (>15s) -> encolhe. Mantém cada transação curta.
    if (dt < 4000) limit = Math.min(maxLimit, Math.ceil(limit * 1.25));
    else if (dt > 15_000) limit = Math.max(100, Math.floor(limit / 2));
    await sleep(pauseMs);
  }
  console.log(`parado. cursor salvo em ${CURSOR_FILE}: ${cursor ?? "(começo)"}`);
}

main().catch((e) => { console.error("fatal:", e); process.exit(1); });
