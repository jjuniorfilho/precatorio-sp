import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

// ─── Helpers ──────────────────────────────────────────────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function formatCurrency(centavos: number): string {
  return (centavos / 100).toLocaleString("pt-BR", {
    style: "currency",
    currency: "BRL",
  });
}

function maskCpf(cpf: string): string {
  // 15125959855 → "151.***.***-55"
  const d = cpf.replace(/\D/g, "");
  if (d.length !== 11) return "***.***.***-**";
  return `${d.slice(0, 3)}.***.***-${d.slice(9)}`;
}

function maskCnpj(cnpj: string): string {
  // 11222333000144 → "11.***.***/0001-44"
  const d = cnpj.replace(/\D/g, "");
  if (d.length !== 14) return "**.***.***/**-**";
  return `${d.slice(0, 2)}.***.***/${d.slice(8, 12)}-${d.slice(12)}`;
}

function maskDoc(cpf: string | null, cnpj: string | null): string | null {
  if (cpf) return maskCpf(cpf);
  if (cnpj) return maskCnpj(cnpj);
  return null;
}

// ─── Types ────────────────────────────────────────────────────────────────────

interface Lead {
  id: string;
  nome: string;
  email: string;
  telefone: string;
  relacao: string;
  processo_depre: string;
  saldo_consultado: number;
  devedora: string | null;
}

interface Precatorio {
  id: string;
  processo_depre: string;
  autos: string | null;
  devedora: string;
  saldo_depre: number;
  natureza: string;
  status: string;
  suspenso: boolean;
  data_protocolo: string | null;
  autor: string | null;
  cpf_titular: string | null;
  cnpj_titular: string | null;
  ordem_pagamento: number | null;
}

// ─── Email template ───────────────────────────────────────────────────────────

function buildEmailHtml(
  lead: Lead,
  precatorios: Precatorio[],
  titularNome: string | null,
  docMasked: string | null,
): string {
  const total = precatorios.reduce((s, p) => s + (p.saldo_depre ?? 0), 0);
  const isTitular = lead.relacao === "titular";
  const titularLabel = titularNome ?? "—";
  const docLabel = docMasked ?? "—";

  const warningBlock = !isTitular
    ? `<tr><td style="padding:0 24px 16px">
        <div style="background:#fffbeb;border:1px solid #fcd34d;border-radius:8px;padding:12px 16px;font-size:13px;color:#92400e">
          ⚠️ O solicitante é diferente do titular registrado no TJSP.
          A cessão do precatório só pode ser feita pelo próprio titular
          ou mediante procuração específica.
        </div>
      </td></tr>`
    : "";

  const processosHtml = precatorios
    .map(
      (p, i) => `
    <tr><td style="padding:0 24px 16px">
      <div style="border:1px solid #e5e7eb;border-radius:8px;overflow:hidden">
        <div style="background:#f9fafb;padding:10px 16px;font-size:11px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.05em">
          Precatório ${i + 1} de ${precatorios.length}
        </div>
        <table width="100%" cellpadding="0" cellspacing="0" style="font-size:13px">
          <tr>
            <td style="padding:10px 16px 4px;color:#6b7280">Processo DEPRE</td>
            <td style="padding:10px 16px 4px;text-align:right;font-family:monospace;color:#1e3a5f;font-weight:600">${p.processo_depre}</td>
          </tr>
          ${p.autos ? `<tr><td style="padding:4px 16px;color:#6b7280">Autos de origem</td><td style="padding:4px 16px;text-align:right;font-family:monospace">${p.autos}</td></tr>` : ""}
          <tr>
            <td style="padding:4px 16px;color:#6b7280">Devedora</td>
            <td style="padding:4px 16px;text-align:right">${p.devedora}</td>
          </tr>
          <tr>
            <td style="padding:4px 16px 10px;color:#6b7280">Saldo DEPRE</td>
            <td style="padding:4px 16px 10px;text-align:right;color:#16a34a;font-weight:700">${formatCurrency(p.saldo_depre)}</td>
          </tr>
          ${p.ordem_pagamento ? `<tr><td style="padding:4px 16px 10px;color:#6b7280">Ordem de pagamento</td><td style="padding:4px 16px 10px;text-align:right">#${p.ordem_pagamento.toLocaleString("pt-BR")}</td></tr>` : ""}
        </table>
      </div>
    </td></tr>`,
    )
    .join("");

  return `<!DOCTYPE html>
<html lang="pt-BR">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f3f4f6;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f3f4f6;padding:32px 0">
    <tr><td align="center">
      <table width="100%" style="max-width:560px;background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 1px 3px rgba(0,0,0,.1)" cellpadding="0" cellspacing="0">

        <!-- Header -->
        <tr><td style="background:#1e3a5f;padding:24px;text-align:center">
          <span style="color:#ffffff;font-size:20px;font-weight:700;letter-spacing:.02em">Forjuris</span>
          <p style="color:#93c5fd;font-size:13px;margin:4px 0 0">Relatório de Precatório DEPRE</p>
        </td></tr>

        <!-- Titular -->
        <tr><td style="padding:24px 24px 0">
          <div style="border:1px solid #e5e7eb;border-radius:8px;overflow:hidden">
            <div style="background:#f9fafb;padding:10px 16px;font-size:11px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.05em">
              Titular do Precatório
            </div>
            <table width="100%" cellpadding="0" cellspacing="0" style="font-size:13px">
              <tr>
                <td style="padding:10px 16px 4px;color:#6b7280">Nome</td>
                <td style="padding:10px 16px 4px;text-align:right;font-weight:600">${titularLabel}</td>
              </tr>
              <tr>
                <td style="padding:4px 16px 10px;color:#6b7280">Documento</td>
                <td style="padding:4px 16px 10px;text-align:right">${docLabel}</td>
              </tr>
            </table>
          </div>
        </td></tr>

        <!-- Solicitante -->
        <tr><td style="padding:16px 24px 0">
          <div style="border:1px solid #e5e7eb;border-radius:8px;overflow:hidden">
            <div style="background:#f9fafb;padding:10px 16px;font-size:11px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.05em">
              Solicitante da Consulta
            </div>
            <table width="100%" cellpadding="0" cellspacing="0" style="font-size:13px">
              <tr>
                <td style="padding:10px 16px 10px;color:#6b7280">Nome</td>
                <td style="padding:10px 16px 10px;text-align:right;font-weight:600">${lead.nome}</td>
              </tr>
            </table>
          </div>
        </td></tr>

        <!-- Warning if not titular -->
        ${warningBlock}

        <!-- Saldo total -->
        <tr><td style="padding:16px 24px 0">
          <div style="border:1px solid #d1fae5;border-radius:8px;background:#f0fdf4;padding:16px">
            <p style="margin:0;font-size:11px;font-weight:600;color:#6b7280;text-transform:uppercase;letter-spacing:.05em">Saldo DEPRE total (a receber)</p>
            <p style="margin:8px 0 0;font-size:24px;font-weight:700;color:#16a34a">${formatCurrency(total)}</p>
          </div>
        </td></tr>

        <!-- Processos -->
        <tr><td style="padding:16px 0 0"><table width="100%" cellpadding="0" cellspacing="0">${processosHtml}</table></td></tr>

        <!-- Footer -->
        <tr><td style="padding:24px;border-top:1px solid #f3f4f6;text-align:center">
          <p style="margin:0;font-size:12px;color:#9ca3af">
            Você recebeu esse relatório porque solicitou uma consulta em <strong>forjuris.com.br</strong>.<br>
            Esse e-mail foi gerado automaticamente — não responda.
          </p>
        </td></tr>

      </table>
    </td></tr>
  </table>
</body>
</html>`;
}

// ─── WhatsApp message ─────────────────────────────────────────────────────────

function buildWhatsAppText(
  lead: Lead,
  precatorios: Precatorio[],
  titularNome: string | null,
  docMasked: string | null,
): string {
  const total = precatorios.reduce((s, p) => s + (p.saldo_depre ?? 0), 0);
  const nome = lead.nome.split(" ")[0];
  const titular = titularNome ?? "—";
  const doc = docMasked ?? "—";

  const linhas = precatorios
    .map(
      (p, i) =>
        `*Precatório ${i + 1}/${precatorios.length}*\n` +
        `Processo: ${p.processo_depre}\n` +
        `Devedora: ${p.devedora}\n` +
        `Saldo: ${formatCurrency(p.saldo_depre)}`,
    )
    .join("\n\n");

  return (
    `Olá, ${nome}! 👋\n\n` +
    `Aqui está o relatório do precatório DEPRE solicitado.\n\n` +
    `*Titular:* ${titular}\n` +
    `*Documento:* ${doc}\n\n` +
    `*Saldo total:* ${formatCurrency(total)}\n\n` +
    linhas +
    `\n\n_Forjuris — forjuris.com.br_`
  );
}

// ─── Send email via Resend ────────────────────────────────────────────────────

async function sendEmail(
  to: string,
  nome: string,
  html: string,
): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) throw new Error("RESEND_API_KEY não configurada");

  const from = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@forjuris.com.br";

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from,
      to,
      subject: `Relatório do seu precatório — Forjuris`,
      html,
    }),
  });

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Resend error: ${err}`);
  }
}

// ─── Agendar WhatsApp via fila comunicacoes_agendadas ────────────────────────

async function agendarWhatsApp(
  supabase: ReturnType<typeof createClient>,
  leadId: string,
  mensagem: string,
): Promise<void> {
  const { error } = await supabase.from("comunicacoes_agendadas").insert({
    lead_id: leadId,
    canal: "whatsapp",
    tipo: "relatorio",
    agendado_para: new Date().toISOString(),
    status: "pendente",
    payload: { body: mensagem },
  });
  if (error) console.warn("[enviar-relatorio] fila WhatsApp error:", error);
}

// ─── Main handler ─────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: { lead_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  if (!body.lead_id) {
    return json({ error: "lead_id obrigatório" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // ── 1. Busca dados do lead ────────────────────────────────────────────────
  const { data: lead, error: leadErr } = await supabase
    .from("leads")
    .select("id, nome, email, telefone, relacao, processo_depre, saldo_consultado, devedora")
    .eq("id", body.lead_id)
    .single();

  if (leadErr || !lead) {
    return json({ error: "lead não encontrado" }, 404);
  }

  // ── 2. Busca precatório com CPF/CNPJ (service role acessa coluna privada) ─
  const { data: precatorio } = await supabase
    .from("precatorios")
    .select("*")
    .eq("processo_depre", lead.processo_depre)
    .single();

  // ── 3. Busca todos os precatórios do mesmo titular (se CPF/CNPJ disponível)
  let allPrecatorios: Precatorio[] = precatorio ? [precatorio] : [];

  if (precatorio?.cpf_titular) {
    const { data: rows } = await supabase
      .from("precatorios")
      .select("*")
      .eq("cpf_titular", precatorio.cpf_titular)
      .order("saldo_depre", { ascending: false });
    if (rows && rows.length > 0) allPrecatorios = rows as Precatorio[];
  } else if (precatorio?.cnpj_titular) {
    const { data: rows } = await supabase
      .from("precatorios")
      .select("*")
      .eq("cnpj_titular", precatorio.cnpj_titular)
      .order("saldo_depre", { ascending: false });
    if (rows && rows.length > 0) allPrecatorios = rows as Precatorio[];
  }

  // ── 4. Monta dados do titular ─────────────────────────────────────────────
  const titularNome = precatorio?.autor ?? null;
  const docMasked = maskDoc(
    precatorio?.cpf_titular ?? null,
    precatorio?.cnpj_titular ?? null,
  );

  // ── 5. Envia email ────────────────────────────────────────────────────────
  const html = buildEmailHtml(lead as Lead, allPrecatorios, titularNome, docMasked);

  try {
    await sendEmail(lead.email, lead.nome, html);
  } catch (e) {
    console.error("[enviar-relatorio] email error:", e);
    return json({ error: "Falha ao enviar email" }, 500);
  }

  // ── 6. Agenda WhatsApp via fila (processado por processar-comunicacoes) ──────
  const whatsappText = buildWhatsAppText(lead as Lead, allPrecatorios, titularNome, docMasked);
  await agendarWhatsApp(supabase, lead.id, whatsappText);

  // ── 7. Registra evento ────────────────────────────────────────────────────
  supabase.from("funnel_events").insert({
    session_id: crypto.randomUUID(),
    event_type: "relatorio_enviado",
    context: {
      lead_id: lead.id,
      processos: allPrecatorios.length,
      tem_titular: !!titularNome,
    },
  }).then(() => {});

  return json({ ok: true, processos: allPrecatorios.length });
});
