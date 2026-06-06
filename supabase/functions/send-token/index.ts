import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const RATE_LIMIT_MAX = 3;
const RATE_LIMIT_WINDOW_MINUTES = 30;
const TOKEN_TTL_MINUTES = 10;

Deno.serve(async (req) => {
  console.log("[send-token] request:", req.method);

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { lead_id?: string; canal?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { lead_id, canal } = body;
  console.log("[send-token] body:", JSON.stringify({ lead_id, canal }));

  if (!lead_id || !canal) {
    return json({ error: "lead_id e canal são obrigatórios" }, 400);
  }

  if (canal !== "email" && canal !== "whatsapp") {
    return json({ error: "canal deve ser 'email' ou 'whatsapp'" }, 400);
  }

  // Service role client — acesso irrestrito às tabelas protegidas por RLS
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } }
  );

  // 1. Buscar lead
  const { data: lead, error: leadError } = await supabase
    .from("leads")
    .select("id, nome, email, telefone")
    .eq("id", lead_id)
    .single();

  if (leadError || !lead) {
    return json({ error: "Lead não encontrado" }, 404);
  }

  // 2. Rate limit: max 3 envios por lead+canal em 30 minutos
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MINUTES * 60 * 1000).toISOString();
  const { count: recentCount, error: rateError } = await supabase
    .from("tokens")
    .select("id", { count: "exact", head: true })
    .eq("lead_id", lead_id)
    .eq("canal", canal)
    .gte("created_at", windowStart);

  if (rateError) {
    return json({ error: "Erro interno ao verificar rate limit" }, 500);
  }

  if ((recentCount ?? 0) >= RATE_LIMIT_MAX) {
    return json(
      { error: "Muitas tentativas. Aguarde 30 minutos antes de solicitar novo código." },
      429
    );
  }

  // 3. Invalidar tokens anteriores do mesmo lead+canal
  await supabase
    .from("tokens")
    .update({ usado: true })
    .eq("lead_id", lead_id)
    .eq("canal", canal)
    .eq("usado", false);

  // 4. Gerar código OTP de 6 dígitos com CSPRNG
  const rand = new Uint32Array(1);
  crypto.getRandomValues(rand);
  const codigo = String(100000 + (rand[0] % 900000));
  const expires_at = new Date(Date.now() + TOKEN_TTL_MINUTES * 60 * 1000).toISOString();

  // 5. Salvar token
  const { error: insertTokenError } = await supabase
    .from("tokens")
    .insert({ lead_id, canal, codigo, expires_at, usado: false, tentativas: 0 });

  if (insertTokenError) {
    return json({ error: "Erro ao salvar token" }, 500);
  }

  // 6. Enviar código pelo canal
  try {
    if (canal === "email") {
      await sendEmail(lead.email, lead.nome, codigo);
    } else {
      await sendWhatsApp(lead.telefone, codigo);
    }
  } catch (err) {
    console.error("Erro ao enviar:", err);
    return json({ error: "Erro ao enviar código. Tente novamente." }, 502);
  }

  // 7. Registrar evento no funil
  const eventType = canal === "email" ? "token_email_enviado" : "token_whatsapp_enviado";
  await supabase.from("funnel_events").insert({
    session_id: lead_id, // usa lead_id como session_id quando não há sessão disponível
    lead_id,
    event_type: eventType,
    context: { canal },
  });

  return json({ success: true, expires_at });
});

async function sendEmail(to: string, nome: string, codigo: string): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@forjuris.com.br";

  if (!apiKey) throw new Error("RESEND_API_KEY não configurado");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: `Forjuris <${fromEmail}>`,
      to: [to],
      subject: "Seu código de verificação — Forjuris",
      html: emailTemplate(nome, codigo),
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Resend error ${res.status}: ${body}`);
  }
}

async function sendWhatsApp(telefone: string, codigo: string): Promise<void> {
  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const fromRaw = Deno.env.get("TWILIO_WHATSAPP_FROM");

  if (!accountSid || !authToken || !fromRaw) {
    throw new Error("Variáveis Twilio não configuradas");
  }

  // Garante prefixo whatsapp: no remetente, mesmo se o secret estiver sem
  const from = fromRaw.startsWith("whatsapp:") ? fromRaw : `whatsapp:${fromRaw}`;

  // Normalizar telefone para E.164 (Brasil por padrão se vier sem +)
  const digits = telefone.replace(/\D/g, "");
  const e164 = telefone.trim().startsWith("+")
    ? `+${digits}`
    : digits.startsWith("55")
      ? `+${digits}`
      : `+55${digits}`;
  const to = `whatsapp:${e164}`;
  console.log("[send-token] whatsapp from/to:", from, to);

  const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
  const auth = btoa(`${accountSid}:${authToken}`);

  const res = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Basic ${auth}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      To: to,
      From: from,
      Body: `[Forjuris] Seu código: ${codigo}. Válido por 10 minutos.`,
    }),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Twilio error ${res.status}: ${body}`);
  }
}

function emailTemplate(nome: string, codigo: string): string {
  return `
<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"></head>
<body style="font-family:sans-serif;max-width:480px;margin:0 auto;padding:24px;color:#1a1a1a">
  <h2 style="margin-bottom:8px">Olá, ${nome}!</h2>
  <p>Seu código de verificação para acessar sua consulta de precatório é:</p>
  <div style="font-size:36px;font-weight:bold;letter-spacing:8px;text-align:center;
              padding:20px;background:#f5f5f5;border-radius:8px;margin:24px 0">
    ${codigo}
  </div>
  <p style="color:#666;font-size:14px">Válido por 10 minutos. Não compartilhe este código.</p>
  <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
  <p style="font-size:12px;color:#999">
    Se você não solicitou este código, ignore este e-mail.
  </p>
</body>
</html>`;
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
