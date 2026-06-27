// Orquestra a coleta de UM job: normaliza à raiz e monta a ProcessoTree.
// e-SAJ é GET sem captcha; #tabelaTodasMovimentacoes já vem no HTML.
import {
  getSession, searchByCnj, showByCodigo, isCnj, parseCnj, type Session,
} from "./esaj.js";
import {
  load, extractCapa, extractPartes, extractAndamentos, extractDepre,
  incidenteLinks, processoPrincLink, tipoFromTexto,
} from "./parse.js";
import type { CumprimentoData, IncidenteData, ProcessoTree } from "./types.js";
import { config, sleep } from "./config.js";

const isCumprimento = (texto: string) => /cumprimento|execu[çc][ãa]o de senten/i.test(texto);

/** lê o código interno da própria página (hidden comum no e-SAJ). */
function selfCodigo($: ReturnType<typeof load>): { codigo: string; foro: string } | null {
  const codigo = ($("#processoSelecionado").attr("value") || $("input[name='processo.codigo']").attr("value") || "").trim();
  const foro = ($("input[name='processo.foro']").attr("value") || "").trim();
  return codigo ? { codigo, foro } : null;
}

/** Sobe via a.processoPrinc até a raiz; retorna {html,$,codigo,foro} da raiz. */
async function normalizeToRoot(seed: string, session: Session) {
  let html: string;
  let foroHint = isCnj(seed) ? parseCnj(seed)?.foro ?? "" : "";
  html = isCnj(seed) ? await searchByCnj(seed, session) : await showByCodigo(seed, foroHint, session);

  let $ = load(html);
  let current = selfCodigo($) ?? { codigo: seed, foro: foroHint };

  // climb
  for (let i = 0; i < 20; i++) {
    const link = processoPrincLink($);
    if (!link) break;
    await sleep(config.delayMs);
    html = await showByCodigo(link.codigo, link.foro || foroHint, session);
    $ = load(html);
    current = { codigo: link.codigo, foro: link.foro || foroHint };
  }
  return { html, $, codigo: current.codigo, foro: current.foro || foroHint };
}

async function buildIncidente(
  codigo: string, foro: string, texto: string, session: Session,
): Promise<IncidenteData> {
  await sleep(config.delayMs);
  const $ = load(await showByCodigo(codigo, foro, session));
  const capa = extractCapa($);
  const { ativa, passiva } = extractPartes($);
  const andamentos = extractAndamentos($);
  return {
    processo_codigo: codigo,
    numero_incidente: texto.match(/(\d{5})/)?.[1] ?? null,
    tipo_previsto: tipoFromTexto(texto),
    numero_depre: extractDepre($("body").text()),
    cnj: capa.cnj,
    status: capa.status,
    tramitacao_prioritaria: capa.tramitacao_prioritaria,
    valor_acao: capa.valor_acao,
    data_base: capa.data_base,
    parte_ativa: ativa,
    parte_passiva: passiva,
    andamentos,
  };
}

/** Coleta a árvore inteira a partir de um seed (CNJ recomendado). */
export async function crawlSeed(seed: string, session?: Session): Promise<ProcessoTree> {
  const sess = session ?? (await getSession());
  const root = await normalizeToRoot(seed, sess);
  const capa = extractCapa(root.$);

  // No nível raiz, os a.incidente costumam ser os Cumprimentos de Sentença.
  const rootLinks = incidenteLinks(root.$);
  const cumprimentos: CumprimentoData[] = [];

  const cumpLinks = rootLinks.filter((l) => isCumprimento(l.texto));
  const directIncidentLinks = rootLinks.filter((l) => !isCumprimento(l.texto));

  // cumprimentos "de verdade"
  for (const c of cumpLinks) {
    await sleep(config.delayMs);
    const $c = load(await showByCodigo(c.codigo, c.foro || root.foro, sess));
    const leafLinks = incidenteLinks($c).filter((l) => !isCumprimento(l.texto));
    const incidentes: IncidenteData[] = [];
    for (const l of leafLinks) incidentes.push(await buildIncidente(l.codigo, l.foro || root.foro, l.texto, sess));
    // Opção A: cumprimento sem incidente → placeholder Indefinido com os andamentos do cumprimento
    if (incidentes.length === 0) {
      incidentes.push({
        processo_codigo: `${c.codigo}#placeholder`,
        numero_incidente: null,
        tipo_previsto: "Indefinido",
        numero_depre: extractDepre($c("body").text()),
        cnj: extractCapa($c).cnj,
        status: extractCapa($c).status,
        tramitacao_prioritaria: extractCapa($c).tramitacao_prioritaria,
        valor_acao: extractCapa($c).valor_acao,
        data_base: extractCapa($c).data_base,
        parte_ativa: extractPartes($c).ativa,
        parte_passiva: extractPartes($c).passiva,
        andamentos: extractAndamentos($c),
      });
    }
    cumprimentos.push({ processo_codigo: c.codigo, cnj: null, incidentes });
  }

  // incidentes pendurados direto na raiz (sem cumprimento) → cumprimento sintético
  if (directIncidentLinks.length > 0) {
    const incidentes: IncidenteData[] = [];
    for (const l of directIncidentLinks) incidentes.push(await buildIncidente(l.codigo, l.foro || root.foro, l.texto, sess));
    cumprimentos.push({ processo_codigo: `${root.codigo}#cumprimento`, cnj: null, incidentes });
  }

  // raiz sem nada → placeholder no nível raiz (só cálculo homologado, p.ex.)
  if (cumprimentos.length === 0) {
    cumprimentos.push({
      processo_codigo: `${root.codigo}#cumprimento`,
      cnj: null,
      incidentes: [{
        processo_codigo: `${root.codigo}#placeholder`,
        numero_incidente: null, tipo_previsto: "Indefinido",
        numero_depre: extractDepre(root.$("body").text()),
        cnj: capa.cnj, status: capa.status, tramitacao_prioritaria: capa.tramitacao_prioritaria,
        valor_acao: capa.valor_acao, data_base: capa.data_base,
        parte_ativa: extractPartes(root.$).ativa, parte_passiva: extractPartes(root.$).passiva,
        andamentos: extractAndamentos(root.$),
      }],
    });
  }

  return {
    processo_codigo: root.codigo,
    cnj: capa.cnj,
    foro: capa.foro ?? root.foro,
    classe: capa.classe,
    assunto: capa.assunto,
    distribuicao: capa.distribuicao,
    valor_acao: capa.valor_acao,
    data_base: capa.data_base,
    status: capa.status,
    cumprimentos,
  };
}
