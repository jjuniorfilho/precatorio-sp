// Descobre TODOS os processos de um advogado via busca direta no cpopg por OAB
// (cbPesquisa=NUMOAB, "todos os foros") e enfileira. Complementa (não substitui)
// o ingest-oab.ts baseado em Comunica/DJEN: aquele só acha processos com alguma
// publicação eletrônica citando o OAB; este lê direto o cadastro de partes do
// TJSP, então pega também casos antigos/sem publicação sob esse OAB. Confirmado
// em produção: 268 processos via cpopg×OAB contra 230 "normais" via Comunica pro
// mesmo advogado (ver .claude/sessions — investigação 2026-09-08).
//
// Ao contrário do ingest-oab.ts, roda de qualquer IP (cpopg é público/deslogado;
// quem bloqueia por IP de datacenter é o Comunica/PJe, não o e-SAJ).
//
// Uso:
//   tsx src/ingest-oab-cpopg.ts --oab=185164 --uf=SP
//   tsx src/ingest-oab-cpopg.ts --oab=185164 --uf=SP --priorizar   (também bumpa scheduled_at)
//   tsx src/ingest-oab-cpopg.ts --oab=185164 --uf=SP --forcar --priorizar
//     --forcar: insere direto na fila em vez de enqueue_crawler_job — processos já
//     'ok' são pulados por essa RPC (next_crawl_at ainda no futuro). Usar depois de um
//     fix no parser (ex.: FOR-157, credores conjuntos) pra reprocessar o que já foi
//     crawleado sem esperar o próximo ciclo natural de refresh.
import { supabase, ensureAuth } from "./supabase.js";
import { getOabSession, searchByOab, nextPageOab, totalPaginasOab, isDepre, naoDistribuido } from "./esaj.js";
import { config, sleep, assertConfig } from "./config.js";

const CNJ_RE = /\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}/g;

function extractCnjs(html: string): string[] {
  return [...new Set([...html.matchAll(CNJ_RE)].map((m) => m[0]))];
}

function arg(name: string): string | undefined {
  const p = process.argv.find((a) => a.startsWith(`--${name}=`));
  return p ? p.split("=")[1] : undefined;
}

async function main() {
  assertConfig();
  await ensureAuth();
  const sb = supabase as any;

  const oab = arg("oab");
  const uf = (arg("uf") ?? "SP").toUpperCase();
  const priorizar = process.argv.includes("--priorizar");
  const forcar = process.argv.includes("--forcar");
  if (!oab) { console.error("uso: tsx src/ingest-oab-cpopg.ts --oab=NNNNNN --uf=SP [--priorizar] [--forcar]"); process.exit(1); }
  const oabNormalizada = `${oab}${uf}`;

  console.log(`ingest-oab-cpopg: OAB ${oab}/${uf} (busca direta no cpopg, todos os foros)`);
  const { data: run } = await sb.from("coleta_runs").insert({ rotina: "ingest_oab_cpopg", status: "running" }).select("id").single();

  const t0 = Date.now();
  try {
    const session = await getOabSession();
    const p1 = await searchByOab(oabNormalizada, session);
    const totalProcessos = p1.totalProcessos;
    const totalPaginas = totalPaginasOab(totalProcessos);
    console.log(`  ${totalProcessos} processos encontrados · ${totalPaginas} páginas`);

    const seen = new Set<string>(extractCnjs(p1.html));
    console.log(`  pág 1: +${seen.size}`);

    for (let pagina = 2; pagina <= totalPaginas; pagina++) {
      await sleep(config.delayMs);
      const pg = await nextPageOab(oabNormalizada, pagina, session);
      const antes = seen.size;
      for (const cnj of extractCnjs(pg.html)) seen.add(cnj);
      console.log(`  pág ${pagina}: +${seen.size - antes} (distintos até agora: ${seen.size})`);
    }

    let enfileirados = 0, naoDistribuidoCount = 0, depreCount = 0;
    const cnjsValidos: string[] = [];
    for (const cnj of seen) {
      if (naoDistribuido(cnj)) { naoDistribuidoCount++; continue; }
      if (isDepre(cnj)) depreCount++;
      cnjsValidos.push(cnj);
      if (forcar) {
        // Ignora o guard de next_crawl_at do enqueue_crawler_job (sql/2026-09-12_
        // forcar_recrawl_processos.sql — aplicar no SQL Editor antes de usar --forcar).
        const { error } = await sb.rpc("enqueue_crawler_job_forcado", { p_processo_codigo: cnj, p_origem: "manual" });
        if (!error) enfileirados++;
      } else {
        const { error } = await sb.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: "manual" });
        if (!error) enfileirados++;
      }
    }

    let priorizados = 0;
    if (priorizar && cnjsValidos.length) {
      const { data, error } = await sb.rpc("priorizar_jobs_manual", { p_numeros: cnjsValidos });
      if (error) console.error("  priorizar_jobs_manual falhou:", error);
      else priorizados = data ?? 0;
    }

    if (run) {
      await sb.from("coleta_runs").update({
        status: "sucesso", finished_at: new Date().toISOString(), itens_ok: enfileirados, duracao_ms: Date.now() - t0,
        detalhe: { oab, uf, totalProcessos, distintos: seen.size, enfileirados, depre: depreCount, nao_distribuido: naoDistribuidoCount, priorizados },
      }).eq("id", run.id);
    }
    console.log(`\n✓ OAB ${oab}/${uf}: ${totalProcessos} processos (cpopg) · ${seen.size} CNJs distintos · ${enfileirados} enfileirados (${depreCount} .0500)${priorizar ? ` · ${priorizados} priorizados` : ""}`);
  } catch (err) {
    if (run) await sb.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { oab, uf, erro: String(err) } }).eq("id", run.id);
    throw err;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
