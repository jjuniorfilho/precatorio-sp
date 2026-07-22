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

const execFileAsync = promisify(execFile);
const BASE = "https://www.tjsp.jus.br/cac/scp";
const RESULTADO_RE = /pesquisainternetnumanoep\.aspx/;

export interface Pagamento {
  data: string | null; // ISO (YYYY-MM-DD) quando possível
  valorCentavos: number;
  tipo: string | null;
}

export interface ConsultaPagamento {
  encontrado: boolean;
  situacao: string | null; // texto da grade, ex. "Pendente de Pagamento"
  pagamentos: Pagamento[]; // linhas do PDF "Pagamentos do Processo" (pode ser vazia)
}

/** Consulta a situação/pagamentos de um processo_depre (.0500). Serializado (fila, 1 por vez). */
export async function consultarPagamentos(
  processoDepre: string,
  maxTentativas = 4,
): Promise<ConsultaPagamento> {
  return comFilaPlaywright(() => consultarInterno(processoDepre, maxTentativas));
}

async function consultarInterno(
  processoDepre: string,
  maxTentativas: number,
): Promise<ConsultaPagamento> {
  const browser: Browser = await chromium.launch({ headless: true });
  try {
    const context = await browser.newContext({ acceptDownloads: true });
    const page = await context.newPage();

    // 1) Menu público (sem login) → link assinado por sessão de "Pagamentos Precatórios".
    await page.goto(`${BASE}/webmenupesquisa.aspx`, { waitUntil: "domcontentloaded" });
    const link = await page.locator("#LBLPAGAMENTOSV2 a").getAttribute("href");
    if (!link) throw new Error("link de Pagamentos Precatórios não encontrado no menu");
    await page.goto(`${BASE}/${link}`, { waitUntil: "networkidle" });

    for (let tentativa = 1; tentativa <= maxTentativas; tentativa++) {
      if (RESULTADO_RE.test(page.url())) break; // busca de uma tentativa anterior já completou
      const ok = await tentarBusca(page, processoDepre);
      if (ok) break;
      if (tentativa === maxTentativas) {
        throw new Error(`consultarPagamentos: captcha não resolvido após ${maxTentativas} tentativas`);
      }
      // pede captcha novo (é de graça); espera o AJAX do reload assentar antes da próxima
      // tentativa — sem isso, o próximo fill() pode cair no meio de um form temporariamente
      // desabilitado e travar (mesma classe de corrida do fix em tentarBusca).
      await page.locator("#CAPTCHA1Container a").click().catch(() => {});
      await page.waitForLoadState("networkidle").catch(() => {});
      await page.waitForTimeout(500);
    }

    const { encontrado, situacao } = await extrairSituacao(page);
    if (!encontrado) return { encontrado: false, situacao: null, pagamentos: [] };

    const pagamentos = await abrirRelatorioEExtrairPagamentos(context, page);
    return { encontrado: true, situacao, pagamentos };
  } finally {
    await browser.close();
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

/** Lê o status da 1ª linha da grade de resultado (`span_PRP_SITUACAO_ANDAMENTO_NNNN`).
 *
 * Nota: a mensagem "Não foram encontrados Processos com estes filtros !!!" fica sempre
 * presente no HTML (só oculta via CSS), mesmo quando HÁ resultado — não é um sinal
 * confiável de "não encontrado". O sinal correto é a presença da própria linha da grade
 * (`span_PRP_SITUACAO_ANDAMENTO_NNNN`), que só existe quando há resultado.
 */
async function extrairSituacao(page: Page): Promise<{ encontrado: boolean; situacao: string | null }> {
  const status = page.locator('span[id^="span_PRP_SITUACAO_ANDAMENTO_"]').first();
  if ((await status.count()) === 0) return { encontrado: false, situacao: null };
  const texto = (await status.innerText()).trim();
  return { encontrado: true, situacao: texto || null };
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
  if ((await icone.count()) === 0) return [];

  const downloadPromise = page.waitForEvent("download", { timeout: 20_000 }).catch(() => null);
  const novaPaginaPromise = context.waitForEvent("page", { timeout: 20_000 }).catch(() => null);

  await icone.click({ timeout: 10_000 });
  const download = await downloadPromise;

  const novaPagina = await novaPaginaPromise;
  await novaPagina?.close().catch(() => {});

  if (!download) return [];
  const path = await download.path();
  if (!path) return [];

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
