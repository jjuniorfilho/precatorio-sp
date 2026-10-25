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

const CNJ_RE = /\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}/;
/** Extrai um CNJ de um texto livre (ex.: texto do link do cumprimento). */
export const extractCnj = (text: string | null | undefined): string | null => (text ?? "").match(CNJ_RE)?.[0] ?? null;

export interface OrigemInfo { cnj: string; numeroIncidente: string | null }

/** CNJs de origem citados na ficha de um requisitório (.0500), com o número do incidente
 * de origem quando presente: "Processo de Origem: 0410665-90.1996.8.26.0053/0001" (o
 * sufixo "/NNNN" identifica QUAL incidente da ação de origem gerou esse .0500 — achado
 * real: processos de execução coletiva antiga têm vários "Precatório - 0000X" na mesma
 * ação, e sem esse sufixo não dá pra saber qual dos vários corresponde a este .0500;
 * extractDepre() nunca encontra o .0500 de volta na página do incidente de origem porque
 * o requisitório simplesmente não é citado lá). "Outros números" da capa não trazem esse
 * sufixo. Exclui o próprio .0500 e dedup por CNJ, preferindo a ocorrência com sufixo. */
export function extractOrigemInfo($: $): OrigemInfo[] {
  const text = $("body").text();
  const porCnj = new Map<string, string | null>();
  for (const m of text.matchAll(/(\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4})(?:\/(\d+))?/g)) {
    const cnj = m[1]!;
    if (/\.8\.26\.0500$/.test(cnj)) continue;
    const numeroIncidente = m[2] ?? null;
    if (numeroIncidente || !porCnj.has(cnj)) porCnj.set(cnj, numeroIncidente ?? porCnj.get(cnj) ?? null);
  }
  return [...porCnj.entries()].map(([cnj, numeroIncidente]) => ({ cnj, numeroIncidente }));
}

/** Só os CNJs de origem, sem o sufixo do incidente — usado pra enfileirar (não importa
 * qual incidente específico pra esse fim). */
export function extractOrigemCnjs($: $): string[] {
  return extractOrigemInfo($).map((o) => o.cnj);
}

/** href do e-SAJ → { codigo, foro }. */
export function codigoForoFromHref(href: string | undefined): { codigo: string; foro: string } | null {
  if (!href) return null;
  const codigo = href.match(/processo\.codigo=([^&]+)/)?.[1];
  const foro = href.match(/processo\.foro=([^&]+)/)?.[1] ?? href.match(/localPesquisa\.cdLocal=([^&]+)/)?.[1];
  return codigo ? { codigo: decodeURIComponent(codigo), foro: decodeURIComponent(foro ?? "") } : null;
}

// FOR-143 — lista de acrônimos/autarquias estendida a partir dos devedores encontrados no
// dump legado (precatorio_sp_202608161955.csv); universidades, hospitais universitários e
// autarquias estaduais/municipais que não continham "ESTADO"/"MUNICÍPIO" por extenso.
export function classifyEsfera(nome: string | null): Esfera {
  const n = (nome ?? "").toUpperCase();
  if (/\b(ESTADO|ESTADUAL|FAZENDA\s+(P[ÚU]BLICA\s+)?DO\s+ESTADO|FAZENDA\s+ESTADUAL|GOVERNO\s+DO\s+ESTADO|UFESP|IPESP|DER|SPPREV|CBPM|USP|UNESP|UNICAMP|IAMSPE|DETRAN|ARTESP|CEETEPS|FDE|FURP|SUCEN|ITESP|JUCESP|DAEE|DERSA|PROCON|FUNDA[ÇC][ÃA]O\s+CASA|HOSPITAL\s+DAS\s+CL[ÍI]NICAS|FAMEMA|HCFAMEMA)\b/.test(n))
    return "Estadual";
  if (
    /\b(MUNIC[ÍI]PIO|MUNICIPAL|PREFEITURA|FAZENDA\s+(P[ÚU]BLICA\s+)?MUNICIPAL|C[ÂA]MARA\s+MUNICIPAL|SPTRANS|SP-URBANISMO|S[ÃA]O\s+PAULO\s+URBANISMO)\b/.test(n)
    || /\bMUN\.\s*DE\b/.test(n) // abreviação "MUN. DE <cidade>" (ex.: institutos de previdência municipal fora da capital)
  )
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

export function extractPartes($: $): { ativas: ParteAtiva[]; passiva: PartePassiva | null } {
  const ativas: ParteAtiva[] = [];
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
      // Credores conjuntos (comum em ação coletiva) viram várias linhas "Reqte/Exequente"
      // na mesma tabela — acumula, não sobrescreve (bug real: reatribuir aqui perdia todo
      // credor/advogado exceto o da última linha a cada re-crawl).
      ativas.push({ nome, documento: null, advogados: advs });
    } else if (isPassiva && !passiva) {
      passiva = { nome, ente_esfera: classifyEsfera(nome) };
    }
  });

  return { ativas, passiva };
}

/**
 * Regra de "acordo homologado" de um requisitório .0500: existe andamento da própria ficha
 * (decisão publicável / remetido ao DJE) cujo teor contém a frase de homologação do juiz
 * — "Homologo o acordo" (ou "os acordos"). Prova a decisão, ao contrário do antigo
 * "Comunicado de Acordo de Requisitório", que é só uma petição informando que há acordo.
 *
 * Fica de fora de propósito: "Não homologo…" (lookbehind), "Deixo de homologar…" (a frase
 * não bate) e "acordo de compensação" (abatimento de dívida, outro instituto). Mantenha em
 * sincronia com ACORDO_HOMOLOGADO_REGEX_PG em sql/2026-10-22_for_acordo_homologado_zera_e_reclassifica.sql
 * (Postgres ARE suporta os mesmos lookahead/lookbehind). Só decide `true`: a ausência da
 * frase prova "não achei", e só vira `false` quando a ficha foi lida por inteiro.
 */
const ACORDO_HOMOLOGADO_RE = /(?<!n[ãa]o\s)homologo\s+os?\s+acordos?\b(?!\s+de\s+compensa)/i;

export function temAcordoHomologado(andamentos: Andamento[]): boolean {
  return andamentos.some((a) => ACORDO_HOMOLOGADO_RE.test(a.descricao));
}

/** Valor de `djen_depre.acordo_homologado` (tri-state): `true` com prova; `false` só se a Movimentação
 * foi lida por inteiro e a frase não apareceu; `null` (não verificado) quando a leitura não é confiável. */
export function classificarAcordoHomologado(andamentos: Andamento[], leituraCompleta: boolean): boolean | null {
  if (temAcordoHomologado(andamentos)) return true;
  return leituraCompleta ? false : null;
}

/** Linha de movimentação (data + descrição) — mesma marcação nos 3 layouts do e-SAJ. */
function andamentoDaLinha($tr: ReturnType<$>): Andamento | null {
  const data = parseDateIso($tr.find("td.dataMovimentacao").text());
  // <br> separa título e teor; sem trocá-lo por espaço, .text() cola "Publicável"+"Vistos".
  const cell = $tr.children("td").last().clone();
  cell.find("br").replaceWith(" ");
  const descricao = cell.text().replace(/\s+/g, " ").trim();
  if (!descricao) return null;
  const arquivo = $tr.find("a.linkMovVincProc").attr("href") ?? null;
  return { data, descricao, arquivo_url: arquivo };
}

/** Movimentações presentes NO HTML da ficha. O e-SAJ já serviu essas linhas de dois jeitos:
 * tabela única `#tabelaTodasMovimentacoes` (layout antigo, completa) e, no layout atual da
 * Consulta de Requisitórios, `#tabelaPrimeiraPaginaMovimentacoes` + `#tabelaOutrasPaginasMovimentacoes`
 * (paginação keyset — as páginas seguintes só vêm via `carregarMovimentacoesAjax.do`, ver
 * extractMovimentacoesAjax). Só linhas com `td.dataMovimentacao` (a linha oculta de cursor não conta). */
export function extractAndamentos($: $): Andamento[] {
  const out: Andamento[] = [];
  $("#tabelaTodasMovimentacoes tr, #tabelaPrimeiraPaginaMovimentacoes tr, #tabelaOutrasPaginasMovimentacoes tr").each((_, tr) => {
    if (!$(tr).find("td.dataMovimentacao").length) return;
    const a = andamentoDaLinha($(tr));
    if (a) out.push(a);
  });
  return out;
}

/** A ficha do .0500 carrega as movimentações sob demanda: o HTML inicial traz só o botão
 * "Exibir movimentações" (`#btnExibirMovimentacoes`) e o JS da página chama
 * `carregarMovimentacoesAjax.do?processo.codigo=…` (1ª página) e depois `…&cursor=…` (demais).
 * Retorna true quando é preciso buscar via AJAX. */
export function movimentacoesViaAjax($: $): boolean {
  return $("#btnExibirMovimentacoes").length > 0 || $("#cursorMovimentacoesPaginado").length > 0;
}

/** Interpreta a resposta de `carregarMovimentacoesAjax.do`: a 1ª página vem como bloco completo
 * (tabela + input oculto `#cursorMovimentacoesPaginado`); as seguintes como `<tr>` soltas com uma
 * linha oculta `#trCursorMovimentacoes[data-cursor]` quando ainda há mais. As `<tr>` soltas são
 * embrulhadas em <table><tbody> (como o JS da página faz) — senão o parser HTML as descarta. */
export function extractMovimentacoesAjax(html: string): { andamentos: Andamento[]; cursor: string | null } {
  const $ = load(/<table[\s>]/i.test(html) ? html : `<table><tbody>${html}</tbody></table>`);
  // O e-SAJ responde 200 com esta div quando recusa a chamada (sessão/referer/CSRF); tratar como
  // "zero movimentações" gravaria a ficha vazia como se estivesse completa — o bug original.
  if ($(".mensagemErroMovimentacoes").length) {
    throw new Error(`carregarMovimentacoesAjax: e-SAJ recusou — ${$(".mensagemErroMovimentacoes").text().replace(/\s+/g, " ").trim()}`);
  }
  const andamentos: Andamento[] = [];
  $("tr").each((_, tr) => {
    if (!$(tr).find("td.dataMovimentacao").length) return;
    const a = andamentoDaLinha($(tr));
    if (a) andamentos.push(a);
  });
  const cursor = ($("#trCursorMovimentacoes").attr("data-cursor") || $("#cursorMovimentacoesPaginado").attr("value") || "").trim();
  return { andamentos, cursor: cursor || null };
}

/** Tabela "Petições diversas" da ficha do .0500 (sem id; achada pelo <h2> que a antecede).
 * Ex.: "Comunicado de Acordo de Requisitório". Fica fora da Movimentação. */
export function extractPeticoesDiversas($: $): Andamento[] {
  const out: Andamento[] = [];
  const heading = $("h2.tituloDoBloco")
    .filter((_, h) => $(h).text().trim() === "Petições diversas")
    .first();
  if (!heading.length) return out;
  const table = heading.closest("div").nextAll("table").first();
  table.find("tbody tr").each((_, tr) => {
    const tds = $(tr).find("td");
    if (tds.length < 2) return;
    const data = parseDateIso($(tds[0]).text());
    const descricao = $(tds[1]).text().replace(/\s+/g, " ").trim();
    if (!descricao) return;
    out.push({ data, descricao, arquivo_url: null });
  });
  return out;
}
