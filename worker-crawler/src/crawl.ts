// Orquestra a coleta de UM job: normaliza à raiz e monta a ProcessoTree.
// e-SAJ é GET sem captcha; #tabelaTodasMovimentacoes já vem no HTML.
import {
  getSession, searchByCnj, showByCodigo, isCnj, parseCnj, type Session,
  getRequisitorioSession, searchRequisitorioByCnj, reqReferer,
} from "./esaj.js";
import {
  load, extractCapa, extractPartes, extractAndamentos, extractDepre, extractCnj,
  incidenteLinks, processoPrincLink, firstProcessoLink, tipoFromTexto, extractOrigemInfo,
  type OrigemInfo,
} from "./parse.js";
import { fetchAdvogadosByCnj, normNome } from "./comunica.js";
import { djenAdvogadosByCnj } from "./supabase.js";
import type { CumprimentoData, IncidenteData, ProcessoPrincipalInfo, ProcessoTree } from "./types.js";
import { config, sleep } from "./config.js";

const isCumprimento = (texto: string) => /cumprimento|execu[çc][ãa]o de senten/i.test(texto);

/** lê o código interno da própria página. O e-SAJ atual não traz hidden inputs;
 * o código/foro internos vêm em `saj.env.queryString` (validado em HTML real). */
function selfCodigo($: ReturnType<typeof load>): { codigo: string; foro: string } | null {
  const qs = $.html().match(/saj\.env\.queryString\s*=\s*'([^']+)'/)?.[1] ?? "";
  const codigo = (qs.match(/processo\.codigo=([^&]+)/)?.[1]
    || $("#processoSelecionado").attr("value") || $("input[name='processo.codigo']").attr("value") || "").trim();
  const foro = (qs.match(/processo\.foro=([^&]+)/)?.[1]
    || $("input[name='processo.foro']").attr("value") || "").trim();
  return codigo ? { codigo, foro } : null;
}

/** Sobe via a.processoPrinc até a raiz; retorna {html,$,codigo,foro} da raiz. */
async function normalizeToRoot(seed: string, session: Session) {
  let html: string;
  let foroHint = isCnj(seed) ? parseCnj(seed)?.foro ?? "" : "";
  html = isCnj(seed) ? await searchByCnj(seed, session) : await showByCodigo(seed, foroHint, session);

  let $ = load(html);
  // Blindagem: se a busca não redirecionou ao detalhe (sem queryString → não é
  // ficha; pode ser lista de resultados/erro), segue o 1º link de processo.
  if (!selfCodigo($)) {
    const lst = firstProcessoLink($);
    if (lst) {
      await sleep(config.delayMs);
      html = await showByCodigo(lst.codigo, lst.foro || foroHint, session);
      $ = load(html);
    }
  }
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
  const { ativas, passiva } = extractPartes($);
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
    partes_ativas: ativas,
    parte_passiva: passiva,
    andamentos,
  };
}

/** Coleta a árvore inteira a partir de um seed (CNJ recomendado). */
export async function crawlSeed(seed: string, session?: Session): Promise<ProcessoTree> {
  const sess = session ?? (await getSession());
  const root = await normalizeToRoot(seed, sess);
  const capa = extractCapa(root.$);

  // Blindagem: a busca não resolveu uma ficha real (não saiu do seed e sem
  // capa/incidentes) → falha o job p/ re-tentar via fila, em vez de gravar lixo.
  // Anexa um trecho do corpo recebido: sem isso, "não retornou página de detalhe" fica
  // indistinguível entre página de manutenção do TJSP, bloqueio, e CNJ que nunca foi e-SAJ.
  if (root.codigo === seed && !capa.cnj && !capa.classe && incidenteLinks(root.$).length === 0) {
    const corpo = root.$("body").text().replace(/\s+/g, " ").trim().slice(0, 200);
    throw new Error(`busca não retornou página de detalhe para seed=${seed} :: corpo="${corpo}"`);
  }

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
      const capaC = extractCapa($c);
      const partesC = extractPartes($c);
      incidentes.push({
        processo_codigo: `${c.codigo}#placeholder`,
        numero_incidente: null,
        tipo_previsto: "Indefinido",
        numero_depre: extractDepre($c("body").text()),
        cnj: capaC.cnj,
        status: capaC.status,
        tramitacao_prioritaria: capaC.tramitacao_prioritaria,
        valor_acao: capaC.valor_acao,
        data_base: capaC.data_base,
        partes_ativas: partesC.ativas,
        parte_passiva: partesC.passiva,
        andamentos: extractAndamentos($c),
      });
    }
    // CNJ do cumprimento vem no texto do link (a folha não traz #numeroProcesso).
    cumprimentos.push({ processo_codigo: c.codigo, cnj: extractCnj(c.texto), incidentes });
  }

  // incidentes pendurados direto na raiz (sem cumprimento) → cumprimento sintético
  if (directIncidentLinks.length > 0) {
    const incidentes: IncidenteData[] = [];
    for (const l of directIncidentLinks) incidentes.push(await buildIncidente(l.codigo, l.foro || root.foro, l.texto, sess));
    // FOR-196: cumprimento sintético — a execução corre no próprio processo, sem CNJ
    // de cumprimento separado. Usa o CNJ da própria raiz (capa.cnj), não null — senão
    // "Cumprimento de Sentença" fica em branco (achado: 347.482 incidentes afetados).
    cumprimentos.push({ processo_codigo: `${root.codigo}#cumprimento`, cnj: capa.cnj, incidentes });
  }

  // raiz sem nada → placeholder no nível raiz (só cálculo homologado, p.ex.)
  if (cumprimentos.length === 0) {
    const partesRoot = extractPartes(root.$);
    cumprimentos.push({
      processo_codigo: `${root.codigo}#cumprimento`,
      // FOR-196: idem acima — herda o CNJ da raiz em vez de null.
      cnj: capa.cnj,
      incidentes: [{
        processo_codigo: `${root.codigo}#placeholder`,
        numero_incidente: null, tipo_previsto: "Indefinido",
        numero_depre: extractDepre(root.$("body").text()),
        cnj: capa.cnj, status: capa.status, tramitacao_prioritaria: capa.tramitacao_prioritaria,
        valor_acao: capa.valor_acao, data_base: capa.data_base,
        partes_ativas: partesRoot.ativas, parte_passiva: partesRoot.passiva,
        andamentos: extractAndamentos(root.$),
      }],
    });
  }

  // Enriquecimento de OAB (e-SAJ não traz OAB; vem do DJEN). As publicações estão
  // sob o CNJ do seed (o número que o DJEN flagou) — que pode diferir do CNJ da raiz
  // quando há subida ao processo de conhecimento. Considera ambos. Casa por nome normalizado.
  // DJEN-first: lê os advogados já estruturados na ingestão; só vai à API ao vivo se o
  // banco não tiver nada (ex.: processo que não veio do DJEN). Best-effort.
  const cnjsParaOab = [...new Set([isCnj(seed) ? seed : null, capa.cnj].filter(Boolean) as string[])];
  const oabMap = await djenAdvogadosByCnj(cnjsParaOab.map((c) => c.replace(/\D/g, "")));
  if (oabMap.size === 0) {
    for (const c of cnjsParaOab) for (const [k, v] of await fetchAdvogadosByCnj(c)) if (!oabMap.has(k)) oabMap.set(k, v);
  }
  if (oabMap.size) {
    for (const c of cumprimentos) {
      for (const inc of c.incidentes) {
        for (const pa of inc.partes_ativas) {
          for (const adv of pa.advogados) {
            const hit = oabMap.get(normNome(adv.nome));
            if (hit) { adv.oab = hit.oab; adv.oab_normalizada = hit.oab_normalizada; adv.sem_oab = false; }
          }
        }
      }
    }
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

// FOR-195 — busca só a página do processo indicado (sem subir a árvore, sem persistir) e
// extrai o link de volta pra ação principal (a.processoPrinc), se existir. Usado pelo backfill
// de legado (`backfill-legado-cumprimento-principal.ts`): os ~11.202 `processos` legado
// (`processo_codigo LIKE 'LEGADO-%'`) hoje representam, por engano, o CUMPRIMENTO como se fosse a
// raiz (promovido a "raiz" porque o seed que originou aquela reconciliação foi o próprio CNJ do
// cumprimento, não um código e-SAJ real). Esta função busca a página desse processo e segue
// `a.processoPrinc`, exatamente como `normalizeToRoot` faria — mas só 1 (ou 2, se achar)
// página(s), sem incidentes/cumprimentos/persistTree.
//
// null = a própria página já é raiz (sem `a.processoPrinc`) — regra espelhada na FOR-196: nada
// a fazer, o processo já está corretamente representado.
//
// `seed` aceita tanto um código e-SAJ interno quanto um CNJ (mesma distinção que
// `normalizeToRoot` faz via `isCnj`) — necessário porque ~98% da população real (candidatos cujo
// `processos.processo_codigo` ainda é `LEGADO-...`, nunca um código e-SAJ real) só tem o CNJ como
// ponto de entrada conhecido (achado do code-review FOR-195: a versão original só aceitava
// código e-SAJ, cobrindo só os ~200 casos já promovidos a código real por outro crawl anterior).
export async function fetchProcessoPrincipal(
  seed: string, foro: string, session: Session,
): Promise<ProcessoPrincipalInfo | null> {
  const foroHint = isCnj(seed) ? parseCnj(seed)?.foro ?? foro : foro;
  let $ = isCnj(seed) ? load(await searchByCnj(seed, session)) : load(await showByCodigo(seed, foroHint, session));

  // Blindagem só necessária no caminho por CNJ (`normalizeToRoot` tem a mesma): a busca por CNJ
  // pode cair numa lista de resultados em vez da ficha direta — segue o 1º link de processo nesse
  // caso. `showByCodigo` com um código e-SAJ exato nunca cai em lista, por isso o caminho por
  // código (seed não-CNJ) segue direto pra `processoPrincLink`, como antes.
  if (isCnj(seed) && !selfCodigo($)) {
    const lst = firstProcessoLink($);
    if (!lst) return null; // CNJ não encontrado no e-SAJ
    await sleep(config.delayMs);
    $ = load(await showByCodigo(lst.codigo, lst.foro || foroHint, session));
  }

  const link = processoPrincLink($);
  if (!link) return null;

  await sleep(config.delayMs);
  const $p = load(await showByCodigo(link.codigo, link.foro || foroHint, session));
  const capa = extractCapa($p);
  const { passiva } = extractPartes($p);

  return {
    processo_codigo: link.codigo,
    foro: capa.foro ?? link.foro ?? foroHint,
    cnj: capa.cnj,
    classe: capa.classe,
    assunto: capa.assunto,
    distribuicao: capa.distribuicao,
    valor_acao: capa.valor_acao,
    data_base: capa.data_base,
    status: capa.status,
    ente_nome: passiva?.nome ?? null,
    ente_esfera: passiva?.ente_esfera ?? null,
    flag_sp: !!passiva && passiva.ente_esfera !== "Outro",
  };
}

export interface RequisitorioResult {
  tree: ProcessoTree;
  origem: string[]; // CNJs do(s) processo(s) de origem → enfileirar p/ o cpopg
  origemInfo: OrigemInfo[]; // idem, com o número do incidente de origem quando presente
  precatorio: { processo_depre: string; valor_acao: number | null; status: string | null; devedora: string | null };
}

/** Coleta UM requisitório (.0500) na Consulta de Requisitórios. A ficha é a mesma
 * `show.do` de um processo normal (foro=0500), mas SEM "Processo principal" (o .0500
 * já é a raiz). Reusa os parsers; monta uma árvore de 1 incidente (Precatorio) e
 * devolve os CNJs de origem + os campos do precatório p/ reuso em `precatorios`. */
export async function crawlRequisitorio(seed: string, session?: Session): Promise<RequisitorioResult> {
  const sess = session ?? (await getRequisitorioSession());
  let html = await searchRequisitorioByCnj(seed, sess);
  let $ = load(html);
  // Sem ficha direta → segue o 1º link de resultado (lista da busca).
  let self = selfCodigo($);
  if (!self) {
    const lst = firstProcessoLink($);
    if (lst) {
      await sleep(config.delayMs);
      html = await showByCodigo(lst.codigo, lst.foro || "500", sess, reqReferer());
      $ = load(html);
      self = selfCodigo($);
    }
  }
  const codigo = self?.codigo ?? seed;
  const foro = self?.foro || "500";

  const capa = extractCapa($);
  // Blindagem: não resolveu ficha real → falha p/ re-tentar (não grava lixo).
  if (codigo === seed && !capa.cnj && !capa.classe && incidenteLinks($).length === 0) {
    const corpo = $("body").text().replace(/\s+/g, " ").trim().slice(0, 200);
    throw new Error(`requisitório não retornou página de detalhe para seed=${seed} :: corpo="${corpo}"`);
  }

  const { ativas, passiva } = extractPartes($);
  const andamentos = extractAndamentos($);
  const cnj = capa.cnj ?? (isCnj(seed) ? seed : null);
  const origemInfo = extractOrigemInfo($);
  const origem = origemInfo.map((o) => o.cnj);

  // OAB (DJEN-first): publicações do .0500 estão sob o próprio número.
  if (ativas.some((pa) => pa.advogados.length)) {
    const oabMap = await djenAdvogadosByCnj([seed.replace(/\D/g, "")]);
    if (oabMap.size === 0) for (const [k, v] of await fetchAdvogadosByCnj(seed)) if (!oabMap.has(k)) oabMap.set(k, v);
    for (const pa of ativas) {
      for (const adv of pa.advogados) {
        const hit = oabMap.get(normNome(adv.nome));
        if (hit) { adv.oab = hit.oab; adv.oab_normalizada = hit.oab_normalizada; adv.sem_oab = false; }
      }
    }
  }

  const incidente: IncidenteData = {
    processo_codigo: codigo,
    numero_incidente: null,
    tipo_previsto: "Precatorio",
    numero_depre: cnj ?? seed,
    cnj,
    status: capa.status,
    tramitacao_prioritaria: capa.tramitacao_prioritaria,
    valor_acao: capa.valor_acao,
    data_base: capa.data_base,
    partes_ativas: ativas,
    parte_passiva: passiva,
    andamentos,
  };
  const tree: ProcessoTree = {
    processo_codigo: codigo,
    cnj,
    foro,
    classe: capa.classe ?? "Precatório",
    assunto: capa.assunto,
    distribuicao: capa.distribuicao,
    valor_acao: capa.valor_acao,
    data_base: capa.data_base,
    status: capa.status,
    cumprimentos: [{ processo_codigo: `${codigo}#requisitorio`, cnj: null, incidentes: [incidente] }],
  };
  return {
    tree,
    origem,
    origemInfo,
    precatorio: { processo_depre: cnj ?? seed, valor_acao: capa.valor_acao, status: capa.status, devedora: passiva?.nome ?? null },
  };
}
