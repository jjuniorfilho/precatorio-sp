// FOR-74 — Busca pública DB-first (CPF/CNPJ/CNJ). Mescla schema novo (FOR-69) +
// precatorios legada; refresh por TTL (enqueue, sem crawl inline); miss → DOCPARTE no e-SAJ.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const TJSP = "https://esaj.tjsp.jus.br/cpopg";
const TJSP_HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/120.0 Safari/537.36",
  "Accept-Language": "pt-BR,pt;q=0.9",
  Referer: `${TJSP}/abrirConsultaDeRequisitorios.do`,
};
const DEPRE_RE = /\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.0500/g;

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const digits = (s: string) => (s ?? "").replace(/\D/g, "");
const maskCpf = (doc: string | null) => !doc ? null : doc.length === 11 ? `${doc.slice(0,3)}.***.***-${doc.slice(9)}` : doc;

async function tjspSession() {
  try {
    const r = await fetch(`${TJSP}/abrirConsultaDeRequisitorios.do`, { headers: TJSP_HEADERS, signal: AbortSignal.timeout(15000) });
    if (!r.ok) return null;
    const html = await r.text();
    const csrf = html.match(/name="_csrf"[^>]+value="([^"]+)"/)?.[1];
    const js = (r.headers.get("set-cookie") ?? "").match(/JSESSIONID=([^;]+)/);
    return csrf ? { csrf, cookie: js ? `JSESSIONID=${js[1]}` : "" } : null;
  } catch { return null; }
}
async function docparteCnjs(doc: string, sess: { csrf: string; cookie: string }): Promise<string[]> {
  try {
    const params = new URLSearchParams({ conversationId: "", cbPesquisa: "DOCPARTE", "dadosConsulta.localPesquisa.cdLocal": "-1", "dadosConsulta.valorConsulta": doc, consultaDeRequisitorios: "true", _csrf: sess.csrf });
    const r = await fetch(`${TJSP}/search.do?${params}`, { headers: { ...TJSP_HEADERS, ...(sess.cookie ? { Cookie: sess.cookie } : {}) }, signal: AbortSignal.timeout(15000) });
    if (!r.ok) return [];
    const html = await r.text();
    return [...new Set([...html.matchAll(DEPRE_RE)].map((m) => m[0]))];
  } catch { return []; }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const body = await req.json().catch(() => ({}));
  const docRaw = digits(body.documento ?? "");
  const procRaw = digits(body.processo ?? "");
  const tipoBusca = procRaw ? "processo" : docRaw.length === 11 ? "cpf" : docRaw.length === 14 ? "cnpj" : null;
  if (!tipoBusca) return json({ error: "documento ou processo inválido" }, 400);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const sid = crypto.randomUUID();
  const logBusca = (ctx: Record<string, unknown>) =>
    sb.from("funnel_events").insert({ session_id: sid, event_type: "busca_realizada", context: ctx }).then(() => {});

  // ---- DB-first: schema novo ----
  let incidenteIds: string[] = [];
  if (tipoBusca === "processo") {
    const { data } = await sb.from("processos").select("id").eq("cnj_normalizado", procRaw);
    const procIds = (data ?? []).map((r: any) => r.id);
    if (procIds.length) {
      const { data: inc } = await sb.from("incidentes").select("id").in("processo_id", procIds);
      incidenteIds = (inc ?? []).map((r: any) => r.id);
    }
  } else {
    const { data } = await sb.from("partes").select("incidente_id").eq("documento", docRaw);
    incidenteIds = [...new Set((data ?? []).map((r: any) => r.incidente_id))];
  }

  let novos: any[] = [];
  if (incidenteIds.length) {
    const { data } = await sb.from("incidentes")
      .select("id, processo_codigo, cnj, numero_incidente, tipo_previsto, numero_depre, macrofase, fase, status, valor_acao, data_base, elegivel, possivelmente_pago, oficio_expedido, tramitacao_prioritaria, processos!inner(id, cnj, ente_nome, ente_esfera, next_crawl_at)")
      .in("id", incidenteIds);
    novos = data ?? [];
  }

  // ---- legado precatorios ----
  let legado: any[] = [];
  if (tipoBusca === "processo") {
    const { data } = await sb.from("precatorios_publico").select("*").or(`processo_depre.eq.${body.processo},autos.eq.${body.processo}`);
    legado = data ?? [];
  } else {
    const col = tipoBusca === "cpf" ? "cpf_titular" : "cnpj_titular";
    const { data } = await sb.from("precatorios").select("processo_depre").eq(col, docRaw);
    const deps = (data ?? []).map((r: any) => r.processo_depre);
    if (deps.length) {
      const { data: pub } = await sb.from("precatorios_publico").select("*").in("processo_depre", deps);
      legado = pub ?? [];
    }
  }

  // ---- refresh por TTL (assíncrono) ----
  const now = Date.now();
  const staleCnjs = new Set<string>();
  for (const i of novos) {
    const p = i.processos;
    if (p?.cnj && (!p.next_crawl_at || new Date(p.next_crawl_at).getTime() <= now)) staleCnjs.add(p.cnj);
  }
  for (const cnj of staleCnjs) await sb.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: "refresh" });

  // ---- merge + máscara ----
  const items = [
    ...novos.map((i) => ({
      fonte: "base", cnj: i.cnj ?? i.processos?.cnj, instrumento: i.tipo_previsto, macrofase: i.macrofase, fase: i.fase,
      status: i.status, elegivel: i.elegivel, possivelmente_pago: i.possivelmente_pago, oficio_expedido: i.oficio_expedido,
      tramitacao_prioritaria: i.tramitacao_prioritaria, valor_acao: i.valor_acao, numero_depre: i.numero_depre,
      ente_nome: i.processos?.ente_nome, ente_esfera: i.processos?.ente_esfera,
    })),
    ...legado.map((p) => ({
      fonte: "depre", cnj: p.autos ?? p.processo_depre, instrumento: "Precatorio", macrofase: "precatorio_efetivo",
      fase: "oc", status: p.status, oficio_expedido: true, saldo: p.saldo_depre, numero_depre: p.processo_depre,
      ente_nome: p.devedora, autor: maskCpf(null),
    })),
  ];
  // dedupe por numero_depre/cnj
  const seen = new Set<string>(); const merged = items.filter((x) => { const k = x.numero_depre ?? x.cnj ?? Math.random().toString(); if (seen.has(k)) return false; seen.add(k); return true; });

  if (merged.length > 0) {
    logBusca({ tipo: tipoBusca, source: "db", found: true, count: merged.length });
    return json({ flag: "encontrado", source: "db", items: merged });
  }

  // ---- miss → DOCPARTE no e-SAJ (só descobre + enfileira) ----
  if (tipoBusca !== "processo") {
    const sess = await tjspSession();
    if (sess) {
      const cnjs = await docparteCnjs(docRaw, sess);
      for (const c of cnjs) await sb.rpc("enqueue_crawler_job", { p_processo_codigo: c, p_origem: "manual" });
      if (cnjs.length) { logBusca({ tipo: tipoBusca, source: "tjsp", found: true, enfileirados: cnjs.length }); return json({ flag: "em_processamento", enfileirados: cnjs.length }); }
    }
  }
  logBusca({ tipo: tipoBusca, source: "db", found: false });
  return json({ flag: "nao_encontrado" });
});
