// Envia o relatório completo do precatório por email (HTML) +
// WhatsApp (mensagem 1) e agenda as mensagens 2 (D+1) e 3 (D+3).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { lead_id?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const { lead_id } = body;
  if (!lead_id || !/^[0-9a-f-]{36}$/i.test(lead_id)) {
    return json({ error: "lead_id inválido" }, 400);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Lead
  const { data: lead, error: leadErr } = await supabase
    .from("leads")
    .select("id, nome, email, telefone, processo_depre, devedora, saldo_consultado, relatorio_enviado_at, token_email_validado, token_telefone_validado")
    .eq("id", lead_id)
    .single();
  if (leadErr || !lead) return json({ error: "Lead não encontrado" }, 404);

  if (!lead.token_email_validado || !lead.token_telefone_validado) {
    return json({ error: "Lead não verificado completamente" }, 400);
  }

  if (lead.relatorio_enviado_at) {
    return json({ success: true, already_sent: true });
  }

  // Pode haver múltiplos processos selecionados (CSV em lead.processo_depre)
  const processos = String(lead.processo_depre || "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);

  const { data: precs } = await supabase
    .from("precatorios")
    .select("processo_depre, autos, autos_antigos, devedora, saldo_depre, valor_pago, natureza, status, ordem_pagamento, num_ordem, es_ep, ordem_orcamentaria, data_protocolo, dt_ensejo_ordem, condicao_superpreferencia, suspenso, autor, cpf_titular, cnpj_titular, advogados")
    .in("processo_depre", processos.length ? processos : [lead.processo_depre]);

  const precsList = (precs ?? []) as Array<Record<string, any>>;
  // Mantém a ordem do lead (placeholder para processos sem dados)
  const ordered = processos.map((p) => {
    const found = precsList.find((x) => x.processo_depre === p);
    return found ?? { processo_depre: p, _semDados: true };
  });

  // Titular/documento — tenta no selecionado; se vazio, busca em precatórios irmãos (mesmo autos).
  let first: Record<string, any> =
    precsList.find((p) => p.autor || p.cpf_titular || p.cnpj_titular) ?? precsList[0] ?? {};

  if (!first.autor && !first.cpf_titular && !first.cnpj_titular) {
    const autosList = [...new Set(precsList.map((p) => p.autos).filter(Boolean))];
    if (autosList.length > 0) {
      const { data: irmaos } = await supabase
        .from("precatorios")
        .select("autor, cpf_titular, cnpj_titular")
        .in("autos", autosList)
        .or("autor.not.is.null,cpf_titular.not.is.null,cnpj_titular.not.is.null")
        .limit(1);
      if (irmaos && irmaos.length > 0) {
        first = { ...first, ...irmaos[0] };
      }
    }
  }

  const doc = first.cpf_titular
    ? `CPF ${maskCpf(String(first.cpf_titular))}`
    : first.cnpj_titular
      ? `CNPJ ${maskCnpj(String(first.cnpj_titular))}`
      : "—";


  const solicitanteNome = lead.nome || "";
  const autorReal = (first.autor as string | undefined) || null;
  const ehMesmoTitular = autorReal && normalizeName(autorReal) === normalizeName(solicitanteNome);

  const saldoTotal = precsList.reduce((acc, p) => acc + (Number(p.saldo_depre) || 0), 0);
  const valorPagoTotal = precsList.reduce((acc, p) => acc + (Number(p.valor_pago) || 0), 0);

  const dados = {
    nome: solicitanteNome,
    primeiroNome: solicitanteNome.split(" ")[0] || "",
    solicitante: solicitanteNome || "—",
    titular: autorReal || "—",
    ehMesmoTitular: !!ehMesmoTitular,
    documento: doc,
    processo: processos[0] || lead.processo_depre,
    qtdProcessos: processos.length || 1,
    devedora: (first.devedora as string | undefined) || lead.devedora || "—",
    saldo: saldoTotal || Number(lead.saldo_consultado) || 0,
    valorPago: valorPagoTotal,
    precatorios: ordered,
  };

  const erros: string[] = [];

  // 1. Email
  try {
    await sendEmail(lead.email, dados);
  } catch (e) {
    console.error("[enviar-relatorio] email error:", e);
    erros.push(`email: ${String(e)}`);
  }

  // 2. WhatsApp mensagem 1 — envio imediato via Twilio
  let whatsappEnviado = false;
  try {
    await sendWhatsApp(lead.telefone, msgWhats1(dados));
    whatsappEnviado = true;
    await supabase.from("comunicacoes_agendadas").insert({
      lead_id,
      canal: "whatsapp",
      tipo: "relatorio",
      agendado_para: new Date().toISOString(),
      status: "enviado",
      enviado_em: new Date().toISOString(),
      tentativas: 1,
      payload: { texto: msgWhats1(dados), telefone: lead.telefone },
    });
  } catch (e) {
    console.error("[enviar-relatorio] whatsapp imediato error:", e);
    const erro = `whatsapp: ${String(e)}`;
    erros.push(erro);
    await supabase.from("comunicacoes_agendadas").insert({
      lead_id,
      canal: "whatsapp",
      tipo: "relatorio",
      agendado_para: new Date().toISOString(),
      status: "falhou",
      erro,
      tentativas: 1,
      payload: { texto: msgWhats1(dados), telefone: lead.telefone },
    });
  }

  // 3. Agenda follow-ups D+1 e D+3 na fila somente se o relatório inicial saiu
  if (whatsappEnviado) {
    const agora = Date.now();
    const dia = 24 * 60 * 60 * 1000;
    const { error: filaErr } = await supabase.from("comunicacoes_agendadas").insert([
      {
        lead_id,
        canal: "whatsapp",
        tipo: "follow_up_d1",
        agendado_para: new Date(agora + dia).toISOString(),
        status: "pendente",
        payload: { texto: msgWhats2(dados), telefone: lead.telefone },
      },
      {
        lead_id,
        canal: "whatsapp",
        tipo: "follow_up_d3",
        agendado_para: new Date(agora + 3 * dia).toISOString(),
        status: "pendente",
        payload: { texto: msgWhats3(dados), telefone: lead.telefone },
      },
    ]);
    if (filaErr) {
      console.error("[enviar-relatorio] fila follow-ups error:", filaErr);
      erros.push(`fila: ${filaErr.message}`);
    }
  }

  // 4. Marca enviado
  if (whatsappEnviado) {
    await supabase
      .from("leads")
      .update({ relatorio_enviado_at: new Date().toISOString() })
      .eq("id", lead_id);
  }

  // 5. Registra no histórico lead ↔ processo
  await supabase.from("lead_precatorios").insert({
    lead_id,
    processo_depre: lead.processo_depre,
    intent: (lead as { intent?: string }).intent ?? null,
    saldo_consultado: dados.saldo,
    devedora: dados.devedora,
  });

  await supabase.from("funnel_events").insert({
    session_id: lead_id,
    lead_id,
    event_type: "relatorio_enviado",
    context: { erros },
  });

  return json({ success: true, erros });
});

// ---------- Mensagens WhatsApp ----------
function msgWhats1(d: ReturnType<typeof buildDadosType>): string {
  return `Olá ${d.primeiroNome}! 👋 Aqui é da Forjuris.

Acabei de enviar para seu email o relatório completo do precatório:

👤 Titular do precatório: ${d.titular}
🙋 Solicitante: ${d.solicitante}
🪪 ${d.documento}
📄 Processo: ${d.processo}
🏛️ Devedora: ${d.devedora}
💰 Saldo DEPRE: ${brl(d.saldo)}${d.valorPago ? `\n✅ Já pago: ${brl(d.valorPago)}` : ""}${d.ehMesmoTitular ? "" : "\n\n⚠️ O solicitante é diferente do titular — a cessão só pode ser feita pelo próprio titular ou com procuração."}

Dá uma olhada com calma. Qualquer dúvida, é só responder aqui. 😉`;
}
function msgWhats2(d: ReturnType<typeof buildDadosType>): string {
  return `Oi ${d.primeiroNome}, tudo bem?

Vi que você consultou seu precatório (${d.processo}) ontem. Posso preparar uma análise personalizada do seu caso?

Cada precatório tem características específicas — natureza, posição na fila, condições de superpreferência — que impactam diretamente as opções de antecipação.

Quer que eu avance com a análise? É sem compromisso.`;
}
function msgWhats3(d: ReturnType<typeof buildDadosType>): string {
  return `${d.primeiroNome}, último contato sobre o precatório ${d.processo}.

O mercado de cessão de precatórios está aquecido — fundos de investimento buscando ativos como o seu. Se faz sentido avaliarmos juntos, responde aqui que eu te direciono.

Se preferir não receber mais mensagens, responde *SAIR*. 🙏`;
}
function buildDadosType() {
  return { primeiroNome: "", solicitante: "", titular: "", ehMesmoTitular: false, documento: "", processo: "", qtdProcessos: 1, devedora: "", saldo: 0, valorPago: 0 };
}

function normalizeName(s: string): string {
  return String(s || "")
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .toLowerCase();
}

// ---------- Email ----------
async function sendEmail(to: string, d: ReturnType<typeof buildDados>) {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const fromEmail = Deno.env.get("RESEND_FROM_EMAIL") ?? "noreply@forjuris.com.br";
  if (!apiKey) throw new Error("RESEND_API_KEY ausente");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: `Forjuris <${fromEmail}>`,
      to: [to],
      subject: d.qtdProcessos > 1 ? `${d.primeiroNome}, seu relatório de ${d.qtdProcessos} precatórios` : `${d.primeiroNome}, seu relatório do precatório ${d.processo}`,
      html: emailTemplate(d),
    }),
  });
  if (!res.ok) throw new Error(`Resend ${res.status}: ${await res.text()}`);
}

function emailTemplate(d: ReturnType<typeof buildDados>): string {
  const primary = "#0F3D2E";
  const accent = "#16A34A";
  const muted = "#6B7280";
  return `<!DOCTYPE html>
<html lang="pt-BR"><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#F3F4F6;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#111827">
<div style="max-width:600px;margin:0 auto;background:#ffffff">
  <div style="background:${primary};padding:24px 28px">
    <table cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse">
      <tr>
        <td style="vertical-align:middle;padding-right:12px">
          <div style="width:40px;height:40px;border:2px solid #D4AF37;border-radius:6px;background:#0B1E3F;text-align:center;line-height:36px;font-family:Georgia,'Times New Roman',serif;font-weight:700;font-size:20px;color:#D4AF37;letter-spacing:-1px">FJ</div>
        </td>
        <td style="vertical-align:middle">
          <div style="font-family:Georgia,'Times New Roman',serif;font-size:22px;font-weight:600;letter-spacing:.3px;line-height:1"><span style="color:#ffffff">For</span><span style="color:#D4AF37">juris</span></div>
          <div style="color:#D4AF37;opacity:.85;font-size:11px;margin-top:4px;font-weight:700;letter-spacing:2px;text-transform:uppercase">Créditos Judiciais</div>
        </td>
      </tr>
    </table>
  </div>

  <div style="padding:28px">
    <h1 style="margin:0 0 8px;font-size:22px;line-height:1.3">${escapeHtml(d.primeiroNome)}, aqui está o relatório do seu precatório</h1>
    <p style="margin:0 0 20px;color:${muted};font-size:14px;line-height:1.55">Reunimos abaixo os dados oficiais consultados na base do DEPRE/TJSP. Guarde este email — você vai precisar dessas informações para qualquer análise.</p>

    <div style="border:1px solid #E5E7EB;border-radius:12px;overflow:hidden;margin-bottom:18px">
      <div style="background:#F9FAFB;padding:12px 16px;font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:${muted};font-weight:600">Titular do precatório</div>
      <table cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;font-size:14px">
        ${row("Nome", d.titular)}
        ${row("Documento", d.documento)}
      </table>
    </div>

    <div style="border:1px solid #E5E7EB;border-radius:12px;overflow:hidden;margin-bottom:18px">
      <div style="background:#F9FAFB;padding:12px 16px;font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:${muted};font-weight:600">Solicitante da consulta</div>
      <table cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;font-size:14px">
        ${row("Nome", d.solicitante)}
      </table>
      ${d.ehMesmoTitular ? "" : `<div style="padding:10px 16px;border-top:1px solid #F3F4F6;background:#FFFBEB;font-size:12px;color:#78350F;line-height:1.5">⚠️ O solicitante é diferente do titular registrado no TJSP. A cessão do precatório só pode ser feita pelo próprio titular ou mediante procuração específica.</div>`}
    </div>

    <div style="border:1px solid #E5E7EB;border-radius:12px;overflow:hidden;margin-bottom:18px">
      <div style="background:#F9FAFB;padding:12px 16px;font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:${muted};font-weight:600">Valores</div>
      <table cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;font-size:14px">
        ${row(d.qtdProcessos > 1 ? "Saldo DEPRE total (a receber)" : "Saldo DEPRE (a receber)", `<strong style="color:${accent};font-size:18px">${brl(d.saldo)}</strong>`)}
        ${d.valorPago ? row(d.qtdProcessos > 1 ? "Valor total já pago" : "Valor já pago", brl(d.valorPago)) : ""}
      </table>
    </div>

    ${d.precatorios.map((p, i) => `
    <div style="border:1px solid #E5E7EB;border-radius:12px;overflow:hidden;margin-bottom:18px">
      <div style="background:#F9FAFB;padding:12px 16px;font-size:11px;text-transform:uppercase;letter-spacing:.6px;color:${muted};font-weight:600">
        Precatório ${i + 1}${d.precatorios.length > 1 ? ` de ${d.precatorios.length}` : ""}
      </div>
      <table cellpadding="0" cellspacing="0" style="width:100%;border-collapse:collapse;font-size:14px">
        ${row("Processo DEPRE", String(p.processo_depre), true)}
        ${p._semDados ? row("Status na base", `<span style="color:#92400E">Aguardando dados — pode ser processo ainda não expedido ou já pago.</span>`) : `
          ${p.autos && p.autos !== p.processo_depre ? row("Autos de origem", String(p.autos), true) : ""}
          ${row("Devedora", String(p.devedora || "—"))}
          ${row("Saldo DEPRE", `<strong style="color:${accent}">${brl(Number(p.saldo_depre) || 0)}</strong>`)}
          ${p.valor_pago ? row("Valor já pago", brl(Number(p.valor_pago))) : ""}
          ${row("Natureza", String(p.natureza || "—"))}
          ${row("Status", `${escapeHtml(String(p.status || "—"))}${p.suspenso ? ' <span style="color:#B91C1C">(suspenso)</span>' : ""}`)}
          ${p.ordem_pagamento != null ? row("Ordem de pagamento", String(p.ordem_pagamento)) : ""}
          ${p.num_ordem ? row("Nº de ordem", String(p.num_ordem)) : ""}
          ${p.es_ep ? row("E/EP", String(p.es_ep)) : ""}
          ${p.ordem_orcamentaria ? row("Ordem orçamentária", String(p.ordem_orcamentaria)) : ""}
          ${p.data_protocolo ? row("Data de protocolo", fmtData(String(p.data_protocolo))) : ""}
          ${p.dt_ensejo_ordem ? row("Data de ensejo da ordem", fmtData(String(p.dt_ensejo_ordem))) : ""}
          ${p.condicao_superpreferencia ? row("Superpreferência", String(p.condicao_superpreferencia)) : ""}
          ${p.advogados ? row("Advogados", String(p.advogados)) : ""}
        `}
      </table>
    </div>`).join("")}

    <h2 style="font-size:16px;margin:0 0 8px">O que esse valor significa</h2>
    <p style="margin:0 0 16px;color:#374151;font-size:14px;line-height:1.6">
      O <strong>Saldo DEPRE</strong> é o valor atualizado do seu crédito reconhecido pelo TJSP. Ele aguarda pagamento conforme a fila orçamentária do Estado/Município devedor — historicamente, esse prazo costuma se estender por <strong>vários anos</strong>, com sucessivas atualizações monetárias que nem sempre acompanham seu custo de vida real.
    </p>

    <div style="background:#FEF3C7;border-left:4px solid #F59E0B;border-radius:6px;padding:14px 16px;margin:16px 0;font-size:13px;line-height:1.55;color:#78350F">
      <strong>Dinheiro parado custa.</strong> Cada ano de espera é um ano sem poder usar esse capital para quitar dívidas, investir, comprar um imóvel, abrir um negócio ou simplesmente ter tranquilidade.
    </div>

    <h2 style="font-size:16px;margin:24px 0 8px">Existe outro caminho: antecipação por cessão</h2>
    <p style="margin:0 0 12px;color:#374151;font-size:14px;line-height:1.6">
      A Forjuris é uma <strong>plataforma de intermediação</strong> que conecta titulares de precatórios a <strong>fundos de investimento</strong> autorizados a comprar esses créditos. Na prática:
    </p>
    <ol style="margin:0 0 16px 20px;padding:0;color:#374151;font-size:14px;line-height:1.7">
      <li>Você cede seu crédito ao fundo via escritura pública.</li>
      <li>Recebe o valor combinado <strong>em poucos dias</strong>, direto na sua conta.</li>
      <li>O fundo passa a ser o novo titular e assume a espera da fila.</li>
    </ol>
    <p style="margin:0 0 20px;color:${muted};font-size:13px;line-height:1.55">
      O valor da proposta depende de uma análise específica do seu caso (natureza, posição na fila, condições processuais, devedora). Por isso só conseguimos calcular após uma conversa rápida.
    </p>

    <div style="text-align:center;margin:28px 0">
      <a href="https://wa.me/${waNumber()}?text=${encodeURIComponent(`Olá! Quero uma análise do meu precatório ${d.processo}.`)}"
         style="display:inline-block;background:${accent};color:#fff;text-decoration:none;font-weight:600;padding:14px 28px;border-radius:8px;font-size:15px">
        Quero uma proposta personalizada →
      </a>
      <div style="margin-top:10px;color:${muted};font-size:12px">Resposta em até 1 dia útil. Sem custos, sem compromisso.</div>
    </div>

    <h2 style="font-size:16px;margin:24px 0 8px">Por que decidir agora faz diferença</h2>
    <ul style="margin:0 0 20px 20px;padding:0;color:#374151;font-size:14px;line-height:1.7">
      <li><strong>Cenário macro:</strong> taxa Selic e expectativas de inflação influenciam diretamente o valor que os fundos pagam hoje. Janelas de mercado abrem e fecham.</li>
      <li><strong>Risco da fila:</strong> alterações legislativas, regimes especiais e RPVs podem reordenar prioridades.</li>
      <li><strong>Tempo é dinheiro:</strong> o valor presente do seu crédito é sempre menor quanto mais distante o pagamento.</li>
    </ul>

    <div style="border-top:1px solid #E5E7EB;margin:28px 0 16px"></div>
    <p style="margin:0;color:${muted};font-size:12px;line-height:1.6">
      Forjuris atua exclusivamente como plataforma de intermediação entre titulares e fundos compradores. Não somos escritório de advocacia. Os dados deste relatório foram obtidos junto à base pública do DEPRE/TJSP em ${new Date().toLocaleDateString("pt-BR")}.
    </p>
    <p style="margin:12px 0 0;color:${muted};font-size:12px">
      Se não deseja mais receber comunicações, responda este email com <strong>SAIR</strong>.
    </p>
  </div>
</div>
</body></html>`;
}

function row(label: string, value: string, isMono = false): string {
  return `<tr>
    <td style="padding:10px 16px;border-top:1px solid #F3F4F6;color:#6B7280;width:42%;vertical-align:top">${escapeHtml(label)}</td>
    <td style="padding:10px 16px;border-top:1px solid #F3F4F6;color:#111827;${isMono ? "font-family:ui-monospace,SFMono-Regular,Menlo,monospace;" : ""}">${value}</td>
  </tr>`;
}

function buildDados() {
  return {
    nome: "", primeiroNome: "", solicitante: "", titular: "", ehMesmoTitular: false,
    documento: "",
    processo: "", qtdProcessos: 1,
    devedora: "", saldo: 0, valorPago: 0,
    precatorios: [] as Array<Record<string, any>>,
  };
}

// ---------- WhatsApp via Twilio ----------
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

// ---------- Helpers ----------
function brl(centavos: number): string {
  // saldo_depre vem em REAIS (não centavos) na base. Detectamos pelo magnitude.
  const valor = centavos;
  return new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(valor);
}
function escapeHtml(s: string): string {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}
function waNumber(): string {
  // Número da Forjuris para CTA (placeholder editável via env)
  return (Deno.env.get("FORJURIS_WHATSAPP_CTA") ?? "5511999999999").replace(/\D/g, "");
}
function maskCpf(s: string): string {
  const d = String(s).replace(/\D/g, "").padStart(11, "0").slice(-11);
  return `${d.slice(0,3)}.${d.slice(3,6)}.${d.slice(6,9)}-${d.slice(9,11)}`;
}
function maskCnpj(s: string): string {
  const d = String(s).replace(/\D/g, "").padStart(14, "0").slice(-14);
  return `${d.slice(0,2)}.${d.slice(2,5)}.${d.slice(5,8)}/${d.slice(8,12)}-${d.slice(12,14)}`;
}
function fmtData(s: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(s));
  return m ? `${m[3]}/${m[2]}/${m[1]}` : String(s);
}
function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
