// Reutiliza um lead já verificado (email + whatsapp validados) para uma nova
// consulta de processo, sem exigir nova verificação. Cria uma nova linha em
// `leads` com os mesmos dados de contato e tokens já marcados como validados.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: {
    prev_lead_id?: string;
    processo?: string;
    saldo?: number;
    devedora?: string | null;
    intent?: string | null;
    session_id?: string;
  };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { prev_lead_id, processo, saldo, devedora, intent, session_id } = body;
  if (!prev_lead_id || !/^[0-9a-f-]{36}$/i.test(prev_lead_id)) {
    return json({ error: "prev_lead_id inválido" }, 400);
  }
  if (!processo || typeof processo !== "string") {
    return json({ error: "processo obrigatório" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: prev, error: prevErr } = await supabase
    .from("leads")
    .select("nome, email, telefone, relacao, token_email_validado, token_telefone_validado, lgpd_consent, verified_at")
    .eq("id", prev_lead_id)
    .single();
  if (prevErr || !prev) return json({ error: "Lead anterior não encontrado" }, 404);
  if (!prev.token_email_validado || !prev.token_telefone_validado) {
    return json({ error: "Lead anterior não está totalmente verificado" }, 403);
  }
  // Expira após 90 dias de inatividade
  const NINETY_DAYS_MS = 90 * 24 * 60 * 60 * 1000;
  const verifiedAtMs = prev.verified_at ? new Date(prev.verified_at).getTime() : 0;
  if (!verifiedAtMs || Date.now() - verifiedAtMs > NINETY_DAYS_MS) {
    return json({ error: "Verificação expirada — refaça a validação", expired: true }, 403);
  }

  const new_id = crypto.randomUUID();
  const { error: insErr } = await supabase.from("leads").insert({
    id: new_id,
    nome: prev.nome,
    email: prev.email,
    telefone: prev.telefone,
    relacao: prev.relacao,
    processo_depre: processo,
    saldo_consultado: typeof saldo === "number" ? saldo : 0,
    devedora: devedora ?? null,
    intent: intent ?? "info",
    session_id: session_id ?? null,
    lgpd_consent: prev.lgpd_consent,
    lgpd_consent_at: new Date().toISOString(),
    token_email_validado: true,
    token_telefone_validado: true,
    verified_at: prev.verified_at,
  });
  if (insErr) return json({ error: insErr.message }, 500);

  await supabase.from("funnel_events").insert({
    session_id: session_id ?? new_id,
    lead_id: new_id,
    event_type: "lead_reused",
    context: { prev_lead_id, processo },
  });

  return json({
    success: true,
    lead_id: new_id,
    nome: prev.nome,
    email: prev.email,
    telefone: prev.telefone,
    relacao: prev.relacao,
  });
});

function json(b: unknown, status = 200) {
  return new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
