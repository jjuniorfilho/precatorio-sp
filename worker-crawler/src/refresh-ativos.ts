// FOR-107 — Varre incidentes com fase >= "calculo" (cálculo homologado ou mais adiantado —
// nunca mais "inicial") e status "ativo", e reenfileira o processo pra recrawl. Mesmos
// critérios de ente público (processos.flag_sp) já usados em toda a coleta; respeita o
// mesmo TTL (processos.next_crawl_at) já usado no refresh por CNJ da edge function
// buscar-precatorio — não reenfileira quem já está agendado pro futuro.
//
// Diferente do ingest-djen/ingest-oab (que DESCOBREM processos novos via DJEN), este script
// REFRESCA processos que já conhecemos e já mostraram progresso real — a hipótese é que
// esses são os que mais valem a pena monitorar de novo (novo andamento, mudança de fase,
// valor atualizado etc.); "inicial" (nenhum marco detectado ainda) fica de fora porque não
// há sinal de que algo tenha mudado.
//
// Uso: tsx src/refresh-ativos.ts
import { supabase, ensureAuth } from "./supabase.js";
import { config, sleep, assertConfig } from "./config.js";

const PAGE = 500;

async function main() {
  assertConfig();
  await ensureAuth();
  const sb = supabase as any;

  console.log("refresh-ativos: varrendo incidentes com fase >= calculo + status ativo...");
  const { data: run } = await sb.from("coleta_runs").insert({ rotina: "refresh_ativos", status: "running" }).select("id").single();

  const cnjsEnfileirados = new Set<string>();
  let cursor = "00000000-0000-0000-0000-000000000000";
  let totalIncidentes = 0, jaAgendados = 0, enfileirados = 0;
  const t0 = Date.now();
  try {
    for (;;) {
      const { data: lote, error } = await sb
        .from("incidentes")
        .select("id, processos!inner(cnj, flag_sp, next_crawl_at)")
        .neq("fase", "inicial")
        .eq("status", "ativo")
        .eq("processos.flag_sp", true)
        .gt("id", cursor)
        .order("id")
        .limit(PAGE);
      if (error) throw new Error(`erro paginando incidentes: ${error.message}`);
      if (!lote || lote.length === 0) break;
      totalIncidentes += lote.length;

      for (const inc of lote as any[]) {
        const proc = inc.processos;
        if (!proc?.cnj) continue;
        // respeita o mesmo TTL do refresh por CNJ (buscar-precatorio) — não reenfileira
        // quem já tem next_crawl_at no futuro.
        if (proc.next_crawl_at && new Date(proc.next_crawl_at).getTime() > Date.now()) { jaAgendados++; continue; }
        if (cnjsEnfileirados.has(proc.cnj)) continue;
        cnjsEnfileirados.add(proc.cnj);
        const { error: enqErr } = await sb.rpc("enqueue_crawler_job", { p_processo_codigo: proc.cnj, p_origem: "refresh" });
        if (!enqErr) enfileirados++;
      }

      cursor = lote[lote.length - 1].id;
      console.log(`  +${lote.length} incidentes (total=${totalIncidentes}, processos distintos enfileirados até agora=${enfileirados})`);
      if (lote.length < PAGE) break;
      await sleep(config.delayMs);
    }

    if (run) {
      await sb.from("coleta_runs").update({
        status: "sucesso", finished_at: new Date().toISOString(), itens_ok: enfileirados,
        duracao_ms: Date.now() - t0, detalhe: { totalIncidentes, enfileirados, jaAgendados },
      }).eq("id", run.id);
    }
    console.log(`\n✓ refresh-ativos: ${totalIncidentes} incidentes elegíveis · ${cnjsEnfileirados.size} processos distintos enfileirados · ${jaAgendados} já com next_crawl_at futuro`);
  } catch (err) {
    if (run) await sb.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { erro: String(err) } }).eq("id", run.id);
    throw err;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
