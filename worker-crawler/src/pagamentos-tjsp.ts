// FOR-102 — Navegação do portal TJSP "Pagamentos Precatórios" (pesquisainternetv2.aspx),
// busca por processo_depre (.0500), via Playwright.
//
// Por que Playwright (e não HTTP puro, como o e-SAJ em esaj.ts): esse portal é uma
// aplicação GeneXus (ASP.NET + AJAX próprio, sessão/estado bem mais complexos que os
// forms Struts do e-SAJ). Tentativas de replicar o protocolo AJAX via undici bateram em
// HTTP 440 "Session timeout" de forma consistente — ver plan.md da sessão FOR-102 (Fase 3).
//
// Fluxo real (confirmado ao vivo, inclusive por captura de navegador do usuário):
// webmenupesquisa.aspx → token de "Pagamentos Precatórios" → pesquisainternetv2.aspx
// (busca por Processo DEPRE + captcha) → grade de resultado (status já visível) → clicar
// no ícone "Selecionar" da linha abre uma ABA NOVA com um PDF gerado sob demanda
// (arelpesquisainternetprecatorio.aspx) contendo a seção "Pagamentos do Processo"
// (Data | Valor R$ | Tipo) quando há pagamentos.
//
// Concorrência: a VPS tem só 1 vCPU / ~2GB livres, compartilhada com outros serviços em
// produção (comunica-web-api, comunica-saas-api, o próprio precatorio-crawler). Rodar
// múltiplos Chromiums em paralelo arrisca derrubar a VPS inteira — por isso todo acesso
// a este módulo passa pela fila de concorrência-1 em `fila.ts`.
import { chromium, type Browser, type BrowserContext, type Page } from "playwright";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { solveCaptcha } from "./captcha.js";
import { comFilaPlaywright } from "./fila.js";
import { upsertPagamentos, marcarPagamentosConsultado, registrarConsultaPagamento } from "./supabase.js";
import { classificarHtml, type ResultadoConsulta } from "./pagamentos-classificar.js";
import { PassosCollector, ConsultaPagamentoErro, type Etapa, type Passo } from "./pagamentos-passos.js";

export { classificarHtml } from "./pagamentos-classificar.js";
export type { ResultadoConsulta } from "./pagamentos-classificar.js";
export { PassosCollector, ConsultaPagamentoErro } from "./pagamentos-passos.js";

const execFileAsync = promisify(execFile);
const BASE = "https://www.tjsp.jus.br/cac/scp";
const RESULTADO_RE = /pesquisainternetnumanoep\.aspx/;

export type OrigemConsulta = "manual" | "busca_publica" | "crawler";
export const ORIGENS_CONSULTA: readonly OrigemConsulta[] = ["manual", "busca_publica", "crawler"];

export interface Pagamento {
  data: string | null; // ISO (YYYY-MM-DD) quando possível
  valorCentavos: number;
  tipo: string | null;
}

export interface ConsultaPagamento {
  /** Compat (edge buscar-precatorio): true só quando `resultado === 'encontrado'`. */
  encontrado: boolean;
  /** FOR-171: encontrado | nao_consta (portal respondeu que não consta — válido) | falha (lança erro). */
  resultado: ResultadoConsulta;
  situacao: string | null; // texto da grade, ex. "Pendente de Pagamento"
  pagamentos: Pagamento[]; // linhas do PDF "Pagamentos do Processo" (pode ser vazia)
  /** ISO do fim da consulta (horário do servidor do worker). */
  consultadoEm: string;
  /** "Data da Consulta" mostrada pelo portal (texto), quando disponível. */
  dataConsultaPortal: string | null;
  tentativas: number;
}

/** Consulta a situação/pagamentos de um processo_depre (.0500). Serializado (fila, 1 por vez).
 * Lança `ConsultaPagamentoErro` (com a etapa) em caso de falha/instabilidade. */
export async function consultarPagamentos(
  processoDepre: string,
  maxTentativas = 4,
  passos: PassosCollector = new PassosCollector(),
): Promise<ConsultaPagamento> {
  return comFilaPlaywright(() => consultarInterno(processoDepre, maxTentativas, passos));
}

/** Dependências injetáveis (testes) de consultarEPersistirPagamentos. */
export interface DepsPersistencia {
  consultar: (processoDepre: string, maxTentativas: number, passos: PassosCollector) => Promise<ConsultaPagamento>;
  upsert: typeof upsertPagamentos;
  marcar: typeof marcarPagamentosConsultado;
  registrar: typeof registrarConsultaPagamento;
}
const depsPadrao: DepsPersistencia = {
  consultar: consultarPagamentos,
  upsert: upsertPagamentos,
  marcar: marcarPagamentosConsultado,
  registrar: registrarConsultaPagamento,
};

export function origemValida(v: unknown): v is OrigemConsulta {
  return typeof v === "string" && (ORIGENS_CONSULTA as readonly string[]).includes(v);
}

export interface OpcoesConsultaPersistida {
  origem?: OrigemConsulta;
  maxTentativas?: number;
}

/** Consulta e já persiste no Supabase (upsert dos pagamentos + marca `pagamentos_consultado_em`).
 * FOR-171: `encontrado` E `nao_consta` marcam consultado (o portal respondeu — ausência é resultado
 * válido); `falha` NUNCA marca. Toda consulta (inclusive falha) é registrada em
 * `pagamentos_consultas_log`, em best-effort (erro ao gravar o log não derruba a consulta).
 * É esta a função que o endpoint HTTP deve chamar, não `consultarPagamentos` diretamente. */
export async function consultarEPersistirPagamentos(
  processoDepre: string,
  opcoes: OpcoesConsultaPersistida | number = {},
  deps: DepsPersistencia = depsPadrao,
): Promise<ConsultaPagamento> {
  const { origem = "manual", maxTentativas = 4 } = typeof opcoes === "number" ? { maxTentativas: opcoes } : opcoes;
  const passos = new PassosCollector();
  const iniciadaEm = new Date();
  let consulta: ConsultaPagamento | null = null;
  let erro: unknown = null;
  try {
    consulta = await deps.consultar(processoDepre, maxTentativas, passos);
    try {
      // encontrado E nao_consta marcam consultado (resultado válido); `falha` já lançou acima.
      await deps.upsert(processoDepre, consulta.pagamentos);
      await deps.marcar(processoDepre);
      passos.passo("persistir", "ok", `${consulta.pagamentos.length} pagamento(s); marcado como consultado`);
    } catch (e) {
      // Mensagem crua do banco só no console (o log é lido pelo admin anônimo via RPC).
      console.error(`[pagamentos] persistência falhou (${processoDepre}):`, e);
      passos.passo("persistir", "erro", "falha ao gravar o resultado no banco");
      throw new ConsultaPagamentoErro("persistência falhou (falha ao gravar o resultado no banco)", "persistir", passos);
    }
  } catch (e) {
    erro = e;
  }

  const etapaFalha = erro ? (erro instanceof ConsultaPagamentoErro ? erro.etapa : "desconhecida") : null;
  await deps.registrar({
    processoDepre,
    iniciadaEm,
    finalizadaEm: new Date(),
    origem,
    resultado: erro ? "falha" : consulta!.resultado,
    tentativas: passos.tentativas,
    situacao: consulta?.situacao ?? null,
    qtdPagamentos: consulta?.pagamentos.length ?? null,
    dataConsultaPortal: consulta?.dataConsultaPortal ?? null,
    erro: erro ? String(erro instanceof Error ? erro.message : erro) : null,
    etapaFalha,
    passos: passos.passos as Passo[],
  }).catch((e) => console.error(`[pagamentos] log da consulta não gravado (${processoDepre}):`, e));

  if (erro) throw erro;
  return consulta!;
}

async function consultarInterno(
  processoDepre: string,
  maxTentativas: number,
  passos: PassosCollector,
): Promise<ConsultaPagamento> {
  let etapa: Etapa = "abrir_portal";
  // --disable-dev-shm-usage: VPS com pouca memória (1 vCPU/~2GB, compartilhada — ver
  // comentário no topo do arquivo) tem /dev/shm pequeno demais pro Chromium default, o que
  // derruba o processo no meio de uma tentativa ("Target page, context or browser has been
  // closed", visto em produção). --no-sandbox: necessário rodando como root na VPS.
  let browser: Browser | null = null;
  try {
    browser = await chromium.launch({
      headless: true,
      args: ["--disable-dev-shm-usage", "--no-sandbox"],
    });
    const context = await browser.newContext({ acceptDownloads: true });
    const page = await context.newPage();

    // 1) Menu público (sem login) → link assinado por sessão de "Pagamentos Precatórios".
    await page.goto(`${BASE}/webmenupesquisa.aspx`, { waitUntil: "domcontentloaded" });
    passos.passo("abrir_portal", "ok", "Abriu o portal TJSP (Pagamentos Precatórios)");
    etapa = "obter_link";
    const link = await page.locator("#LBLPAGAMENTOSV2 a").getAttribute("href");
    if (!link) throw new Error("link de Pagamentos Precatórios não encontrado no menu");
    passos.passo("obter_link", "ok");
    etapa = "abrir_pesquisa";
    await page.goto(`${BASE}/${link}`, { waitUntil: "networkidle" });
    passos.passo("abrir_pesquisa", "ok", "Abriu a pesquisa por Processo DEPRE");

    etapa = "busca";
    for (let tentativa = 1; tentativa <= maxTentativas; tentativa++) {
      if (RESULTADO_RE.test(page.url())) break; // busca de uma tentativa anterior já completou
      passos.tentativas = tentativa;
      const ok = await tentarBusca(page, processoDepre);
      passos.passo("busca", ok ? "ok" : "info", ok ? `Tentativa ${tentativa}: busca executada` : `Tentativa ${tentativa}: captcha rejeitado ou sem resultado`);
      if (ok) break;
      if (tentativa === maxTentativas) {
        passos.passo("busca", "erro", `captcha não resolvido após ${maxTentativas} tentativas`);
        throw new Error(`consultarPagamentos: captcha não resolvido após ${maxTentativas} tentativas`);
      }
      // pede captcha novo (é de graça); espera o AJAX do reload assentar antes da próxima
      // tentativa — sem isso, o próximo fill() pode cair no meio de um form temporariamente
      // desabilitado e travar (mesma classe de corrida do fix em tentarBusca).
      await page.locator("#CAPTCHA1Container a").click().catch(() => {});
      await page.waitForLoadState("networkidle").catch(() => {});
      await page.waitForTimeout(500);
    }
    if (passos.tentativas === 0) passos.tentativas = 1;
    passos.passo("resultado_carregou", "ok", "Página de resultado carregou");

    etapa = "ler_resultado";
    const cls = await lerResultado(page);
    if (cls.resultado === "falha") {
      passos.passo("ler_resultado", "erro", cls.motivo);
      throw new Error(`resposta do portal não reconhecida: ${cls.motivo}`);
    }
    passos.passo("ler_resultado", "ok", cls.motivo);

    let pagamentos: Pagamento[] = [];
    if (cls.resultado === "encontrado") {
      etapa = "extrair_pagamentos";
      pagamentos = await abrirRelatorioEExtrairPagamentos(context, page);
      passos.passo("extrair_pagamentos", "ok", `${pagamentos.length} pagamento(s) no relatório`);
    }
    return {
      encontrado: cls.resultado === "encontrado",
      resultado: cls.resultado,
      situacao: cls.situacao,
      pagamentos,
      consultadoEm: new Date().toISOString(),
      dataConsultaPortal: cls.dataConsultaPortal,
      tentativas: passos.tentativas,
    };
  } catch (e) {
    if (e instanceof ConsultaPagamentoErro) throw e;
    if (!passos.passos.some((p) => p.etapa === etapa && p.status === "erro")) {
      passos.passo(etapa, "erro", e instanceof Error ? e.message : String(e));
    }
    throw new ConsultaPagamentoErro(e instanceof Error ? e.message : String(e), etapa, passos);
  } finally {
    await browser?.close().catch(() => {});
  }
}

/** Preenche o form (Processo DEPRE) + resolve o captcha atual + clica Pesquisar. Retorna
 * `false` se o captcha foi rejeitado (chamador deve pedir um novo e tentar de novo).
 *
 * Ordem importa: o `blur` do campo do captcha dispara uma validação assíncrona (AJAX) no
 * servidor — clicar em "Pesquisar" antes dela terminar faz a busca ser ignorada. Por isso
 * esperamos `networkidle` + uma folga entre o blur e o clique, e damos um timeout generoso
 * pra navegação (o backend pode demorar) antes de desistir e pedir um captcha novo — timeout
 * curto demais causa uma corrida onde a busca anterior completa DEPOIS que já pedimos outro
 * captcha, deixando a página num estado inconsistente pra próxima tentativa (ver plan.md).
 */
async function tentarBusca(page: Page, processoDepre: string): Promise<boolean> {
  await page.locator('select[name="vOPCAOPESQUISA"], #vOPCAOPESQUISA').selectOption("01").catch(() => {});
  await page.locator('input[name="vPRP_PROCESSO"]').fill(processoDepre);

  const captchaImg = page.locator("#CAPTCHA1Container img");
  const imgSrc = await captchaImg.getAttribute("src");
  if (!imgSrc) throw new Error("imagem do captcha não encontrada");
  const imgUrl = new URL(imgSrc, page.url()).toString();
  const imgResponse = await page.request.get(imgUrl);
  const imgBuffer = await imgResponse.body();
  const guess = await solveCaptcha(imgBuffer);

  const cfield = page.locator('input[name="cfield"], #_cfield');
  await cfield.fill(guess);
  await cfield.blur();
  await page.waitForLoadState("networkidle");
  await page.waitForTimeout(500); // folga pra validação assíncrona do captcha assentar

  await page.locator('input[name="BUTTON3"]').click();
  try {
    await page.waitForURL(RESULTADO_RE, { timeout: 25_000 });
    return true;
  } catch {
    await page.waitForLoadState("networkidle").catch(() => {});
    return RESULTADO_RE.test(page.url());
  }
}

/** Lê o resultado da página (FOR-171): classifica o HTML (grade / TXTNENHUM server-side / rodapé)
 * e confirma com a visibilidade COMPUTADA da mensagem `#TXTNENHUM` no navegador. Se os dois sinais
 * divergirem, o resultado é `falha` (nunca marcamos "consultado" na dúvida).
 *
 * Nota: a mensagem "Não foram encontrados Processos…" fica SEMPRE no HTML (oculta por CSS quando há
 * resultado) — só a visibilidade (não a presença) é sinal. Validado no portal real em 25/09/2026. */
async function lerResultado(page: Page) {
  const cls = classificarHtml(await page.content(), page.url());
  if (cls.resultado === "nao_consta") {
    const visivel = await page.locator("#TXTNENHUM").first().isVisible().catch(() => false);
    if (!visivel) {
      return { ...cls, resultado: "falha" as const, motivo: "sinais divergentes: HTML indica não consta, mas #TXTNENHUM não está visível no navegador" };
    }
  }
  return cls;
}

/** Clica no ícone "Selecionar" da 1ª linha — o GeneXus abre uma aba nova (via
 * `RCOOpenWindowRender.js` + `window.open`) que o Chromium trata como **download** (não
 * navegação normal): a aba não expõe uma URL utilizável (`page.url()` fica preso em `":"`)
 * e o corpo da resposta via CDP não é lido de forma confiável quando é tratado como
 * download ("No resource with given identifier found"). A forma correta é usar a própria
 * API de download do Playwright (`page.on("download")` + `download.path()`), com o
 * contexto criado com `acceptDownloads: true`. */
async function abrirRelatorioEExtrairPagamentos(context: BrowserContext, page: Page): Promise<Pagamento[]> {
  const icone = page.locator('input[type="image"][name^="vSELECIONAR_"]').first();
  // FOR-171: com linha na grade o ícone "Selecionar" TEM que existir e o PDF tem que baixar —
  // se não, é falha (não marcar "consultado" com 0 pagamentos na dúvida).
  if ((await icone.count()) === 0) throw new Error('ícone "Selecionar" da grade não encontrado');

  const downloadPromise = page.waitForEvent("download", { timeout: 20_000 }).catch(() => null);
  const novaPaginaPromise = context.waitForEvent("page", { timeout: 20_000 }).catch(() => null);

  await icone.click({ timeout: 10_000 });
  const download = await downloadPromise;

  const novaPagina = await novaPaginaPromise;
  await novaPagina?.close().catch(() => {});

  if (!download) throw new Error("relatório de pagamentos (PDF) não foi baixado");
  const path = await download.path();
  if (!path) throw new Error("relatório de pagamentos (PDF) sem arquivo local");

  return parsePagamentosPdf(await pdfToText(path));
}

/** `pdftotext` (poppler) — mesma ferramenta já usada no pipeline DEPRE deste projeto
 * (bin/extract_depre.py) — extrai o texto do PDF do relatório (já salvo em disco pelo
 * Playwright via `download.path()`). */
async function pdfToText(pdfPath: string): Promise<string> {
  const { stdout } = await execFileAsync("pdftotext", ["-layout", pdfPath, "-"]);
  return stdout;
}

/** Extrai {data, valor, tipo} da seção "Pagamentos do Processo" do texto do PDF. */
function parsePagamentosPdf(texto: string): Pagamento[] {
  const pagamentos: Pagamento[] = [];
  const linhaRe = /(\d{2}\/\d{2}\/\d{4})\s+([\d.,]+)\s+(\S.*\S|\S)$/gm;
  let m: RegExpExecArray | null;
  while ((m = linhaRe.exec(texto))) {
    const [, dataBr, valorStr, tipo] = m;
    const [dd, mm, yyyy] = dataBr!.split("/");
    const valorCentavos = Math.round(parseFloat(valorStr!.replace(/\./g, "").replace(",", ".")) * 100);
    if (!Number.isFinite(valorCentavos)) continue;
    pagamentos.push({ data: `${yyyy}-${mm}-${dd}`, valorCentavos, tipo: tipo!.trim() || null });
  }
  return pagamentos;
}
