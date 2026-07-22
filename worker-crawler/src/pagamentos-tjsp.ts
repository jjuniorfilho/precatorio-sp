// FOR-102 — Navegação do portal TJSP "Pagamentos Precatórios" (pesquisainternetv2.aspx),
// busca por processo_depre (.0500). App GeneXus (ASP.NET + AJAX próprio, não postback
// clássico) — protocolo mapeado em .claude/sessions/for-102-valor-pago-crawler/plan.md
// a partir de uma captura real de tráfego de navegador (DevTools → Copy as fetch).
import { request } from "undici";
import { randomBytes } from "node:crypto";
import { solveCaptcha } from "./captcha.js";
import { config, sleep } from "./config.js";

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36";
const BASE = "https://www.tjsp.jus.br/cac/scp";

export interface Pagamento {
  data: string | null; // ISO (YYYY-MM-DD) quando possível
  valorCentavos: number;
  tipo: string | null;
}

interface Session {
  cookie: string;
  gxState: Record<string, unknown>;
  pageToken: string; // token assinado, parte da URL de pesquisainternetv2.aspx
  referer: string;
}

function mergeSetCookie(current: string, headers: Record<string, string | string[] | undefined>): string {
  const raw = ([] as string[]).concat(headers["set-cookie"] ?? []);
  if (raw.length === 0) return current;
  const jar = new Map<string, string>();
  for (const part of current.split(";").map((s) => s.trim()).filter(Boolean)) {
    const [k, v] = part.split("=");
    if (k) jar.set(k, v ?? "");
  }
  for (const setCookie of raw) {
    const [pair] = setCookie.split(";");
    const [k, v] = (pair ?? "").split("=");
    if (k) jar.set(k.trim(), (v ?? "").trim());
  }
  return [...jar.entries()].map(([k, v]) => `${k}=${v}`).join("; ");
}

/** Abre a sessão pública (sem login) e captura o token assinado de "Pagamentos Precatórios". */
export async function abrirSessaoPagamentos(): Promise<Session> {
  let cookie = "";
  const res1 = await request(`${BASE}/webmenupesquisa.aspx`, {
    method: "GET",
    headers: { "User-Agent": UA, "Accept-Language": "pt-BR,pt;q=0.9" },
    signal: AbortSignal.timeout(config.requestTimeoutMs),
  });
  cookie = mergeSetCookie(cookie, res1.headers as Record<string, string | string[] | undefined>);
  const menuHtml = await res1.body.text();
  const linkMatch = menuHtml.match(/"LBLPAGAMENTOSV2_Link":"([^"]+)"/);
  if (!linkMatch) throw new Error("token de Pagamentos Precatórios não encontrado em webmenupesquisa.aspx");
  const link = linkMatch[1]!.replace(/\\\//g, "/");
  const pageToken = link.split("?")[1]!;
  const referer = `${BASE}/${link}`;

  const res2 = await request(referer, {
    method: "GET",
    headers: { "User-Agent": UA, "Accept-Language": "pt-BR,pt;q=0.9", Cookie: cookie },
    signal: AbortSignal.timeout(config.requestTimeoutMs),
  });
  cookie = mergeSetCookie(cookie, res2.headers as Record<string, string | string[] | undefined>);
  const formHtml = await res2.body.text();
  const stateMatch = formHtml.match(/name="GXState" value='(\{.*?\})'>/s);
  if (!stateMatch) throw new Error("GXState inicial não encontrado no form de Pagamentos Precatórios");
  const gxState = JSON.parse(stateMatch[1]!) as Record<string, unknown>;

  return { cookie, gxState, pageToken, referer };
}

/** Uma chamada AJAX do GeneXus (POST, corpo x-www-form-urlencoded, GXState embutido). */
async function ajaxCall(
  session: Session,
  eventName: string,
  fields: Record<string, string>,
): Promise<{ bodyText: string; statusCode: number }> {
  const state = { ...session.gxState, _EventName: eventName, _EventGridId: "", _EventRowId: "" };
  const nonce = randomBytes(16).toString("hex");
  const url = `${BASE}/pesquisainternetv2.aspx?${nonce},${session.pageToken},gx-no-cache=${Date.now()}`;
  const body = new URLSearchParams({ ...fields, GXState: JSON.stringify(state) }).toString();

  const res = await request(url, {
    method: "POST",
    headers: {
      "User-Agent": UA,
      "Accept-Language": "pt-BR,pt;q=0.9",
      Accept: "*/*",
      "Content-Type": "application/x-www-form-urlencoded",
      Cookie: session.cookie,
      ajax_security_token: String(session.gxState.AJAX_SECURITY_TOKEN ?? ""),
      gxajaxrequest: "1",
      Referer: session.referer,
      "sec-fetch-dest": "empty",
      "sec-fetch-mode": "cors",
      "sec-fetch-site": "same-origin",
    },
    body,
    signal: AbortSignal.timeout(config.requestTimeoutMs),
  });
  session.cookie = mergeSetCookie(session.cookie, res.headers as Record<string, string | string[] | undefined>);
  const bodyText = await res.body.text();
  // Se a resposta trouxer GXState atualizado, acumula pro próximo call da sequência
  // (padrão observado: cada AJAX response pode devolver o estado revisado do lado servidor).
  const m = bodyText.match(/"GXState"\s*:\s*(\{.*\})\s*\}?\s*$/s) ?? bodyText.match(/^(\{.*\})$/s);
  if (m) {
    try {
      const maybeState = JSON.parse(m[1]!);
      session.gxState = { ...session.gxState, ...maybeState };
    } catch {
      /* resposta não é JSON puro — ver nota no plan.md, ainda em investigação */
    }
  }
  return { bodyText, statusCode: res.statusCode };
}

/**
 * Busca os pagamentos de um processo_depre (.0500). Tenta até `maxTentativas` captchas
 * diferentes (cada um é de graça pra recarregar) antes de desistir.
 *
 * NOTA (FOR-102, ver plan.md): a sequência exata de eventos (`EVENT_ID.ISVALID.` →
 * `ERFR.` → `E'PESQUISAR'.`) foi mapeada a partir de uma captura real de navegador, mas
 * ainda não foi validada rodando este módulo de ponta a ponta — as tentativas via script
 * solto (Python/curl) bateram em "440 Session timeout" por um motivo ainda não isolado
 * (possivelmente serialização exata do GXState, ou detalhe de cookie/sessão). Este é o
 * ponto exato onde continuar a depuração, preferencialmente com logging do `bodyText`
 * de cada `ajaxCall` pra ver a resposta real do servidor.
 */
export async function buscarPagamentos(
  processoDepre: string,
  maxTentativas = 3,
): Promise<Pagamento[]> {
  const session = await abrirSessaoPagamentos();

  const baseFields: Record<string, string> = {
    vTIPOPESQUISA: "1",
    vENT_ID: "",
    vPRP_PROCESSO: processoDepre,
    vOPCAOPESQUISA: "01", // "Processo DEPRE"
    vPRP_NUM_AUTOS: "",
    vPRP_NUM_ORDEM: "",
    vPRP_ANO_ORDEM: "",
    vPRP_NUM_PROTOCOLO: "",
    vPRP_DT_PROTOCOLO: "   /  /     ",
    vNAT_ID: "0",
    vNOME: "",
    vTIPOPARTICIPACAO: "3",
    vISNOMECOMPLETO: "",
    vTIPOCOMBINACAOFONEMA: "C",
    vCRE_CPF_CNPJ: "",
    BUTTON3: "Pesquisar",
    BUTTON1: "Limpar",
    BUTTON4: "Voltar",
  };

  for (let tentativa = 1; tentativa <= maxTentativas; tentativa++) {
    // TODO: baixar a imagem do captcha de verdade (Captcha/images/<n>.jpg) em vez de usar
    // um placeholder — depende de descobrir como o servidor comunica qual <n> foi sorteado
    // (hoje é 100% client-side JS; ver discussão de arquitetura no plan.md).
    const cfield = await solveCaptcha(Buffer.alloc(0)).catch(() => "");
    session.gxState.CAPTCHA1_Validationresult = 1;

    await ajaxCall(session, "EVENT_ID.ISVALID.", { ...baseFields, cfield });
    await ajaxCall(session, "ERFR.", { ...baseFields, cfield });
    const { bodyText, statusCode } = await ajaxCall(session, "E'PESQUISAR'.", { ...baseFields, cfield });

    if (statusCode === 200 && !/session timeout/i.test(bodyText)) {
      return parsePagamentos(bodyText);
    }
    await sleep(config.delayMs);
  }
  throw new Error(`buscarPagamentos: falhou após ${maxTentativas} tentativas (processo=${processoDepre})`);
}

/** Extrai {data, valor, tipo} da tabela "Pagamentos do Processo" no HTML de detalhe. */
function parsePagamentos(html: string): Pagamento[] {
  const pagamentos: Pagamento[] = [];
  // TODO: ajustar o parser assim que tivermos um HTML de resposta real (ver nota acima) —
  // o formato abaixo é uma primeira aproximação baseada no PDF de exemplo (Data | Valor R$ | Tipo).
  const rowRe = /(\d{2}\/\d{2}\/\d{4})\s*<\/td>\s*<td[^>]*>\s*([\d.,]+)\s*<\/td>\s*<td[^>]*>\s*([^<]+)</g;
  let m: RegExpExecArray | null;
  while ((m = rowRe.exec(html))) {
    const [, dataBr, valorStr, tipo] = m;
    const [dd, mm, yyyy] = dataBr!.split("/");
    const valorCentavos = Math.round(parseFloat(valorStr!.replace(/\./g, "").replace(",", ".")) * 100);
    pagamentos.push({ data: `${yyyy}-${mm}-${dd}`, valorCentavos, tipo: tipo!.trim() });
  }
  return pagamentos;
}
