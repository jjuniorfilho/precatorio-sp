import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const TJSP_BASE = "https://esaj.tjsp.jus.br/cpopg";
const TJSP_HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept-Language": "pt-BR,pt;q=0.9",
  "Referer": `${TJSP_BASE}/abrirConsultaDeRequisitorios.do`,
};
const REGEX_DEPRE = /\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.0500/g;

interface TjspSession { csrf: string; cookie: string; }

async function getTjspSession(): Promise<TjspSession | null> {
  try {
    const res = await fetch(`${TJSP_BASE}/abrirConsultaDeRequisitorios.do`, { headers: TJSP_HEADERS, signal: AbortSignal.timeout(15_000) });
    if (!res.ok) return null;
    const html = await res.text();
    const csrfMatch = html.match(/name="_csrf"[^>]+value="([^"]+)"/);
    if (!csrfMatch) return null;
    const setCookie = res.headers.get("set-cookie") ?? "";
    const jsessionMatch = setCookie.match(/JSESSIONID=([^;]+)/);
    return { csrf: csrfMatch[1], cookie: jsessionMatch ? `JSESSIONID=${jsessionMatch[1]}` : "" };
  } catch { return null; }
}

async function searchTjspByDoc(documento: string, session: TjspSession): Promise<string | null> {
  try {
    const params = new URLSearchParams({ conversationId: "", cbPesquisa: "DOCPARTE", "dadosConsulta.localPesquisa.cdLocal": "-1", "dadosConsulta.valorConsulta": documento, consultaDeRequisitorios: "true", _csrf: session.csrf });
    const res = await fetch(`${TJSP_BASE}/search.do?${params}`, { headers: { ...TJSP_HEADERS, ...(session.cookie ? { Cookie: session.cookie } : {}) }, signal: AbortSignal.timeout(15_000) });
    if (!res.ok) return null;
    return res.text();
  } catch { return null; }
}

function extractDepres(html: string): string[] {
  return [...new Set([...html.matchAll(REGEX_DEPRE)].map((m) => m[0]))];
}

function extractNome(html: string): string | null {
  const patterns = [
    /class="[^"]*nomeParte[^"]*"[^>]*>\s*([^<]{5,200})/i,
    /Requerente[^<]{0,30}:\s*<[^>]*>\s*([^<]{5,80})/i,
    /Exequente[^<]{0,30}:\s*<[^>]*>\s*([^<]{5,80})/i,
    /class="[^"]*partePrincipal[^"]*"[^>]*>\s*([A-ZÁÉÍÓÚÀÂÊÔÇÃÕ\s]{10,60})/,
  ];
  for (const pattern of patterns) {
    const m = html.match(pattern);
    if (m) return m[1].trim();
  }
  return null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { documento?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON body" }, 400); }

  const rawDoc = (body.documento ?? "").replace(/\D/g, "");
  if (rawDoc.length !== 11 && rawDoc.length !== 14) return json({ error: "documento inválido" }, 400);

  const col = rawDoc.length === 11 ? "cpf_titular" : "cnpj_titular";
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });

  // DB-first: só retorna do banco se CPF já tem autor preenchido em todos os processos
  const { data: dbRows } = await supabase.from("precatorios").select("processo_depre, autor").eq(col, rawDoc);
  const allHaveNome = dbRows && dbRows.length > 0 && dbRows.every((r: { autor: string | null }) => !!r.autor);

  if (allHaveNome) {
    const processos = (dbRows as { processo_depre: string }[]).map((r) => r.processo_depre);
    const { data: publicRows } = await supabase.from("precatorios_publico").select("*").in("processo_depre", processos);
    supabase.from("funnel_events").insert({ session_id: crypto.randomUUID(), event_type: "busca_realizada", context: { tipo: col === "cpf_titular" ? "cpf" : "cnpj", source: "db" } }).then(() => {});
    return json({ data: publicRows ?? [], source: "db" });
  }
  // Se autor ainda é null → consulta TJSP para enriquecer

  const session = await getTjspSession();
  if (!session) return json({ flag: "tjsp_unavailable" });

  const html = await searchTjspByDoc(rawDoc, session);
  if (!html) return json({ flag: "tjsp_unavailable" });

  if (html.includes("Não existem informações disponíveis")) {
    supabase.from("funnel_events").insert({ session_id: crypto.randomUUID(), event_type: "busca_realizada", context: { tipo: col === "cpf_titular" ? "cpf" : "cnpj", source: "tjsp", found: false } }).then(() => {});
    return json({ flag: "not_found" });
  }

  const depres = extractDepres(html);
  if (depres.length === 0) return json({ flag: "not_found" });

  const { data: matches } = await supabase.from("precatorios").select("processo_depre").in("processo_depre", depres);
  if (!matches || matches.length === 0) return json({ flag: "not_found" });

  const matchedProcessos = matches.map((r: { processo_depre: string }) => r.processo_depre);
  const updatePayload: Record<string, string | null> = { [col]: rawDoc };
  const nome = extractNome(html);
  if (nome) updatePayload.autor = nome;

  await supabase.from("precatorios").update(updatePayload).in("processo_depre", matchedProcessos);

  const { data: publicRows } = await supabase.from("precatorios_publico").select("*").in("processo_depre", matchedProcessos);

  supabase.from("funnel_events").insert({ session_id: crypto.randomUUID(), event_type: "busca_realizada", context: { tipo: col === "cpf_titular" ? "cpf" : "cnpj", source: "tjsp", found: true, count: matchedProcessos.length } }).then(() => {});

  return json({ data: publicRows ?? [], source: "tjsp" });
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
