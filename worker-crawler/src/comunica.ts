// Enriquecimento de OAB via DJEN/Comunica. O e-SAJ cpopg traz o nome do advogado
// mas NÃO a OAB; o DJEN traz nome + numero_oab + uf_oab. Busca publicações por número
// de processo (a API aceita `numeroProcesso=<CNJ>`) e mapeia nome→OAB.
// Roda só na VPS (IP aceito pelo PJe); em outros IPs a API responde 403 → mapa vazio.
import { config } from "./config.js";

const API = "https://comunicaapi.pje.jus.br/api/v1/comunicacao";
const HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  Accept: "application/json, text/plain, */*",
  "Accept-Language": "pt-BR,pt;q=0.9",
  Referer: "https://comunica.pje.jus.br/",
  Origin: "https://comunica.pje.jus.br",
};

/** Normaliza nome p/ casamento (sem acento, minúsculo, espaços colapsados). */
export const normNome = (s: string): string =>
  (s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/\s+/g, " ").trim();

export interface OabInfo { oab: string; oab_normalizada: string }
export interface DjenAdvogado { nome: string; oab_numero: string; uf_oab: string; oab: string; oab_normalizada: string }

/** Extrai os advogados estruturados de um item da Comunica (nome+OAB+UF).
 * Descarta OAB malformada (numero_oab às vezes vem como "RN"; exige ao menos um dígito). */
export function advogadosFromItem(item: { destinatarioadvogados?: Array<{ advogado?: { nome?: string; numero_oab?: string; uf_oab?: string } }> }): DjenAdvogado[] {
  const out: DjenAdvogado[] = [];
  for (const da of item?.destinatarioadvogados ?? []) {
    const a = da.advogado ?? {};
    const nome = (a.nome ?? "").trim();
    const numero = (a.numero_oab ?? "").toString().trim();
    const uf = (a.uf_oab ?? "").toString().trim().toUpperCase();
    if (!nome || !/\d/.test(numero)) continue;
    out.push({
      nome, oab_numero: numero, uf_oab: uf,
      oab: uf ? `${numero}/${uf}` : numero,
      oab_normalizada: `${numero}${uf}`.replace(/[^0-9A-Za-z]/g, "").toUpperCase(),
    });
  }
  return out;
}

/** nome(normalizado) → OAB, a partir das publicações DJEN do processo (busca AO VIVO).
 * Usado como fallback quando não há nada estruturado no banco. Best-effort: mapa vazio em erro. */
export async function fetchAdvogadosByCnj(cnj: string | null): Promise<Map<string, OabInfo>> {
  const out = new Map<string, OabInfo>();
  if (!cnj) return out;
  try {
    const url = `${API}?siglaTribunal=TJSP&numeroProcesso=${encodeURIComponent(cnj)}&itensPorPagina=50`;
    const res = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(config.requestTimeoutMs) });
    if (!res.ok) return out;
    const payload = await res.json() as { items?: Array<Parameters<typeof advogadosFromItem>[0]> };
    for (const it of payload.items ?? []) {
      for (const a of advogadosFromItem(it)) out.set(normNome(a.nome), { oab: a.oab, oab_normalizada: a.oab_normalizada });
    }
  } catch { /* best-effort */ }
  return out;
}
