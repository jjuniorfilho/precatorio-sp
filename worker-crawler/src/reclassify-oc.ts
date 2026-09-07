// FOR-112 — reclassificação em massa: recalcula ano_oc (agora calculado a partir da data
// de expedição do ofício requisitório, ver sql/2026-07-24_for112_oc_calculado.sql) pros
// ~88k processos existentes. Precisa rodar fora do SQL Editor (mesma ressalva do fix
// FOR-72: um `select classify_all()` roda tudo numa transação só — qualquer falha/timeout
// no meio derruba tudo sem progresso parcial salvo).
//
// classify_processo reclassifica TODOS os incidentes de um processo numa UPDATE só; ~19
// processos "mega" (769 a 8.513 incidentes) estouram timeout mesmo um por vez (mesmo
// problema do fix FOR-72). Fallback automático: se classify_processo falhar, pagina os
// incidente_id do processo via buscar_incidentes_processo e reclassifica em lotes de 100
// via classify_incidentes (escopado por incidente, nunca estoura).
//
// Uso: tsx src/reclassify-oc.ts
import { supabase, ensureAuth, classifyProcesso } from "./supabase.js";
import { config, sleep, assertConfig } from "./config.js";

const PAGE = 500;
const MEGA_BATCH = 100;

async function classificarMegaProcesso(processoId: string): Promise<void> {
  const sb = supabase as any;
  let offset = 0;
  for (;;) {
    const { data: lote, error } = await sb.rpc("buscar_incidentes_processo", {
      p_processo_id: processoId, p_limit: MEGA_BATCH, p_offset: offset,
    });
    if (error) throw new Error(`buscar_incidentes_processo(${processoId}): ${error.message}`);
    const ids = (lote as Array<{ incidente_id: string }>).map((r) => r.incidente_id);
    if (ids.length === 0) break;
    const { error: clsErr } = await sb.rpc("classify_incidentes", { p_incidente_ids: ids });
    if (clsErr) throw new Error(`classify_incidentes(${processoId}, offset=${offset}): ${clsErr.message}`);
    if (ids.length < MEGA_BATCH) break;
    offset += MEGA_BATCH;
  }
}

async function main() {
  assertConfig();
  await ensureAuth();
  const sb = supabase as any;

  console.log("reclassify-oc: recalculando ano_oc pra todos os processos flag_sp...");
  const { data: run } = await sb.from("coleta_runs").insert({ rotina: "reclassify_oc", status: "running" }).select("id").single();

  let cursor = "00000000-0000-0000-0000-000000000000";
  let total = 0, ok = 0, mega = 0, erro = 0;
  const erros: Array<{ processo_id: string; erro: string }> = [];
  const t0 = Date.now();

  try {
    for (;;) {
      const { data: lote, error } = await sb.rpc("listar_processos_para_reclassificar", { p_cursor: cursor, p_limit: PAGE });
      if (error) throw new Error(`erro paginando processos: ${error.message}`);
      if (!lote || lote.length === 0) break;

      for (const row of lote as Array<{ processo_id: string }>) {
        total++;
        try {
          await classifyProcesso(row.processo_id);
          ok++;
        } catch (e1) {
          // provável timeout em processo "mega" — tenta o caminho em lote por incidente.
          try {
            await classificarMegaProcesso(row.processo_id);
            ok++; mega++;
          } catch (e2) {
            erro++;
            erros.push({ processo_id: row.processo_id, erro: String(e2) });
            console.error(`  ✗ ${row.processo_id}: ${String(e2)}`);
          }
        }
      }

      cursor = lote[lote.length - 1].processo_id;
      const elapsedMin = ((Date.now() - t0) / 60000).toFixed(1);
      console.log(`  processados=${total} ok=${ok} (mega=${mega}) erro=${erro} · ${elapsedMin}min`);
      if (lote.length < PAGE) break;
      await sleep(config.delayMs);
    }

    if (run) {
      await sb.from("coleta_runs").update({
        status: erro > 0 ? "sucesso_parcial" : "sucesso",
        finished_at: new Date().toISOString(), itens_ok: ok, itens_erro: erro,
        duracao_ms: Date.now() - t0, detalhe: { total, ok, mega, erro, erros: erros.slice(0, 50) },
      }).eq("id", run.id);
    }
    console.log(`\n✓ reclassify-oc: ${total} processos · ${ok} ok (${mega} via fallback mega) · ${erro} erro(s)`);
    if (erros.length) console.log(`  processo_id com erro: ${erros.map((e) => e.processo_id).join(", ")}`);
  } catch (err) {
    if (run) await sb.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { erro: String(err) } }).eq("id", run.id);
    throw err;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
