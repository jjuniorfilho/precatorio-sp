// FOR-71 — Worker crawler e-SAJ. Loop: claim → crawl → persist → classify → complete/fail.
import { config, assertConfig, sleep } from "./config.js";
import { getSession, getRequisitorioSession, isDepre } from "./esaj.js";
import { crawlSeed, crawlRequisitorio } from "./crawl.js";
import { supabase, ensureAuth, claimJobs, completeJob, failJob, classifyProcesso, persistTree, persistRequisitorio, enqueueJob, resetOrfaosCrawlerQueue } from "./supabase.js";
import { startHttpServer } from "./http-server.js";
import type { QueueJob } from "./types.js";

async function rotinaHabilitada(): Promise<boolean> {
  const { data } = await supabase.from("coleta_config").select("enabled").eq("rotina", "crawler_esaj").maybeSingle();
  return data ? (data as { enabled: boolean }).enabled : true; // default ligado
}

const ORFAO_LIMITE_MIN = 60; // 1h — nenhum job legítimo fica "processando" tanto tempo

/** Self-heal: jobs travados em "processando" nunca são reclamados de novo por
 * claim_crawler_jobs (que só pega "pendente") — acontece quando o worker morre no meio de
 * um lote (ex.: pm2 max-memory-restart). Reseta pra "pendente" na subida. Via RPC (não
 * UPDATE direto): RLS bloqueia escrita em crawler_queue quando o worker roda sem
 * service_role (anon key + login admin) — confirmado em produção (ver commit). */
async function selfHealOrfaos(): Promise<number> {
  try {
    const n = await resetOrfaosCrawlerQueue(ORFAO_LIMITE_MIN);
    if (n > 0) console.log(`[self-heal] ${n} job(s) "processando" órfão(s) resetado(s) pra "pendente"`);
    return n;
  } catch (err) {
    console.error("[self-heal] erro ao resetar órfãos:", err);
    return 0;
  }
}

/** FOR-108: registra cada subida do processo em coleta_runs — dá histórico de restart
 * visível no admin (hoje só dava pra ver via `pm2 describe` na VPS). */
async function logStartup(orfaosResetados: number): Promise<void> {
  await supabase.from("coleta_runs").insert({
    rotina: "worker_startup", status: "sucesso",
    started_at: new Date().toISOString(), finished_at: new Date().toISOString(),
    itens_ok: 0, itens_erro: 0, duracao_ms: 0,
    detalhe: { orfaos_resetados: orfaosResetados },
  }).then(() => {}, () => {});
}

/** FOR-116 — teto de tempo geral por job (não confundir com o timeout por requisição
 * HTTP individual em esaj.ts). Não cancela o trabalho em andamento de verdade (o
 * fetch/DB call "perdedor" continua rodando em segundo plano até resolver sozinho) —
 * mas libera a vaga do pool pra seguir pro próximo job, que é o que evita um
 * mega-processo travar o lote inteiro. */
class JobTimeoutError extends Error {}

function withJobTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new JobTimeoutError(`job excedeu o teto de ${ms}ms`)), ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
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
      await withJobTimeout((async () => {
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
          if (tree.cnj && isDepre(tree.cnj)) {
            // O seed não era .0500, mas o "climb" por link de Processo Principal (dentro de
            // crawlSeed/normalizeToRoot) subiu até um requisitório .0500 — a checagem de
            // isDepre() lá em cima só olha o seed original, não a raiz resolvida. Sem essa
            // segunda checagem aqui, esse .0500 seria persistido como processo raiz via
            // persistTree, violando a regra do FOR-70 (nenhum .0500 é principal). Em vez
            // disso, reenfileira como requisitório de verdade — a próxima claim cai no ramo
            // isDepre() acima e persiste corretamente em djen_depre.
            await enqueueJob(tree.cnj, "manual");
          } else {
            const processoId = await persistTree(tree);
            await classifyProcesso(processoId);
          }
        }
      })(), config.jobTimeoutMs);
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

// Circuit breaker: quando o TJSP fica fora do ar (retorna 200 com página de manutenção em
// vez de 429/5xx), fetchHtml não tem o que reter­tar — cada job falha em segundos e o
// worker reivindicaria o lote inteiro em ritmo altíssimo, queimando `tentativas` da fila e
// (suspeita, ver sessão FOR-107) estressando memória/conexões o bastante pra derrubar o
// processo. Detecta taxa de erro muito alta num lote e pausa em vez de continuar batendo.
const CIRCUITO_TAXA_ERRO = 0.8; // 80%+
const CIRCUITO_LOTE_MINIMO = 10; // não dispara em lotes pequenos (ruído estatístico)
const CIRCUITO_COOLDOWN_MS = 10 * 60 * 1000; // 10min

async function tick(): Promise<{ processed: number; circuitoAberto: boolean }> {
  if (!(await rotinaHabilitada())) {
    console.log("[paused] crawler_esaj desabilitado em coleta_config");
    return { processed: 0, circuitoAberto: false };
  }
  const jobs = await claimJobs(config.claimBatch);
  if (jobs.length === 0) return { processed: 0, circuitoAberto: false };

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

  const taxaErro = erro / jobs.length;
  const circuitoAberto = jobs.length >= CIRCUITO_LOTE_MINIMO && taxaErro >= CIRCUITO_TAXA_ERRO;
  if (circuitoAberto) {
    // FOR-108: log do disparo do circuit breaker em coleta_runs — antes só existia no
    // console/pm2 logs, sem histórico visível no admin.
    await supabase.from("coleta_runs").insert({
      rotina: "circuit_breaker", status: "erro_parcial",
      started_at: startedAt, finished_at: new Date().toISOString(),
      itens_ok: ok, itens_erro: erro, duracao_ms: Date.now() - t0,
      detalhe: { taxa_erro: Math.round(taxaErro * 1000) / 10, lote: jobs.length, cooldown_ms: CIRCUITO_COOLDOWN_MS },
    }).then(() => {}, () => {});
  }
  return { processed: jobs.length, circuitoAberto };
}

async function main(): Promise<void> {
  assertConfig();
  await ensureAuth();
  // Self-heal: reinícios (ex.: max-memory-restart do pm2) deixam runs "running"
  // órfãos. Na subida, fecha os pendentes do crawler como erro.
  await supabase.from("coleta_runs")
    .update({ status: "erro", finished_at: new Date().toISOString() })
    .eq("rotina", "crawler_esaj").eq("status", "running");
  const orfaosResetados = await selfHealOrfaos();
  await logStartup(orfaosResetados);
  console.log(`worker-crawler iniciando · batch=${config.claimBatch} conc=${config.concurrency} loop=${config.loopEnabled}`);

  // FOR-102: endpoint HTTP roda no mesmo processo, em paralelo ao loop de coleta —
  // não bloqueia nem é bloqueado por ele (event loop do Node cuida disso sozinho).
  startHttpServer();

  if (!config.loopEnabled) { await tick(); return; }

  // loop contínuo; quando a fila esvazia, dorme POLL_EMPTY_MS
  for (;;) {
    let processed = 0, circuitoAberto = false;
    try {
      ({ processed, circuitoAberto } = await tick());
    } catch (err) {
      console.error("[tick] erro:", err);
    }
    if (circuitoAberto) {
      console.log(`[circuit-breaker] taxa de erro >= ${CIRCUITO_TAXA_ERRO * 100}% — TJSP provavelmente fora do ar, pausando ${CIRCUITO_COOLDOWN_MS / 60000}min`);
      await sleep(CIRCUITO_COOLDOWN_MS);
    } else if (processed === 0) {
      await sleep(config.pollEmptyMs);
    }
  }
}

main().catch((err) => {
  console.error("fatal:", err);
  process.exit(1);
});
