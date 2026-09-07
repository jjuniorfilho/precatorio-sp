// FOR-102 — OCR leve do captcha da "Pesquisa dos Precatórios e Pagamentos" (TJSP).
// São 191 imagens estáticas (Captcha/images/1.jpg..191.jpg, 140x39, texto simples com
// ruído de pontos) — testado contra 10 exemplos reais via hash MD5 conhecido
// (Captcha/jcap.js expõe a resposta certa de cada imagem em texto puro): ~50-60% de
// acerto no primeiro palpite com o pipeline abaixo. Suficiente porque o captcha é de
// graça pra recarregar ("Nova Imagem") — o chamador (pagamentos-tjsp.ts) deve tentar
// de novo com uma imagem nova em caso de rejeição, em vez de exigir alta precisão aqui.
//
// Depende dos binários de sistema `convert` (ImageMagick) e `tesseract` (Tesseract OCR
// + pacote de idioma `eng`) já instalados na VPS — mesmo padrão do projeto de usar CLIs
// de sistema (ex.: pdftotext no pipeline DEPRE) em vez de libs Node pesadas.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

const execFileAsync = promisify(execFile);

/** Resolve o texto de uma imagem de captcha (JPEG cru). Melhor palpite, sem garantia. */
export async function solveCaptcha(imageBuffer: Buffer): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), "captcha-"));
  const raw = join(dir, "raw.jpg");
  const proc = join(dir, "proc.png");
  try {
    await writeFile(raw, imageBuffer);
    // grayscale + despeckle (remove o ruído de pontos) + upscale 6x + threshold — pipeline
    // testado contra exemplos reais (ver plan.md da sessão FOR-102 pra métricas).
    await execFileAsync("convert", [
      raw, "-colorspace", "gray", "-despeckle", "-despeckle",
      "-resize", "600%", "-threshold", "55%", proc,
    ]);
    const { stdout } = await execFileAsync("tesseract", [
      proc, "stdout", "--psm", "8", "-l", "eng",
      "-c", "tessedit_char_whitelist=abcdefghijklmnopqrstuvwxyz",
    ]);
    return stdout.trim().toLowerCase();
  } finally {
    await rm(dir, { recursive: true, force: true }).catch(() => {});
  }
}
