// FOR-143 — import one-off do dump CSV legado de precatórios (precatorio_sp_202608161955.csv)
// pra preencher lacunas na base própria. Compara contra processos/incidentes existentes e
// insere só o que falta (nunca sobrescreve). Script descartável — não é feature reutilizável.
//
// Uso: tsx src/import-csv-legado.ts --apply [--csv=../precatorio_sp_202608161955.csv] [--limit=N]
//
// Sem --apply, o script SEMPRE roda em modo relatório (leitura + filtro de completude + match
// em lote + amostra), nunca escreve — opt-in explícito pra gravar, não opt-out (--dry-run ainda
// é aceito como no-op só por clareza/compat, mas não é ele quem decide).
import { readFileSync } from "node:fs";
import { createHash } from "node:crypto";
import { pathToFileURL } from "node:url";
import { supabase, ensureAuth, upsertReturningId, classifyProcesso, enqueueJob } from "./supabase.js";
import { assertConfig, config } from "./config.js";
import { classifyEsfera } from "./parse.js";

const COLS_OBRIGATORIAS = ["origin_process_number", "incident_number", "depre_number"] as const;

export interface LinhaCsv {
  depre_number: string;
  creditor_name: string;
  creditor_document: string;
  creditor_total_amount: string;
  update_base_date: string;
  order_number: string;
  oc_number: string;
  origin_process_number: string;
  incident_number: string;
  debtor_entity: string;
  decision_date: string;
}

export interface LinhaCandidata {
  linha: LinhaCsv;
  cnjRaiz: string;
  cnjNorm: string;
  numeroIncidente: string;
  numeroDepre: string;
}

/** Parser simples de 1 linha CSV (RFC4180: aspas duplas, "" escapa aspas, vírgula dentro de
 * aspas não separa campo). O dump inteiro já foi validado sem quebra de linha dentro de campo
 * (contagem de linhas do arquivo bate com contagem de registros via csv.reader do Python). */
export function parseCsvLine(line: string): string[] {
  const out: string[] = [];
  let cur = "";
  let inQuotes = false;
  for (let i = 0; i < line.length; i++) {
    const ch = line[i]!;
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') { cur += '"'; i++; } else { inQuotes = false; }
      } else {
        cur += ch;
      }
    } else if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      out.push(cur);
      cur = "";
    } else {
      cur += ch;
    }
  }
  out.push(cur);
  return out;
}

function lerCsv(path: string): LinhaCsv[] {
  const raw = readFileSync(path, "utf8");
  const linhas = raw.split("\n").filter((l) => l.length > 0);
  const header = parseCsvLine(linhas[0]!);
  const idx = (col: string) => {
    const i = header.indexOf(col);
    if (i === -1) throw new Error(`coluna "${col}" não encontrada no CSV (header: ${header.join(",")})`);
    return i;
  };
  const cols = {
    depre_number: idx("depre_number"),
    creditor_name: idx("creditor_name"),
    creditor_document: idx("creditor_document"),
    creditor_total_amount: idx("creditor_total_amount"),
    update_base_date: idx("update_base_date"),
    order_number: idx("order_number"),
    oc_number: idx("oc_number"),
    origin_process_number: idx("origin_process_number"),
    incident_number: idx("incident_number"),
    debtor_entity: idx("debtor_entity"),
    decision_date: idx("decision_date"),
  };
  return linhas.slice(1).map((l) => {
    const c = parseCsvLine(l);
    const get = (i: number) => (c[i] ?? "").trim();
    return {
      depre_number: get(cols.depre_number),
      creditor_name: get(cols.creditor_name),
      creditor_document: get(cols.creditor_document),
      creditor_total_amount: get(cols.creditor_total_amount),
      update_base_date: get(cols.update_base_date),
      order_number: get(cols.order_number),
      oc_number: get(cols.oc_number),
      origin_process_number: get(cols.origin_process_number),
      incident_number: get(cols.incident_number),
      debtor_entity: get(cols.debtor_entity),
      decision_date: get(cols.decision_date),
    };
  });
}

export const cnjNorm = (cnj: string) => cnj.replace(/\D/g, "");

// numero_incidente vem com padding diferente conforme a fonte: DB (crawler e-SAJ) usa 5
// dígitos ("00003"), CSV legado usa 4 ("0003") — compara pelo valor numérico, não string.
export const normIncidente = (s: string | null) => (s ? String(parseInt(s, 10)) : "");

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

const md5 = (s: string) => createHash("md5").update(s).digest("hex");
const pad5 = (s: string) => s.padStart(5, "0");

/** Mesmo padrão de src/index.ts (não exportado de lá — cada script CLI é standalone). */
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

/** valor em centavos, validado — CSV é sempre ponto decimal (ex.: "1234.56"). Se algum export
 * futuro vier em pt-BR ("1234,56") ou outro formato inesperado, aborta a linha em vez de gravar
 * um valor truncado/errado silenciosamente (achado do code-review: Math.round(parseFloat(...))
 * sem validação aceitava qualquer lixo). */
export function parseValorCentavos(raw: string): number | null {
  if (!raw) return null;
  if (!/^\d+(\.\d+)?$/.test(raw)) throw new Error(`valor monetário em formato inesperado: "${raw}"`);
  const centavos = Math.round(parseFloat(raw) * 100);
  if (!Number.isFinite(centavos)) throw new Error(`valor monetário inválido: "${raw}"`);
  return centavos;
}

/** Insere processo+incidente+partes+andamentos sintéticos (se houver evidência de ofício) e
 * classifica. Se `processoRealId` for informado (já existe uma linha REAL — não-LEGADO — pra
 * esse cnj_normalizado, achada pelo próprio match em lote), reusa esse processo em vez de criar
 * um placeholder LEGADO- duplicado (achado real do code-review: sem isso, qualquer CNJ que o
 * crawler já tivesse descoberto organicamente, mas com um incidente nesse CSV ainda ausente,
 * ganhava uma segunda linha `processos` pro mesmo CNJ). Retorna o processoId (pra dedupe do
 * classify_processo em lote no caller, em vez de chamar 1x por linha). */
async function inserirLinha(c: LinhaCandidata, processoRealId: string | null): Promise<string> {
  const { linha } = c;
  if (c.cnjNorm.length !== 20) throw new Error(`cnjRaiz malformado: "${c.cnjRaiz}" (cnj_normalizado com ${c.cnjNorm.length} dígitos, esperado 20)`);
  const incidenteCodigoLegado = `LEGADO-${c.cnjNorm}-${pad5(c.numeroIncidente)}`;
  const debtor = linha.debtor_entity || null;

  let processoId: string;
  if (processoRealId) {
    // processo real já existe (crawleado organicamente) — só reusa o id, não mexe nos campos
    // (dado real sempre prevalece sobre o CSV).
    processoId = processoRealId;
  } else {
    processoId = await upsertReturningId("processos", {
      processo_codigo: `LEGADO-${c.cnjNorm}`,
      cnj: c.cnjRaiz,
      cnj_normalizado: c.cnjNorm,
      flag_sp: true,
      ente_nome: debtor,
      ente_esfera: debtor ? classifyEsfera(debtor) : null,
      status: null,
      last_crawled_at: null,
      next_crawl_at: null,
    }, "processo_codigo");
  }

  const valorAcao = parseValorCentavos(linha.creditor_total_amount);
  const incidenteId = await upsertReturningId("incidentes", {
    processo_id: processoId,
    processo_codigo: incidenteCodigoLegado,
    numero_incidente: pad5(c.numeroIncidente),
    tipo_previsto: "Indefinido",
    numero_depre: c.numeroDepre,
    cnj: c.cnjRaiz,
    cnj_normalizado: c.cnjNorm,
    status: null,
    valor_acao: valorAcao,
    data_base: linha.update_base_date || null,
  }, "processo_codigo");

  // partes não é upsert (não tem chave natural própria) — apaga as que este script já tinha
  // gravado antes de reinserir, senão uma re-execução (ex.: o mesmo par processo+incidente com
  // 2 numero_depre diferentes no CSV) duplica linhas a cada rodada. e-SAJ real, quando chegar,
  // já apaga tudo de novo e substitui (persistTree), então isso não conflita com aquele fluxo.
  const { error: eDel } = await supabase.from("partes").delete().eq("incidente_id", incidenteId).eq("fonte", "csv_legado");
  if (eDel) throw new Error(`delete partes (idempotência): ${eDel.message}`);

  const documento = linha.creditor_document.replace(/\D/g, "") || null;
  const partesRows: Record<string, unknown>[] = [{
    incidente_id: incidenteId, processo_id: processoId, papel: "ativa",
    nome: linha.creditor_name || null, documento, sem_oab: false, fonte: "csv_legado",
  }];
  if (debtor) {
    partesRows.push({
      incidente_id: incidenteId, processo_id: processoId, papel: "passiva",
      nome: debtor, sem_oab: false, fonte: "csv_legado",
    });
  }
  const { error: ePartes } = await supabase.from("partes").insert(partesRows);
  if (ePartes) throw new Error(`insert partes: ${ePartes.message}`);

  // evidência de ofício expedido → termo (sempre precede) + ofício, casando com
  // classificacao_regras existentes ('%ofício requisitório%expedido%', '%termo de declaraç%')
  if (linha.oc_number || linha.order_number) {
    const data = linha.decision_date ? linha.decision_date.slice(0, 10) : null;
    const andamentos = [
      { incidente_id: incidenteId, data, descricao: "Termo de declaração de crédito (importado — CSV legado)", arquivo_url: null },
      { incidente_id: incidenteId, data, descricao: "Ofício requisitório expedido (importado — CSV legado)", arquivo_url: null },
    ].map((a) => ({ ...a, hash: md5(`${a.data ?? ""}|${a.descricao}|${a.arquivo_url ?? ""}`) }));
    const { error: eAnd } = await supabase.from("andamentos").upsert(andamentos, { onConflict: "incidente_id,hash", ignoreDuplicates: true });
    if (eAnd) throw new Error(`upsert andamentos: ${eAnd.message}`);
  }

  return processoId;
}

// nem cnj_normalizado (processos) nem numero_depre (incidentes) têm UNIQUE no schema —
// confirmado na prática: o mesmo numero_depre pode aparecer em 2 incidentes distintos (achado
// no teste de idempotência da FASE 6). Por isso os dois mapas guardam TODAS as linhas
// encontradas, não só a última — um Map<chave, valor único> perderia matches por colisão.
/** Agrupa `rows` por `chave(row)`, preservando TODAS as ocorrências por chave (nunca sobrescreve
 * a anterior). Extraído como função pura pra poder testar isoladamente a regressão da FASE 6:
 * antes disso, o código montava `Map<chave, valor único>` e uma colisão de chave (ex.:
 * numero_depre repetido em 2 incidentes de processos diferentes) perdia o match certo. Linhas
 * sem chave (`chave(row)` retorna null/"") são ignoradas. */
export function agruparPorChave<T>(rows: T[], chave: (row: T) => string | null | undefined): Map<string, T[]> {
  const out = new Map<string, T[]>();
  for (const row of rows) {
    const k = chave(row);
    if (!k) continue;
    const arr = out.get(k) ?? [];
    arr.push(row);
    out.set(k, arr);
  }
  return out;
}

function mergeGrupos<T>(out: Map<string, T[]>, grupo: Map<string, T[]>): void {
  for (const [k, vs] of grupo) out.set(k, [...(out.get(k) ?? []), ...vs]);
}

async function buscarProcessosPorCnjNorm(cnjNorms: string[]): Promise<Map<string, Array<{ id: string; processoCodigo: string }>>> {
  const out = new Map<string, Array<{ id: string; processoCodigo: string }>>(); // cnj_normalizado -> linhas
  for (const lote of chunk([...new Set(cnjNorms)], 500)) {
    const { data, error } = await supabase.from("processos").select("id, cnj_normalizado, processo_codigo").in("cnj_normalizado", lote);
    if (error) throw new Error(`select processos: ${error.message}`);
    const rows = ((data ?? []) as Array<{ id: string; cnj_normalizado: string | null; processo_codigo: string }>)
      .map((row) => ({ id: row.id, processoCodigo: row.processo_codigo, chave: row.cnj_normalizado }));
    mergeGrupos(out, agruparPorChave(rows, (r) => r.chave));
  }
  return out;
}

async function buscarIncidentesPorDepre(numeroDepres: string[]): Promise<Map<string, Array<{ processo_id: string; numero_incidente: string | null }>>> {
  const out = new Map<string, Array<{ processo_id: string; numero_incidente: string | null }>>();
  for (const lote of chunk([...new Set(numeroDepres)], 500)) {
    const { data, error } = await supabase.from("incidentes").select("numero_depre, numero_incidente, processo_id").in("numero_depre", lote);
    if (error) throw new Error(`select incidentes: ${error.message}`);
    const rows = (data ?? []) as Array<{ numero_depre: string; numero_incidente: string | null; processo_id: string }>;
    mergeGrupos(out, agruparPorChave(rows, (r) => r.numero_depre));
  }
  return out;
}

/** Separa candidatas do CSV em "já existem" vs. "a inserir" comparando contra os mapas em lote.
 * Extraído como função pura (lógica idêntica à antes inline em `main()`) pra poder testar
 * isoladamente a regressão de colisão de `numero_depre` entre processos distintos (FASE 6):
 * match exige o MESMO `processo_id` nos dois mapas **e** `numero_incidente` batendo (via
 * `normIncidente`, que tolera padding 4 vs. 5 dígitos entre CSV e banco). */
export function separarJaExistemEAInserir(
  candidatas: LinhaCandidata[],
  processosPorCnj: Map<string, Array<{ id: string; processoCodigo: string }>>,
  incidentesPorDepre: Map<string, Array<{ processo_id: string; numero_incidente: string | null }>>,
): { jaExistem: LinhaCandidata[]; aInserir: LinhaCandidata[] } {
  const jaExistem: LinhaCandidata[] = [];
  const aInserir: LinhaCandidata[] = [];
  for (const c of candidatas) {
    const incs = incidentesPorDepre.get(c.numeroDepre) ?? [];
    const processoIds = new Set((processosPorCnj.get(c.cnjNorm) ?? []).map((r) => r.id));
    const match = incs.some((inc) => processoIds.has(inc.processo_id) && normIncidente(inc.numero_incidente) === normIncidente(c.numeroIncidente));
    (match ? jaExistem : aInserir).push(c);
  }
  return { jaExistem, aInserir };
}

/** Resolve, por `cnj_normalizado`, o id do processo REAL (não-`LEGADO-`) já existente, se houver.
 * Extraído como função pura pra testar isoladamente a regressão C3 (import criava `processos`
 * `LEGADO-` duplicado quando um real já existia pro mesmo CNJ, porque `cnj_normalizado` não tem
 * UNIQUE no schema). */
export function resolverProcessoRealPorCnj(processosPorCnj: Map<string, Array<{ id: string; processoCodigo: string }>>): Map<string, string> {
  const out = new Map<string, string>();
  for (const [cnj, rows] of processosPorCnj) {
    const real = rows.find((r) => !r.processoCodigo.startsWith("LEGADO-"));
    if (real) out.set(cnj, real.id);
  }
  return out;
}

/** Enfileira o complemento (backfill) pra todo CNJ com processo_codigo LEGADO-, não só os
 * inseridos NESTA execução — assim o enqueue é re-executável por si só (achado do code-review:
 * enqueueJob só loga erro e não lança; antes disso dependia só do resultado da rodada atual, e
 * uma falha silenciosa de RPC nunca mais seria recuperada numa re-execução, porque a linha já
 * passaria a bater como "já existe" no match). */
async function enfileirarBackfillPendente(): Promise<number> {
  const cnjs: string[] = [];
  for (let offset = 0; ; offset += 1000) {
    const { data, error } = await supabase.from("processos").select("cnj").like("processo_codigo", "LEGADO-%").range(offset, offset + 999);
    if (error) throw new Error(`select processos (enqueue): ${error.message}`);
    if (!data?.length) break;
    for (const row of data as Array<{ cnj: string | null }>) if (row.cnj) cnjs.push(row.cnj);
    if (data.length < 1000) break;
  }
  const unicos = [...new Set(cnjs)];
  await runPool(unicos, config.concurrency, (cnj) => enqueueJob(cnj, "backfill"));
  return unicos.length;
}

async function main() {
  const args = process.argv.slice(2);
  const ARGS_CONHECIDOS = /^(--apply|--dry-run|--csv=.*|--limit=\d+)$/;
  const desconhecido = args.find((a) => !ARGS_CONHECIDOS.test(a));
  if (desconhecido) {
    console.error(`argumento não reconhecido: "${desconhecido}". Aceitos: --apply, --csv=<path>, --limit=<N>.`);
    process.exit(1);
  }

  const apply = args.includes("--apply");
  const csvArg = args.find((a) => a.startsWith("--csv="))?.slice("--csv=".length);
  const csvPath = csvArg ?? "../precatorio_sp_202608161955.csv";
  const limitArg = args.find((a) => a.startsWith("--limit="))?.slice("--limit=".length);
  const limit = limitArg ? parseInt(limitArg, 10) : null; // teste em escala pequena (smoke test)
  if (limitArg && (!Number.isFinite(limit) || (limit as number) <= 0)) {
    console.error(`--limit inválido: "${limitArg}" (precisa ser inteiro positivo).`);
    process.exit(1);
  }

  assertConfig();
  await ensureAuth();

  console.log(`import-csv-legado: lendo ${csvPath}...`);
  const linhas = lerCsv(csvPath);
  console.log(`  ${linhas.length} linhas lidas.`);

  // 1) filtro de completude
  const incompletas: LinhaCsv[] = [];
  const candidatas: LinhaCandidata[] = [];
  let divergenciaIncidente = 0;
  for (const linha of linhas) {
    if (COLS_OBRIGATORIAS.some((col) => !linha[col])) {
      incompletas.push(linha);
      continue;
    }
    const [cnjRaiz, numeroIncidenteDoOrigin] = linha.origin_process_number.split("/");
    if (!cnjRaiz || !numeroIncidenteDoOrigin) {
      incompletas.push(linha);
      continue;
    }
    if (numeroIncidenteDoOrigin !== linha.incident_number) divergenciaIncidente++;
    candidatas.push({
      linha,
      cnjRaiz,
      cnjNorm: cnjNorm(cnjRaiz),
      numeroIncidente: linha.incident_number,
      numeroDepre: linha.depre_number,
    });
  }
  console.log(`  ${incompletas.length} ignoradas (sem origin_process_number/incident_number/depre_number completos).`);
  console.log(`  ${candidatas.length} candidatas (completas).`);
  if (divergenciaIncidente) console.log(`  ⚠ ${divergenciaIncidente} com numero_incidente(origin_process_number) ≠ incident_number (não bloqueia).`);

  // 2) match em lote contra a base
  console.log("\nconsultando base existente...");
  const processosPorCnj = await buscarProcessosPorCnjNorm(candidatas.map((c) => c.cnjNorm));
  const incidentesPorDepre = await buscarIncidentesPorDepre(candidatas.map((c) => c.numeroDepre));
  console.log(`  ${processosPorCnj.size} processos distintos já existentes (por cnj_normalizado das candidatas).`);
  console.log(`  ${incidentesPorDepre.size} incidentes distintos já existentes (por numero_depre das candidatas).`);

  // processo REAL (não-LEGADO) já existente por cnj_normalizado — pra reusar em vez de criar
  // um placeholder duplicado quando o crawler já descobriu esse CNJ organicamente (C3 do
  // code-review: cnj_normalizado não é UNIQUE, então sem isso cada incidente novo desse CSV
  // pra um CNJ já real ganhava uma segunda linha `processos`).
  const processoRealPorCnj = resolverProcessoRealPorCnj(processosPorCnj);

  const { jaExistem, aInserir } = separarJaExistemEAInserir(candidatas, processosPorCnj, incidentesPorDepre);

  const semDevedor = aInserir.filter((c) => !c.linha.debtor_entity).length;

  console.log("\n=== relatório ===");
  console.log(`total lido:        ${linhas.length}`);
  console.log(`ignoradas:         ${incompletas.length}`);
  console.log(`já existem:        ${jaExistem.length}`);
  console.log(`a inserir:         ${aInserir.length}  (${semDevedor} sem debtor_entity → ente_nome/esfera ficarão NULL)`);

  const amostra = (rows: LinhaCandidata[], n = 10) =>
    rows.slice(0, n).map((c) => `    ${c.cnjRaiz}/${c.numeroIncidente} · depre=${c.numeroDepre} · credor="${c.linha.creditor_name}" · devedor="${c.linha.debtor_entity}"`).join("\n");

  console.log("\namostra já existem:");
  console.log(amostra(jaExistem) || "    (nenhuma)");
  console.log("\namostra a inserir:");
  console.log(amostra(aInserir) || "    (nenhuma)");

  if (!apply) {
    console.log("\nmodo relatório (sem --apply): nada foi gravado.");
    return;
  }

  // 3) escrita: processos/incidentes/partes/andamentos/classify, em pool + registro em coleta_runs
  const paraGravar = limit ? aInserir.slice(0, limit) : aInserir;
  if (limit) console.log(`\n--limit=${limit}: gravando só uma amostra (smoke test), não os ${aInserir.length} completos.`);
  console.log(`\ngravando ${paraGravar.length} registros (concorrência=${config.concurrency})...`);
  const t0 = Date.now();
  const { data: run } = await supabase.from("coleta_runs").insert({ rotina: "import_csv_legado", status: "running" }).select("id").single();

  let ok = 0, erro = 0;
  const processosParaClassificar = new Set<string>();
  const erros: Array<{ depre: string; erro: string }> = [];
  let processados = 0;

  try {
    await runPool(paraGravar, config.concurrency, async (c) => {
      try {
        const processoId = await inserirLinha(c, processoRealPorCnj.get(c.cnjNorm) ?? null);
        ok++;
        processosParaClassificar.add(processoId);
      } catch (e) {
        erro++;
        erros.push({ depre: c.numeroDepre, erro: String(e) });
        console.error(`  ✗ ${c.numeroDepre}: ${String(e)}`);
      }
      processados++;
      if (processados % 500 === 0) console.log(`  processados=${processados}/${paraGravar.length} ok=${ok} erro=${erro}`);
    });

    // classify_processo por processo (não por linha) — um CNJ com N incidentes no CSV chamava
    // a RPC N vezes, cada uma reclassificando TODOS os incidentes do processo (O(n²); achado
    // do code-review). Dedup por processoId e roda 1x cada, em pool.
    console.log(`\nclassificando ${processosParaClassificar.size} processos únicos...`);
    await runPool([...processosParaClassificar], config.concurrency, (id) => classifyProcesso(id));

    console.log("\nenfileirando complemento (backfill) — todo LEGADO- pendente, não só desta rodada...");
    const enfileirados = await enfileirarBackfillPendente();

    const duracaoMs = Date.now() - t0;
    if (run) {
      await supabase.from("coleta_runs").update({
        status: erro > 0 ? "erro_parcial" : "sucesso",
        finished_at: new Date().toISOString(), itens_ok: ok, itens_erro: erro, duracao_ms: duracaoMs,
        detalhe: { total: paraGravar.length, ok, erro, enfileirados, erros: erros.slice(0, 50) },
      }).eq("id", run.id);
    }
    console.log(`\n✓ import-csv-legado: ${ok} inseridos · ${erro} erro(s) · ${enfileirados} CNJs enfileirados (backfill) · ${(duracaoMs / 1000).toFixed(1)}s`);
    if (erros.length) console.log(`  primeiros erros: ${JSON.stringify(erros.slice(0, 5), null, 2)}`);
  } catch (fatal) {
    // sem isso, um crash no meio do runPool deixava a linha em coleta_runs presa em "running"
    // pra sempre (achado do code-review).
    if (run) await supabase.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { erro: String(fatal) } }).eq("id", run.id);
    throw fatal;
  }
}

// Só roda main() quando executado diretamente (`tsx src/import-csv-legado.ts`), nunca quando
// importado (ex.: pelos testes unitários das funções puras acima, que não podem disparar
// leitura de CSV/rede/Supabase como efeito colateral de `import`).
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
