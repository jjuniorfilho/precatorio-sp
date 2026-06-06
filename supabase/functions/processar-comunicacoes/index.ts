// Worker chamado por pg_cron a cada 5 min: envia as comunicações
// agendadas cujo agendado_para já passou.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MAX_TENTATIVAS = 3;
const BATCH = 25;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  const { data: pendentes, error } = await supabase
    .from("comunicacoes_agendadas")
    .select("id, lead_id, canal, tipo, payload, tentativas")
    .eq("status", "pendente")
    .lte("agendado_para", new Date().toISOString())
    .lt("tentativas", MAX_TENTATIVAS)
    .order("agendado_para", { ascending: true })
    .limit(BATCH);

  if (error) return json({ error: error.message }, 500);

  const results: Array<{ id: string; ok: boolean; erro?: string }> = [];

  for (const c of pendentes ?? []) {
    try {
      if (c.canal === "whatsapp") {
        const payload = c.payload as { texto?: string; telefone?: string } | null;
        if (!payload?.texto || !payload?.telefone) throw new Error("payload inválido");
        await sendWhatsApp(payload.telefone, payload.texto);
      } else {
        throw new Error(`canal não suportado: ${c.canal}`);
      }
      await supabase
        .from("comunicacoes_agendadas")
        .update({ status: "enviado", enviado_em: new Date().toISOString(), tentativas: c.tentativas + 1 })
        .eq("id", c.id);
      await supabase.from("funnel_events").insert({
        session_id: c.lead_id, lead_id: c.lead_id,
        event_type: "comunicacao_enviada", context: { tipo: c.tipo, canal: c.canal },
      });
      results.push({ id: c.id, ok: true });
    } catch (e) {
      const novaTentativa = c.tentativas + 1;
      const novoStatus = novaTentativa >= MAX_TENTATIVAS ? "falhou" : "pendente";
      await supabase
        .from("comunicacoes_agendadas")
        .update({ status: novoStatus, tentativas: novaTentativa, erro: String(e) })
        .eq("id", c.id);
      results.push({ id: c.id, ok: false, erro: String(e) });
    }
  }

  return json({ processados: results.length, results });
});

async function sendWhatsApp(telefone: string, texto: string) {
  const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const fromRaw = Deno.env.get("TWILIO_WHATSAPP_FROM");
  if (!accountSid || !authToken || !fromRaw) throw new Error("Twilio não configurado");
  const from = fromRaw.startsWith("whatsapp:") ? fromRaw : `whatsapp:${fromRaw}`;
  const digits = telefone.replace(/\D/g, "");
  const e164 = telefone.trim().startsWith("+")
    ? `+${digits}`
    : digits.startsWith("55") ? `+${digits}` : `+55${digits}`;
  const to = `whatsapp:${e164}`;
  const url = `https://api.twilio.com/2010-04-01/Accounts/${accountSid}/Messages.json`;
  const auth = btoa(`${accountSid}:${authToken}`);
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ To: to, From: from, Body: texto }),
  });
  if (!res.ok) throw new Error(`Twilio ${res.status}: ${await res.text()}`);
}

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
