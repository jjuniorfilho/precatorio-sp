// FOR-75 — Captura pública (reusa `leads`) + e-mail dos andamentos (caso em_formacao).
// Enfileira em comunicacoes_agendadas (tipo andamentos_resumo); disparo existente envia.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const json = (d: unknown, s = 200) => new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const digits = (s: string) => (s ?? "").replace(/\D/g, "");
const isEmail = (e: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(e ?? "");
const ORIGEM: Record<string, string> = { em_formacao: "busca_em_formacao", nao_encontrado: "monitorar", com_saldo: "antecipacao", possivelmente_pago: "monitorar" };
const ANDAMENTOS_N = 10;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const body = await req.json().catch(() => ({}));
  const email = (body.email ?? "").trim().toLowerCase();
  const ramo = body.ramo ?? "monitorar";
  if (!isEmail(email)) return json({ error: "email inválido" }, 400);
  if (body.lgpd_consent !== true) return json({ error: "consentimento LGPD obrigatório" }, 400);

  const doc = digits(body.documento ?? "");
  const cnj = body.cnj ?? null;
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const sid = body.session_id ?? crypto.randomUUID();

  // upsert lead (email-only permitido após FOR-75)
  const { data: lead, error: leadErr } = await sb.from("leads").insert({
    email, cnj, origem: ORIGEM[ramo] ?? "monitorar", status_crm: "novo",
    lgpd_consent: true, lgpd_consent_at: new Date().toISOString(), session_id: sid,
  }).select("id").single();
  if (leadErr) return json({ error: `lead: ${leadErr.message}` }, 500);
  const leadId = (lead as { id: string }).id;

  sb.from("funnel_events").insert({ session_id: sid, lead_id: leadId, event_type: "cadastro_iniciado", context: { ramo, origem: ORIGEM[ramo] } }).then(() => {});

  // e-mail dos andamentos só no caso em_formacao
  if (ramo === "em_formacao" && (doc || cnj)) {
    let incidenteIds: string[] = [];
    if (cnj) {
      const { data: pr } = await sb.from("processos").select("id").eq("cnj_normalizado", digits(cnj));
      const ids = (pr ?? []).map((r: any) => r.id);
      if (ids.length) {
        const { data: inc } = await sb.from("incidentes").select("id").in("processo_id", ids);
        incidenteIds = (inc ?? []).map((r: any) => r.id);
      }
    } else {
      const { data: pa } = await sb.from("partes").select("incidente_id").eq("documento", doc);
      incidenteIds = [...new Set((pa ?? []).map((r: any) => r.incidente_id))];
    }

    let andamentos: any[] = [];
    if (incidenteIds.length) {
      const { data } = await sb.from("andamentos").select("data, descricao").in("incidente_id", incidenteIds).order("data", { ascending: false }).limit(ANDAMENTOS_N);
      andamentos = data ?? [];
    }

    const linhas = andamentos.map((a) => `<li><b>${a.data ?? ""}</b> — ${String(a.descricao ?? "").slice(0, 300)}</li>`).join("");
    const html = `
      <p>Olá! Você consultou um crédito contra o Estado/Município de SP em nosso sistema.</p>
      <p>Situação: <b>direito creditório — aguardando expedição do precatório</b>. Avisaremos quando virar pagável.</p>
      <p><b>Últimos andamentos do seu processo:</b></p>
      <ul>${linhas || "<li>Sem andamentos públicos recentes.</li>"}</ul>
      <p>Quando houver ofício/valor, entraremos em contato para uma eventual proposta de antecipação.</p>`;

    const { error: comErr } = await sb.from("comunicacoes_agendadas").insert({
      lead_id: leadId, canal: "email", tipo: "andamentos_resumo",
      agendado_para: new Date().toISOString(), status: "pendente",
      payload: { email, assunto: "Os últimos andamentos do seu processo", html },
    });
    if (comErr) return json({ ok: true, lead_id: leadId, email_enfileirado: false, aviso: comErr.message });
    return json({ ok: true, lead_id: leadId, email_enfileirado: true });
  }

  return json({ ok: true, lead_id: leadId, email_enfileirado: false });
});
