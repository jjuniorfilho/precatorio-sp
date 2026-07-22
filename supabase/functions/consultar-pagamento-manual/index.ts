// FOR-102 Fase 7 — Ponte pro endpoint HTTP do worker (Fase 5), usada pelo disparo manual
// no admin (/admin/processos/:id). O worker já persiste os pagamentos no Supabase por
// conta própria (consultarEPersistirPagamentos, Fase 4) sempre que /valor-pago é chamado —
// essa function só existe pra não expor WORKER_HTTP_SECRET no browser.
const WORKER_URL = "https://crawler.forjuris.com.br/valor-pago";
const WORKER_SECRET = Deno.env.get("WORKER_HTTP_SECRET") ?? "";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);
  if (!WORKER_SECRET) return json({ error: "worker não configurado (WORKER_HTTP_SECRET ausente)" }, 500);

  const body = await req.json().catch(() => ({}));
  const processoDepre = String(body.processo_depre ?? "").trim();
  if (!/\.8\.26\.0500$/.test(processoDepre)) {
    return json({ error: "processo_depre inválido (esperado terminar em .8.26.0500)" }, 400);
  }

  try {
    // Folga generosa (retry de captcha do lado do worker) — chamada manual, não está no
    // caminho crítico de uma busca pública, então pode esperar mais que os 90s do
    // buscar-precatorio (ainda dentro do teto ~150s da edge function).
    const r = await fetch(WORKER_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Worker-Secret": WORKER_SECRET },
      body: JSON.stringify({ processo_depre: processoDepre }),
      signal: AbortSignal.timeout(120_000),
    });
    const data = await r.json().catch(() => ({}));
    if (!r.ok) return json({ error: data?.error ?? `worker respondeu ${r.status}` }, r.status);
    return json(data);
  } catch (e) {
    return json({ error: `falha ao consultar worker: ${String(e)}` }, 502);
  }
});
