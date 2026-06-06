import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MAX_ATTEMPTS = 5;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { lead_id?: string; canal?: string; codigo?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { lead_id, canal, codigo } = body;

  if (!lead_id || !canal || !codigo) {
    return json({ error: "lead_id, canal e codigo são obrigatórios" }, 400);
  }
  if (canal !== "email" && canal !== "whatsapp") {
    return json({ error: "canal inválido" }, 400);
  }
  if (!/^\d{6}$/.test(codigo)) {
    return json({ error: "Código deve ter 6 dígitos" }, 400);
  }
  if (!/^[0-9a-f-]{36}$/i.test(lead_id)) {
    return json({ error: "lead_id inválido" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: token, error: tokenError } = await supabase
    .from("tokens")
    .select("id, codigo, expires_at, usado, tentativas")
    .eq("lead_id", lead_id)
    .eq("canal", canal)
    .eq("usado", false)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  if (tokenError) {
    return json({ error: "Erro ao validar código" }, 500);
  }
  if (!token) {
    return json({ error: "Nenhum código ativo. Solicite um novo." }, 404);
  }

  if (new Date(token.expires_at).getTime() < Date.now()) {
    await supabase.from("tokens").update({ usado: true }).eq("id", token.id);
    return json({ error: "Código expirado. Solicite um novo." }, 410);
  }

  if (token.tentativas >= MAX_ATTEMPTS) {
    await supabase.from("tokens").update({ usado: true }).eq("id", token.id);
    return json({ error: "Muitas tentativas. Solicite um novo código." }, 429);
  }

  if (!timingSafeEqual(token.codigo, codigo)) {
    await supabase
      .from("tokens")
      .update({ tentativas: token.tentativas + 1 })
      .eq("id", token.id);
    return json({ error: "Código incorreto." }, 401);
  }

  await supabase.from("tokens").update({ usado: true }).eq("id", token.id);

  const leadPatch =
    canal === "email"
      ? { token_email_validado: true }
      : { token_telefone_validado: true };

  const { error: updateError } = await supabase
    .from("leads")
    .update(leadPatch)
    .eq("id", lead_id);

  if (updateError) {
    return json({ error: "Erro ao atualizar lead" }, 500);
  }

  // Se ambos canais já estão validados, carimba verified_at
  const { data: leadCheck } = await supabase
    .from("leads")
    .select("token_email_validado, token_telefone_validado, verified_at")
    .eq("id", lead_id)
    .single();
  if (
    leadCheck?.token_email_validado &&
    leadCheck?.token_telefone_validado &&
    !leadCheck?.verified_at
  ) {
    await supabase
      .from("leads")
      .update({ verified_at: new Date().toISOString() })
      .eq("id", lead_id);
  }

  await supabase.from("funnel_events").insert({
    session_id: lead_id,
    lead_id,
    event_type: canal === "email" ? "token_email_validado" : "token_whatsapp_validado",
    context: { canal },
  });

  return json({ success: true });
});

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
