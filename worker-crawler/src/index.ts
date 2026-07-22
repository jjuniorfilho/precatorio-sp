// FOR-71 — Worker crawler e-SAJ. Loop: claim → crawl → persist → classify → complete/fail.
import { config, assertConfig, sleep } from "./config.js";
import { getSession, getRequisitorioSession, isDepre } from "./esaj.js";
import { crawlSeed, crawlRequisitorio } from "./crawl.js";
import { supabase, ensureAuth, claimJobs, completeJob, failJob, classifyProcesso, persistTree, persistRequisitorio, enqueueJob } from "./supabase.js";
import { startHttpServer } from "./http-server.js";
import type { QueueJob } from "./types.js";

async function rotinaHabilitada(): Promise<boolean> {
  const { data } = await supabase.from("coleta_config").select("enabled").eq("rotina", "crawler_esaj").maybeSingle();
  return data ? (data as { enabled: boolean }).enabled : true; // default ligado
}

/** Executa fn sobre items com no máximo `limit` em paralelo. */
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

async function processBatch(jobs: QueueJob[]): Promise<{ ok: number; erro: number }> {
  const session = await getSession();
  // Sessão da Consulta de Requisitórios só se houver seed .0500 no lote.
  const reqSession = jobs.some((j) => isDepre(j.processo_codigo)) ? await getRequisitorioSession() : null;
  let ok = 0, erro = 0;

  await runPool(jobs, config.concurrency, async (job) => {
    try {
      if (isDepre(job.processo_codigo)) {
        // Requisitório (.0500): ficha na Consulta de Requisitórios. NUNCA vira processo
        // principal — persiste na tabela DEPRE (djen_depre) com ficha + andamentos, e
        // enfileira a(s) ORIGEM(ns). O vínculo com o principal acontece depois: quando
        // a origem é crawleada, um dos seus incidentes referencia este .0500 (numero_depre).
        const { tree, origem } = await crawlRequisitorio(job.processo_codigo, reqSession ?? undefined);
        await persistRequisitorio(tree, origem);
        // origem do requisitório → cpopg. p_origem deve respeitar crawler_queue_origem_check
        // (valores aceitos: manual/refresh/backfill/caderno_dje). Usa "manual" como a edge.
        for (const cnj of origem) await enqueueJob(cnj, "manual");
      } else {
        const tree = await crawlSeed(job.processo_codigo, session);
        const processoId = await persistTree(tree);
        await classifyProcesso(processoId);
      }
      await completeJob(job.id);
      ok++;
    } catch (err) {
      await failJob(job.id, String(err)).catch(() => {});
      erro++;
      console.error(`[fail] job=${job.id} seed=${job.processo_codigo}:`, err);
    }
    await sleep(config.delayMs);
  });

  return { ok, erro };
}

async function tick(): Promise<number> {
  if (!(await rotinaHabilitada())) {
    console.log("[paused] crawler_esaj desabilitado em coleta_config");
    return 0;
  }
  const jobs = await claimJobs(config.claimBatch);
  if (jobs.length === 0) return 0;

  const startedAt = new Date().toISOString();
  const { data: run } = await supabase
    .from("coleta_runs").insert({ rotina: "crawler_esaj", status: "running", started_at: startedAt })
    .select("id").single();

  const t0 = Date.now();
  const { ok, erro } = await processBatch(jobs);

  if (run) {
    await supabase.from("coleta_runs").update({
      status: erro === 0 ? "sucesso" : ok === 0 ? "erro" : "erro_parcial",
      finished_at: new Date().toISOString(),
      itens_ok: ok, itens_erro: erro, duracao_ms: Date.now() - t0,
    }).eq("id", (run as { id: string }).id);
  }
  console.log(`[batch] claimed=${jobs.length} ok=${ok} erro=${erro} (${Date.now() - t0}ms)`);
  return jobs.length;
}

async function main(): Promise<void> {
  assertConfig();
  await ensureAuth();
  // Self-heal: reinícios (ex.: max-memory-restart do pm2) deixam runs "running"
  // órfãos. Na subida, fecha os pendentes do crawler como erro.
  await supabase.from("coleta_runs")
    .update({ status: "erro", finished_at: new Date().toISOString() })
    .eq("rotina", "crawler_esaj").eq("status", "running");
  console.log(`worker-crawler iniciando · batch=${config.claimBatch} conc=${config.concurrency} loop=${config.loopEnabled}`);

  // FOR-102: endpoint HTTP roda no mesmo processo, em paralelo ao loop de coleta —
  // não bloqueia nem é bloqueado por ele (event loop do Node cuida disso sozinho).
  startHttpServer();

  if (!config.loopEnabled) { await tick(); return; }

  // loop contínuo; quando a fila esvazia, dorme POLL_EMPTY_MS
  for (;;) {
    let processed = 0;
    try {
      processed = await tick();
    } catch (err) {
      console.error("[tick] erro:", err);
    }
    if (processed === 0) await sleep(config.pollEmptyMs);
  }
}

main().catch((err) => {
  console.error("fatal:", err);
  process.exit(1);
});
