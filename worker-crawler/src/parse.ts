// Extração via cheerio. Seletores conforme a doc:
// docs/business-context/crawler-tjsp-esaj/Documentacao_Crawler_TJSP_eSAJ.md
// NOTA: validar seletores contra páginas reais do e-SAJ ao subir o worker —
// alguns rótulos/classes podem variar. Parsing é defensivo (optional chaining).
import * as cheerio from "cheerio";
import type {
  Advogado, Andamento, Esfera, ParteAtiva, PartePassiva, StatusBruto,
} from "./types.js";

type $ = cheerio.CheerioAPI;
export const load = (html: string): $ => cheerio.load(html);

// ---- helpers ----------------------------------------------------------------
const onlyDigits = (s: string | undefined | null) => (s ?? "").replace(/\D/g, "");

/** "R$ 2.817,12" → 281712 (centavos). null se não achar. */
export function parseMoneyToCents(text: string | undefined | null): number | null {
  if (!text) return null;
  const m = text.match(/R\$\s*([\d.]+,\d{2})/);
  if (!m) return null;
  const cents = m[1]!.replace(/\./g, "").replace(",", "");
  const n = Number(cents);
  return Number.isFinite(n) ? n : null;
}

/** "dd/mm/aaaa" → "aaaa-mm-dd". */
export function parseDateIso(text: string | undefined | null): string | null {
  const m = (text ?? "").match(/(\d{2})\/(\d{2})\/(\d{4})/);
  return m ? `${m[3]}-${m[2]}-${m[1]}` : null;
}

const DEPRE_RE = /\d{7}-\d{2}\.\d{4}\.8\.26\.0500/;
export const extractDepre = (text: string): string | null => text.match(DEPRE_RE)?.[0] ?? null;

/** href do e-SAJ → { codigo, foro }. */
export function codigoForoFromHref(href: string | undefined): { codigo: string; foro: string } | null {
  if (!href) return null;
  const codigo = href.match(/processo\.codigo=([^&]+)/)?.[1];
  const foro = href.match(/processo\.foro=([^&]+)/)?.[1] ?? href.match(/localPesquisa\.cdLocal=([^&]+)/)?.[1];
  return codigo ? { codigo: decodeURIComponent(codigo), foro: decodeURIComponent(foro ?? "") } : null;
}

export function classifyEsfera(nome: string | null): Esfera {
  const n = (nome ?? "").toUpperCase();
  if (/\b(ESTADO|FAZENDA\s+(P[ÚU]BLICA\s+)?DO\s+ESTADO|FAZENDA\s+ESTADUAL|GOVERNO\s+DO\s+ESTADO|UFESP|IPESP|DER|SPPREV|CBPM)\b/.test(n))
    return "Estadual";
  if (/\b(MUNIC[ÍI]PIO|PREFEITURA|FAZENDA\s+(P[ÚU]BLICA\s+)?MUNICIPAL|C[ÂA]MARA\s+MUNICIPAL)\b/.test(n))
    return "Municipal";
  return "Outro";
}

// ---- navegação --------------------------------------------------------------
/** Link "Processo principal" (a.processoPrinc) → sobe um nível. null = raiz. */
export function processoPrincLink($: $): { codigo: string; foro: string } | null {
  const href = $("a.processoPrinc").first().attr("href");
  return codigoForoFromHref(href);
}

/** 1º link de processo numa página de listagem (a.incidente cobre incidentes;
 * aqui pegamos qualquer link de ficha — fallback quando a busca não redireciona
 * direto ao detalhe e cai numa lista de resultados). */
export function firstProcessoLink($: $): { codigo: string; foro: string } | null {
  const href = $("a[href*='show.do'][href*='processo.codigo']").first().attr("href");
  return codigoForoFromHref(href);
}

/** Links de incidentes/cumprimentos (a.incidente) com texto da classe. */
export function incidenteLinks($: $): Array<{ codigo: string; foro: string; texto: string }> {
  const out: Array<{ codigo: string; foro: string; texto: string }> = [];
  $("a.incidente").each((_, el) => {
    const cf = codigoForoFromHref($(el).attr("href"));
    if (cf) out.push({ ...cf, texto: $(el).text().trim() });
  });
  return out;
}

export function tipoFromTexto(texto: string): "Precatorio" | "RPV" | "Indefinido" {
  const t = texto.toLowerCase();
  if (t.includes("pequeno valor") || /\brpv\b/.test(t)) return "RPV";
  if (t.includes("precat")) return "Precatorio";
  return "Indefinido";
}

// ---- extração de página -----------------------------------------------------
export interface CapaInfo {
  cnj: string | null;
  classe: string | null;
  assunto: string | null;
  foro: string | null;
  distribuicao: string | null;
  valor_acao: number | null;
  data_base: string | null;
  status: StatusBruto | null;
  tramitacao_prioritaria: boolean;
}

export function extractCapa($: $): CapaInfo {
  const body = $("body").text();
  const label = (re: RegExp) => body.match(re)?.[1]?.trim() ?? null;

  const statusTxt = ($("#labelSituacaoProcesso, #labelStatusProcesso, .unj-tag, .classeStatus").first().text() || "").toLowerCase();
  let status: StatusBruto | null = null;
  if (statusTxt.includes("suspen")) status = "suspenso";
  else if (statusTxt.includes("extint")) status = "extinto";
  else if (statusTxt.includes("arquiv")) status = "arquivado";
  else if (statusTxt) status = "ativo";

  return {
    cnj: $("#numeroProcesso").text().trim().match(/\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}/)?.[0] ?? null,
    classe: $("#classeProcesso").text().trim() || label(/Classe[^A-Za-z0-9]{0,5}([^\n<]{3,120})/),
    assunto: $("#assuntoProcesso").text().trim() || label(/Assunto[^A-Za-z0-9]{0,5}([^\n<]{3,120})/),
    foro: $("#foroProcesso").text().trim() || label(/Foro[^A-Za-z0-9]{0,5}([^\n<]{3,80})/),
    distribuicao: parseDateIso($("#dataHoraDistribuicaoProcesso").text() || label(/Distribui[çc][ãa]o[^0-9]{0,10}(\d{2}\/\d{2}\/\d{4})/) || ""),
    valor_acao: parseMoneyToCents($("#valorAcaoProcesso").text() || label(/Valor da a[çc][ãa]o[^R]{0,10}(R\$\s*[\d.,]+)/) || ""),
    data_base: parseDateIso(label(/data[\- ]base[^0-9]{0,10}(\d{2}\/\d{2}\/\d{4})/i) || ""),
    status,
    tramitacao_prioritaria: /tramita[çc][ãa]o\s+priorit/i.test(body),
  };
}

export function extractPartes($: $): { ativa: ParteAtiva | null; passiva: PartePassiva | null } {
  let ativa: ParteAtiva | null = null;
  let passiva: PartePassiva | null = null;

  $("#tablePartesPrincipais tr").each((_, tr) => {
    const tipo = $(tr).find("td.label, span.mensagemExibindo").first().text().trim().toLowerCase();
    const valueCell = $(tr).find("td").last();
    const nome = valueCell.clone().children().remove().end().text().trim().split("\n")[0]?.trim() ?? null;

    const isAtiva = /reqte|exequente|requerente|autor|credor/.test(tipo);
    const isPassiva = /reqd[oa]|requerid|ent\.?\s*devedora|executad|fazenda|munic|devedor/.test(tipo);

    if (isAtiva) {
      // O nome do advogado é um text node solto após <span>Advogad[oa]:</span>,
      // não está dentro do span — por isso extraímos do texto completo da célula.
      const advs: Advogado[] = [];
      const cellText = valueCell.text().replace(/ /g, " ");
      for (const m of cellText.matchAll(/Advogad[oa]:\s*([\s\S]*?)(?=Advogad[oa]:|$)/gi)) {
        const seg = m[1]!.replace(/\s+/g, " ").trim();
        if (!seg) continue;
        const oab = seg.match(/OAB[:\s]*([\dA-Z\/.\- ]+)/i)?.[1]?.trim() ?? null;
        const nomeAdv = seg.replace(/\s*OAB.*$/i, "").replace(/\(.*$/, "").trim();
        if (!nomeAdv) continue;
        advs.push({
          nome: nomeAdv,
          oab,
          oab_normalizada: oab ? oab.replace(/[^0-9A-Za-z]/g, "").toUpperCase() : null,
          sem_oab: !oab,
        });
      }
      ativa = { nome, documento: null, advogados: advs };
    } else if (isPassiva && !passiva) {
      passiva = { nome, ente_esfera: classifyEsfera(nome) };
    }
  });

  return { ativa, passiva };
}

export function extractAndamentos($: $): Andamento[] {
  const out: Andamento[] = [];
  $("#tabelaTodasMovimentacoes tr").each((_, tr) => {
    const data = parseDateIso($(tr).find("td.dataMovimentacao").text());
    const descCell = $(tr).children("td").last();
    const descricao = descCell.text().replace(/\s+/g, " ").trim();
    if (!descricao) return;
    const arquivo = $(tr).find("a.linkMovVincProc").attr("href") ?? null;
    out.push({ data, descricao, arquivo_url: arquivo });
  });
  return out;
}
