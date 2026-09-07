// Acesso HTTP ao e-SAJ cpopg (deslogado). GET + retry/backoff/timeout.
// Padrão de sessão/CSRF espelha a edge function `search-by-document`.
import { request } from "undici";
import { config, sleep } from "./config.js";

const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

export interface Session {
  csrf: string | null;
  cookie: string;
}

function baseHeaders(session?: Session, referer?: string): Record<string, string> {
  return {
    "User-Agent": UA,
    "Accept-Language": "pt-BR,pt;q=0.9",
    Referer: referer ?? `${config.esajBase}/open.do?servico=190101`,
    ...(session?.cookie ? { Cookie: session.cookie } : {}),
  };
}

/** GET com timeout + backoff (429/5xx/timeout). Retorna o HTML (texto). */
export async function fetchHtml(url: string, session?: Session, referer?: string): Promise<string> {
  let lastErr: unknown;
  for (let attempt = 0; attempt <= config.maxHttpRetry; attempt++) {
    try {
      const res = await request(url, {
        method: "GET",
        headers: baseHeaders(session, referer),
        signal: AbortSignal.timeout(config.requestTimeoutMs),
        maxRedirections: 5,
      });
      if (res.statusCode === 429 || res.statusCode >= 500) {
        throw new Error(`HTTP ${res.statusCode}`);
      }
      return await res.body.text();
    } catch (err) {
      lastErr = err;
      if (attempt < config.maxHttpRetry) {
        await sleep(config.delayMs * Math.pow(2, attempt) + 250); // backoff exponencial
      }
    }
  }
  throw new Error(`fetchHtml falhou após retries: ${url} :: ${String(lastErr)}`);
}

/** Abre o formulário de consulta e captura _csrf + JSESSIONID. */
export async function getSession(): Promise<Session> {
  const res = await request(`${config.esajBase}/open.do?servico=190101`, {
    method: "GET",
    headers: baseHeaders(),
    signal: AbortSignal.timeout(config.requestTimeoutMs),
  });
  const html = await res.body.text();
  const csrf = html.match(/name="_csrf"[^>]+value="([^"]+)"/)?.[1] ?? null;
  const setCookie = ([] as string[]).concat(res.headers["set-cookie"] ?? []).join("; ");
  const jsession = setCookie.match(/JSESSIONID=([^;]+)/)?.[1];
  return { csrf, cookie: jsession ? `JSESSIONID=${jsession}` : "" };
}

/** CNJ "NNNNNNN-DD.AAAA.8.26.FFFF" → partes para o form de busca. */
export function parseCnj(cnj: string): { digitoAno: string; foro: string; full: string } | null {
  const m = cnj.match(/^(\d{7}-\d{2}\.\d{4})\.\d\.\d{2}\.(\d{4})$/);
  if (!m) return null;
  return { digitoAno: m[1]!, foro: m[2]!, full: cnj };
}

export const isCnj = (s: string) => /^\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}$/.test(s);

/** DEPRE/requisitório (.0500): vive na Consulta de Requisitórios, não no cpopg comum. */
export const isDepre = (cnj: string): boolean => /\.8\.26\.0500$/.test(cnj);

const REQ_FORM = (base: string) => `${base}/abrirConsultaDeRequisitorios.do`;

/** Busca por número unificado (NUMPROC). Retorna o HTML da página de detalhe/lista. */
export async function searchByCnj(cnj: string, session: Session): Promise<string> {
  const p = parseCnj(cnj);
  if (!p) throw new Error(`CNJ inválido: ${cnj}`);
  const params = new URLSearchParams({
    cbPesquisa: "NUMPROC",
    numeroDigitoAnoUnificado: p.digitoAno,
    foroNumeroUnificado: p.foro,
    "dadosConsulta.valorConsultaNuUnificado": p.full,
    "dadosConsulta.tipoNuProcesso": "UNIFICADO",
    ...(session.csrf ? { _csrf: session.csrf } : {}),
  });
  return fetchHtml(`${config.esajBase}/search.do?${params}`, session);
}

/** Página de detalhe por código interno + foro. */
export async function showByCodigo(processoCodigo: string, foro: string, session: Session, referer?: string): Promise<string> {
  const params = new URLSearchParams({
    "processo.codigo": processoCodigo,
    "processo.foro": foro,
    "localPesquisa.cdLocal": foro,
  });
  return fetchHtml(`${config.esajBase}/show.do?${params}`, session, referer);
}

// ---- Consulta de Requisitórios (.0500) --------------------------------------
// A ficha de um requisitório é a MESMA `show.do` de um processo normal (foro=0500),
// só que descoberta por um fluxo de busca próprio (consultaDeRequisitorios=true) e
// sem "Processo principal" (o .0500 já é a raiz). Espelha a edge `buscar-precatorio`.

/** Sessão da Consulta de Requisitórios: abre o form próprio e captura csrf+JSESSIONID. */
export async function getRequisitorioSession(): Promise<Session> {
  const res = await request(REQ_FORM(config.esajBase), {
    method: "GET",
    headers: baseHeaders(undefined, REQ_FORM(config.esajBase)),
    signal: AbortSignal.timeout(config.requestTimeoutMs),
  });
  const html = await res.body.text();
  const csrf = html.match(/name="_csrf"[^>]+value="([^"]+)"/)?.[1] ?? null;
  const setCookie = ([] as string[]).concat(res.headers["set-cookie"] ?? []).join("; ");
  const jsession = setCookie.match(/JSESSIONID=([^;]+)/)?.[1];
  return { csrf, cookie: jsession ? `JSESSIONID=${jsession}` : "" };
}

/** Referer p/ as chamadas autenticadas na consulta de requisitórios. */
export const reqReferer = (): string => REQ_FORM(config.esajBase);

/** Busca um requisitório (.0500) por número unificado. Retorna HTML (ficha ou lista). */
export async function searchRequisitorioByCnj(cnj: string, session: Session): Promise<string> {
  const p = parseCnj(cnj);
  if (!p) throw new Error(`CNJ inválido: ${cnj}`);
  const params = new URLSearchParams({
    conversationId: "",
    cbPesquisa: "NUMPROC",
    numeroDigitoAnoUnificado: p.digitoAno,
    foroNumeroUnificado: p.foro,
    "dadosConsulta.valorConsultaNuUnificado": p.full,
    "dadosConsulta.valorConsulta": "",
    "dadosConsulta.tipoNuProcesso": "UNIFICADO",
    consultaDeRequisitorios: "true",
    ...(session.csrf ? { _csrf: session.csrf } : {}),
  });
  return fetchHtml(`${config.esajBase}/search.do?${params}`, session, REQ_FORM(config.esajBase));
}
