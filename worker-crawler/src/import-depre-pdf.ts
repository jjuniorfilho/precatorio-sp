// Import mensal do PDF "Consulta do Total da Dívida Anual - Detalhado" (TJSP) — duas fontes,
// mesmo layout tabular: Estado de SP (FE001) e Prefeitura de SP (PM576). Recalcula
// `precatorios` do zero por fonte todo mês (delete + reimport), já que o PDF já traz o saldo
// atualizado — não tem por que tentar diffar linha a linha.
//
// Uso: tsx src/import-depre-pdf.ts --pdf=<arquivo.pdf> --fonte=estado|municipio --apply [--limit=N]
//
// Sem --apply: só parseia e valida (nunca escreve). A validação central é o checksum: soma de
// Valor Pago e Saldo de todas as linhas extraídas tem que bater EXATAMENTE com o "TOTAL GERAL"
// impresso no próprio PDF — se não bater, aborta antes de qualquer escrita (o parser pode ter
// errado alguma linha, e isso é dado financeiro real).
import { execFileSync } from "node:child_process";
import { readFileSync, unlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { supabase, ensureAuth } from "./supabase.js";
import { assertConfig, config } from "./config.js";

type Fonte = "estado" | "municipio";

interface LinhaPrecatorio {
  processo_depre: string;
  natureza: string;
  dt_ensejo_ordem: string; // YYYY-MM-DD
  condicao_superpreferencia: string;
  valor_pago: number; // centavos
  saldo_depre: number; // centavos
  data_protocolo: string | null; // YYYY-MM-DD
  fonte_relatorio: Fonte;
}

const ROW_RE = /^(\d{7}-\d{2}\.\d{4}\.8\.26\.0500)\s+([AO])\s+(.*)$/;
const CONDICAO_RE = /(Há registros de credores em condição de superpreferência neste precatório|Não há registros de credores em condição de superpreferência neste precatório)/;
const DATE_RE = /\d{2}\/\d{2}\/\d{4}/g;
const MONEY_RE = /-?[\d.]+,\d{2}/g;
const TOTAL_GERAL_RE = /^TOTAL GERAL:\s+(-?[\d.]+,\d{2})\s+(-?[\d.]+,\d{2})/m;

const NATUREZA: Record<string, string> = { A: "Alimentar", O: "Outras" };

function ddmmyyyyToIso(d: string): string {
  const [dd, mm, yyyy] = d.split("/");
  return `${yyyy}-${mm}-${dd}`;
}

/** "1.234.567,89" ou "-45.981,14" → centavos (inteiro). */
function moneyToCentavos(s: string): number {
  const neg = s.startsWith("-");
  const semSinal = neg ? s.slice(1) : s;
  const [inteiro, centavos] = semSinal.split(",") as [string, string];
  const n = parseInt(inteiro.replace(/\./g, ""), 10) * 100 + parseInt(centavos, 10);
  return neg ? -n : n;
}

function centavosToMoneyStr(c: number): string {
  const neg = c < 0;
  const abs = Math.abs(c);
  const reais = Math.floor(abs / 100);
  const cent = abs % 100;
  return `${neg ? "-" : ""}${reais.toLocaleString("pt-BR")},${String(cent).padStart(2, "0")}`;
}

interface ParseResult {
  linhas: LinhaPrecatorio[];
  erros: Array<{ linha: string; motivo: string }>;
  totalGeralPago: number | null;
  totalGeralSaldo: number | null;
}

function parseTexto(texto: string, fonte: Fonte): ParseResult {
  const linhas: LinhaPrecatorio[] = [];
  const erros: Array<{ linha: string; motivo: string }> = [];

  const rawLines = texto.split("\n");
  for (let i = 0; i < rawLines.length; i++) {
    const linha = rawLines[i]!.trim();
    if (!linha) continue;
    const m = ROW_RE.exec(linha);
    if (!m) continue; // header, "Total do Ano de X", "TOTAL GERAL", rodapé etc. — não é linha de dado
    const [, processoDepre, nat, restoInicial] = m;

    // pdftotext -layout às vezes quebra uma linha de dado em duas quando o conteúdo de
    // Protocolo/Nº Ordem é largo demais pra largura da coluna (achado real, pego pelo
    // checksum contra o TOTAL GERAL — sem isso o parser perdia essas linhas silenciosamente).
    // A continuação nunca começa com um número de processo, então emendar até achar a
    // condição (ou desistir depois de algumas linhas) é seguro.
    let resto = restoInicial!;
    let emendas = 0;
    while (!CONDICAO_RE.test(resto) && emendas < 2 && i + 1 < rawLines.length) {
      i++;
      resto += " " + rawLines[i]!.trim();
      emendas++;
    }

    const condMatch = CONDICAO_RE.exec(resto);
    if (!condMatch) {
      erros.push({ linha, motivo: "condição de superpreferência não encontrada (mesmo após emendar linhas)" });
      continue;
    }
    const antes = resto.slice(0, condMatch.index);
    const depois = resto.slice(condMatch.index + condMatch[0].length);

    const datas = antes.match(DATE_RE) ?? [];
    if (datas.length === 0) {
      erros.push({ linha, motivo: "nenhuma data encontrada antes da condição" });
      continue;
    }
    const dtEnsejoOrdem = datas[datas.length - 1]!;
    const dataProtocolo = datas[0]!;

    const valores = depois.match(MONEY_RE) ?? [];
    if (valores.length !== 2) {
      erros.push({ linha, motivo: `esperava 2 valores monetários após a condição, achou ${valores.length}` });
      continue;
    }

    if (emendas > 0 && process.env.DEBUG_EMENDAS) {
      console.error(`[emenda x${emendas}] ${processoDepre} resto="${resto}"`);
    }

    linhas.push({
      processo_depre: processoDepre!,
      natureza: NATUREZA[nat!] ?? nat!,
      dt_ensejo_ordem: ddmmyyyyToIso(dtEnsejoOrdem),
      condicao_superpreferencia: condMatch[0],
      valor_pago: moneyToCentavos(valores[0]!),
      saldo_depre: moneyToCentavos(valores[1]!),
      data_protocolo: dataProtocolo ? ddmmyyyyToIso(dataProtocolo) : null,
      fonte_relatorio: fonte,
    });
  }

  const totalMatch = TOTAL_GERAL_RE.exec(texto);
  return {
    linhas,
    erros,
    totalGeralPago: totalMatch ? moneyToCentavos(totalMatch[1]!) : null,
    totalGeralSaldo: totalMatch ? moneyToCentavos(totalMatch[2]!) : null,
  };
}

function extrairTexto(pdfPath: string): string {
  const tmpTxt = join(tmpdir(), `depre-${Date.now()}.txt`);
  try {
    execFileSync("pdftotext", ["-layout", pdfPath, tmpTxt], { maxBuffer: 1024 * 1024 * 1024 });
    return readFileSync(tmpTxt, "utf8");
  } finally {
    try { unlinkSync(tmpTxt); } catch { /* best-effort */ }
  }
}

async function runPool<T>(items: T[], limit: number, fn: (item: T) => Promise<void>): Promise<void> {
  let i = 0;
  const workers = Array.from({ length: Math.min(limit, items.length) }, async () => {
    while (i < items.length) {
      const idx = i++;
      await fn(items[idx]!);
    }
  });
  await Promise.all(workers);
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

async function main() {
  const args = process.argv.slice(2);
  const ARGS_CONHECIDOS = /^(--apply|--pdf=.*|--fonte=(estado|municipio)|--limit=\d+)$/;
  const desconhecido = args.find((a) => !ARGS_CONHECIDOS.test(a));
  if (desconhecido) {
    console.error(`argumento não reconhecido: "${desconhecido}". Aceitos: --apply, --pdf=<path>, --fonte=estado|municipio, --limit=<N>.`);
    process.exit(1);
  }

  const pdfPath = args.find((a) => a.startsWith("--pdf="))?.slice("--pdf=".length);
  const fonte = args.find((a) => a.startsWith("--fonte="))?.slice("--fonte=".length) as Fonte | undefined;
  const apply = args.includes("--apply");
  const limitArg = args.find((a) => a.startsWith("--limit="))?.slice("--limit=".length);
  const limit = limitArg ? parseInt(limitArg, 10) : null;

  if (!pdfPath || !fonte) {
    console.error("uso: tsx src/import-depre-pdf.ts --pdf=<arquivo.pdf> --fonte=estado|municipio [--apply] [--limit=N]");
    process.exit(1);
  }

  // parse+checksum não precisam de banco — só autentica se for de fato escrever, pra permitir
  // validar o parser offline (ex.: máquina local sem credenciais de produção).
  if (apply) {
    assertConfig();
    await ensureAuth();
  }

  console.log(`import-depre-pdf: extraindo texto de ${pdfPath} (pdftotext -layout)...`);
  const texto = extrairTexto(pdfPath);
  console.log(`  ${texto.split("\n").length} linhas de texto bruto.`);

  const { linhas, erros, totalGeralPago, totalGeralSaldo } = parseTexto(texto, fonte);
  console.log(`\n${linhas.length} precatórios parseados. ${erros.length} linha(s) com erro de parse.`);
  if (erros.length) {
    console.log("  amostra de erros:");
    for (const e of erros.slice(0, 10)) console.log(`    [${e.motivo}] ${e.linha}`);
  }

  const somaPago = linhas.reduce((acc, l) => acc + l.valor_pago, 0);
  // TJSP zera saldo negativo (crédito/superpagamento, marcado com "*" no PDF) na hora de somar
  // o TOTAL GERAL, mas mantém o valor real (negativo) na linha individual — confirmado
  // empiricamente comparando com/sem floor(0) contra os totais impressos no PDF. Gravamos o
  // valor real em `saldo_depre` (linhas), mas o checksum precisa replicar o floor pra bater.
  const somaSaldo = linhas.reduce((acc, l) => acc + Math.max(l.saldo_depre, 0), 0);

  console.log("\n=== checksum contra TOTAL GERAL do PDF ===");
  console.log(`  Valor Pago — extraído: ${centavosToMoneyStr(somaPago)} · PDF: ${totalGeralPago !== null ? centavosToMoneyStr(totalGeralPago) : "NÃO ENCONTRADO"}`);
  console.log(`  Saldo      — extraído: ${centavosToMoneyStr(somaSaldo)} · PDF: ${totalGeralSaldo !== null ? centavosToMoneyStr(totalGeralSaldo) : "NÃO ENCONTRADO"}`);

  const checksumOk = totalGeralPago !== null && totalGeralSaldo !== null && somaPago === totalGeralPago && somaSaldo === totalGeralSaldo;
  console.log(`  ${checksumOk ? "✓ bate exatamente" : "✗ NÃO BATE"}`);

  if (!checksumOk) {
    console.error("\nchecksum não bateu — abortando sem gravar nada. Revise o parser antes de tentar de novo.");
    process.exit(1);
  }

  if (!apply) {
    console.log("\nmodo relatório (sem --apply): nada foi gravado.");
    return;
  }

  const paraGravar = limit ? linhas.slice(0, limit) : linhas;
  if (limit) {
    console.log(`\n--limit=${limit}: gravando só uma amostra (smoke test) — NÃO apaga a fonte '${fonte}' primeiro, só testa o insert.`);
  } else {
    console.log(`\nsubstituindo fonte '${fonte}': apagando registros existentes...`);
    const { data: removidos, error: eDel } = await supabase.rpc("precatorios_delete_fonte", { p_fonte: fonte });
    if (eDel) throw new Error(`precatorios_delete_fonte: ${eDel.message}`);
    console.log(`  ${removidos} linha(s) removida(s).`);
  }

  console.log(`gravando ${paraGravar.length} registros em lotes...`);
  const lotes = chunk(paraGravar, 3000);
  let inseridos = 0, erroLotes = 0;
  const t0 = Date.now();
  const { data: run } = await supabase.from("coleta_runs").insert({ rotina: "import_depre_pdf", status: "running" }).select("id").single();

  await runPool(lotes, 3, async (lote) => {
    const { data: n, error } = await supabase.rpc("precatorios_insert_lote", { p_rows: lote });
    if (error) {
      erroLotes++;
      console.error(`  ✗ lote de ${lote.length}: ${error.message}`);
    } else {
      inseridos += (n as number) ?? lote.length;
      console.log(`  lote ok: +${(n as number) ?? lote.length} (total ${inseridos}/${paraGravar.length})`);
    }
  });

  const duracaoMs = Date.now() - t0;
  if (run) {
    await supabase.from("coleta_runs").update({
      status: erroLotes > 0 ? "erro_parcial" : "sucesso",
      finished_at: new Date().toISOString(), itens_ok: inseridos, itens_erro: erroLotes, duracao_ms: duracaoMs,
      detalhe: { fonte, total_parseado: linhas.length, inseridos, erro_lotes: erroLotes, erros_parse: erros.length },
    }).eq("id", run.id);
  }
  console.log(`\n✓ import-depre-pdf (${fonte}): ${inseridos} inseridos · ${erroLotes} lote(s) com erro · ${(duracaoMs / 1000).toFixed(1)}s`);
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
