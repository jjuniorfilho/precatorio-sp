// FOR-70 — Ingestão DJEN/Comunica (TJSP) + flag SP (parte passiva) + roteamento e-SAJ/eproc.
// Disparada pelo cron `caderno-dje-diario` (X-Cron-Secret). Processa 1 dia por invocação.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const API = "https://comunicaapi.pje.jus.br/api/v1/comunicacao";
const TIME_BUDGET_MS = 120_000; // folga sob o limite ~150s da edge function

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
};

function esfera(nome: string): "Estadual" | "Municipal" | "Outro" {
  const n = (nome ?? "").toUpperCase();
  if (/\b(ESTADO|FAZENDA\s+(P[ÚU]BLICA\s+)?DO\s+ESTADO|FAZENDA\s+ESTADUAL|GOVERNO\s+DO\s+ESTADO|PROCURADORIA\s+GERAL\s+DO\s+ESTADO|UFESP|IPESP|DER|SPPREV|CDHU|CBPM)\b/.test(n)) return "Estadual";
  if (/\b(MUNIC[ÍI]PIO|PREFEITURA|FAZENDA\s+(P[ÚU]BLICA\s+)?MUNICIPAL|C[ÂA]MARA\s+MUNICIPAL)\b/.test(n)) return "Municipal";
  return "Outro";
}
const sistemaFromLink = (link: string | null): "esaj" | "eproc" | "outro" =>
  !link ? "outro" : /esaj\.tjsp\.jus\.br/i.test(link) ? "esaj" : /eproc.*\.tjsp\.jus\.br/i.test(link) ? "eproc" : "outro";

const norm = (s: string) => (s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
function yesterdayIso(): string {
  const d = new Date(Date.now() - 24 * 3600 * 1000);
  return d.toISOString().slice(0, 10);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const cronSecret = Deno.env.get("CRON_SECRET") ?? "";
  if (cronSecret && req.headers.get("x-cron-secret") !== cronSecret) return json({ error: "unauthorized" }, 401);

  const body = await req.json().catch(() => ({}));
  const date: string = body.date ?? yesterdayIso();
  const origem: string = body.backfill ? "backfill" : "dje_diario";

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // config
  const { data: cfg } = await supabase.from("coleta_config").select("enabled, params").eq("rotina", "caderno_dje").maybeSingle();
  if (cfg && cfg.enabled === false) return json({ skipped: "caderno_dje desabilitado" });
  const params = (cfg?.params ?? {}) as { classes_relevantes?: string[]; itens_por_pagina?: number };
  const classes = (params.classes_relevantes ?? []).map(norm);
  const pageSize = params.itens_por_pagina ?? 100;

  // idempotência por dia
  const { data: dia } = await supabase.from("djen_dias").select("status, ultima_pagina").eq("data", date).maybeSingle();
  if (dia?.status === "ok") return json({ skipped: `dia ${date} já processado` });
  let pagina = (dia?.status === "parcial" ? dia.ultima_pagina : 0) + 1;

  await supabase.from("djen_dias").upsert({ data: date, status: "parcial" }, { onConflict: "data" });
  const { data: run } = await supabase.from("coleta_runs")
    .insert({ rotina: origem === "backfill" ? "backfill" : "caderno_dje", status: "running" }).select("id").single();

  const t0 = Date.now();
  let total = 0, flagueados = 0, enfileirados = 0, eprocCount = 0, parcial = false;

  try {
    for (;;) {
      if (Date.now() - t0 > TIME_BUDGET_MS) { parcial = true; break; }
      const url = `${API}?siglaTribunal=TJSP&dataDisponibilizacaoInicio=${date}&dataDisponibilizacaoFim=${date}&pagina=${pagina}&itensPorPagina=${pageSize}`;
      const res = await fetch(url, { headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept": "application/json, text/plain, */*",
        "Accept-Language": "pt-BR,pt;q=0.9",
        "Referer": "https://comunica.pje.jus.br/",
        "Origin": "https://comunica.pje.jus.br",
      }, signal: AbortSignal.timeout(20_000) });
      if (!res.ok) throw new Error(`Comunica HTTP ${res.status} (pagina ${pagina})`);
      const payload = await res.json();
      const items: any[] = payload.items ?? [];
      if (items.length === 0) break;

      for (const it of items) {
        total++;
        const cnj: string | null = it.numeroprocessocommascara ?? null;
        if (!cnj) continue;
        const classeOk = classes.length === 0 || classes.some((c) => norm(it.nomeClasse ?? "").includes(c) || c.includes(norm(it.nomeClasse ?? "")));
        const passivoPublico = (it.destinatarios ?? []).some((d: any) => d.polo === "P" && esfera(d.nome) !== "Outro");
        if (!(classeOk && passivoPublico)) continue;
        flagueados++;

        const sistema = sistemaFromLink(it.link ?? null);
        if (sistema === "esaj") {
          const { error } = await supabase.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: origem });
          if (!error) enfileirados++;
        } else if (sistema === "eproc") {
          eprocCount++;
          await supabase.from("eproc_pendentes").upsert({
            cnj, numero_processo: it.numero_processo ?? null, link: it.link ?? null,
            nome_orgao: it.nomeOrgao ?? null, nome_classe: it.nomeClasse ?? null, data_disponibilizacao: date,
          }, { onConflict: "cnj", ignoreDuplicates: true });
        }
      }

      if (items.length < pageSize) break;
      pagina++;
    }

    const status = parcial ? "parcial" : "ok";
    await supabase.from("djen_dias").upsert({
      data: date, status, total, flagueados, enfileirados, eproc: eprocCount,
      ultima_pagina: pagina, processado_em: new Date().toISOString(),
    }, { onConflict: "data" });
    if (run) await supabase.from("coleta_runs").update({
      status: parcial ? "erro_parcial" : "sucesso", finished_at: new Date().toISOString(),
      itens_ok: enfileirados, itens_erro: 0, duracao_ms: Date.now() - t0,
      detalhe: { date, total, flagueados, enfileirados, eproc: eprocCount, parcial },
    }).eq("id", run.id);

    return json({ date, status, total, flagueados, enfileirados, eproc: eprocCount, parcial });
  } catch (err) {
    await supabase.from("djen_dias").upsert({ data: date, status: "erro", erro: String(err) }, { onConflict: "data" });
    if (run) await supabase.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { date, erro: String(err) } }).eq("id", run.id);
    return json({ error: String(err), date }, 500);
  }
});
