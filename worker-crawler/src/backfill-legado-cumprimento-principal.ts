// FOR-195 — backfill one-off: sobe o último nível que falta (a AÇÃO PRINCIPAL REAL acima do
// cumprimento) pros incidentes legado (FOR-143) que a FOR-178 já reconciliou até o nível do
// CUMPRIMENTO de sentença. Script descartável — não entra no loop claim/crawl/persist do worker
// principal (ver `fetchProcessoPrincipal` em crawl.ts e `reconcilePrincipalReal` em supabase.ts
// pros detalhes da reconciliação).
//
// Uso: tsx src/backfill-legado-cumprimento-principal.ts --apply [--limit=N]
//
// Sem --apply, o script SEMPRE roda em modo relatório (lista candidatos, nunca escreve, nunca
// bate no e-SAJ) — opt-in explícito pra gravar, não opt-out. --limit=N grava só uma amostra
// (smoke test) antes de rodar os ~24.292 completos.
//
// Candidatos: `processos` rows que hoje representam, por engano, o CUMPRIMENTO como se fosse a
// raiz — identificados via incidentes ainda nomeados `LEGADO-%` que JÁ têm `cumprimento_id`
// preenchido (reconciliados ao nível do cumprimento pela FOR-178, mas não renomeados
// individualmente porque o e-SAJ não devolveu um incidente real com o mesmo numero_depre na
// última vez em que a árvore foi crawleada). A contagem exata deve ser confirmada contra a base
// real pelo MODO RELATÓRIO (abaixo) antes de qualquer --apply — mesma cautela de
// `import-csv-legado.ts`: se o número não bater com o ~24.292 esperado (card FOR-195), pare e
// investigue antes de gravar.
//
// Concorrência=1 (serial, SEM runPool) — aprovado pelo humano: cautela com o e-SAJ e a VPS de 1
// vCPU pra um backfill pontual de ~24k itens, não como rede de segurança contra duplicata (que
// já não existe: o upsert de `processos` por `processo_codigo`, UNIQUE desde a migration FOR-69,
// é atômico por construção — ver reconcilePrincipalReal em supabase.ts).
import { pathToFileURL } from "node:url";
import { getSession } from "./esaj.js";
import { fetchProcessoPrincipal } from "./crawl.js";
import { supabase, ensureAuth, reconcilePrincipalReal, classifyProcesso, cnjNorm } from "./supabase.js";
import { assertConfig, config, sleep } from "./config.js";

export interface Candidato {
  processoId: string;
  processoCodigo: string;
  foro: string;
}

function chunk<T>(arr: T[], size: number): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/** 2 queries em lote (sem join embutido do supabase-js — tipagem frágil sem generated types;
 * sem N+1 — lotes de 500 ids via .in()): 1) distinct processo_id de incidentes ainda `LEGADO-%`
 * com `cumprimento_id` preenchido (reconciliados ao nível do cumprimento, FOR-178); 2) os
 * `processos` correspondentes. */
export async function buscarCandidatos(): Promise<Candidato[]> {
  const { data: incs, error: eInc } = await supabase
    .from("incidentes").select("processo_id")
    .like("processo_codigo", "LEGADO-%").not("cumprimento_id", "is", null);
  if (eInc) throw new Error(`buscarCandidatos (incidentes): ${eInc.message}`);

  const processoIds = [...new Set((incs ?? []).map((r) => (r as { processo_id: string }).processo_id))];
  const candidatos: Candidato[] = [];
  for (const lote of chunk(processoIds, 500)) {
    const { data, error } = await supabase.from("processos").select("id, processo_codigo, foro").in("id", lote);
    if (error) throw new Error(`buscarCandidatos (processos): ${error.message}`);
    for (const row of (data ?? []) as Array<{ id: string; processo_codigo: string; foro: string | null }>) {
      candidatos.push({ processoId: row.id, processoCodigo: row.processo_codigo, foro: row.foro ?? "" });
    }
  }
  return candidatos;
}

async function main() {
  const args = process.argv.slice(2);
  const ARGS_CONHECIDOS = /^(--apply|--dry-run|--limit=\d+)$/;
  const desconhecido = args.find((a) => !ARGS_CONHECIDOS.test(a));
  if (desconhecido) {
    console.error(`argumento não reconhecido: "${desconhecido}". Aceitos: --apply, --limit=<N>.`);
    process.exit(1);
  }

  const apply = args.includes("--apply");
  const limitArg = args.find((a) => a.startsWith("--limit="))?.slice("--limit=".length);
  const limit = limitArg ? parseInt(limitArg, 10) : null;
  if (limitArg && (!Number.isFinite(limit) || (limit as number) <= 0)) {
    console.error(`--limit inválido: "${limitArg}" (precisa ser inteiro positivo).`);
    process.exit(1);
  }

  assertConfig();
  await ensureAuth();

  console.log("backfill-legado-cumprimento-principal: consultando candidatos...");
  const candidatos = await buscarCandidatos();
  console.log(`  ${candidatos.length} processos candidatos (esperado ~24.292 — confira antes de --apply se divergir muito).`);
  console.log("\namostra:");
  console.log(candidatos.slice(0, 10).map((c) => `    ${c.processoId} · ${c.processoCodigo} · foro=${c.foro}`).join("\n") || "    (nenhum)");

  if (!apply) {
    console.log("\nmodo relatório (sem --apply): nada foi gravado, nenhum fetch ao e-SAJ foi feito.");
    return;
  }

  const paraProcessar = limit ? candidatos.slice(0, limit) : candidatos;
  if (limit) console.log(`\n--limit=${limit}: processando só uma amostra (smoke test), não os ${candidatos.length} completos.`);
  console.log(`\nprocessando ${paraProcessar.length} candidatos (concorrência=1, serial)...`);

  const { data: run } = await supabase.from("coleta_runs").insert({ rotina: "backfill_legado_principal", status: "running" }).select("id").single();
  const t0 = Date.now();
  let session = await getSession();
  let achados = 0, jaEraRaiz = 0, erro = 0, processados = 0;
  const erros: Array<{ processoCodigo: string; erro: string }> = [];

  try {
    for (const c of paraProcessar) {
      try {
        const principal = await fetchProcessoPrincipal(c.processoCodigo, c.foro, session);
        if (!principal) {
          jaEraRaiz++; // regra da FOR-196: já é a raiz, nada a fazer.
        } else {
          const principalId = await reconcilePrincipalReal(c.processoId, principal);
          await classifyProcesso(principalId);
          achados++;
          console.log(`  ✓ ${c.processoCodigo} -> principal ${principal.processo_codigo} (cnj=${principal.cnj}, norm=${cnjNorm(principal.cnj)})`);
        }
      } catch (e) {
        erro++;
        erros.push({ processoCodigo: c.processoCodigo, erro: String(e) });
        console.error(`  ✗ ${c.processoCodigo}: ${String(e)}`);
        if (/HTTP (429|5\d\d)/.test(String(e))) session = await getSession(); // sessão provavelmente morta
      }
      processados++;
      if (processados % 500 === 0) console.log(`  processados=${processados}/${paraProcessar.length} achados=${achados} já_raiz=${jaEraRaiz} erro=${erro}`);
      await sleep(config.delayMs);
    }

    const duracaoMs = Date.now() - t0;
    if (run) {
      await supabase.from("coleta_runs").update({
        status: erro > 0 ? "erro_parcial" : "sucesso",
        finished_at: new Date().toISOString(), itens_ok: achados + jaEraRaiz, itens_erro: erro, duracao_ms: duracaoMs,
        detalhe: { total: paraProcessar.length, achados, jaEraRaiz, erro, erros: erros.slice(0, 50) },
      }).eq("id", run.id);
    }
    console.log(`\n✓ backfill-legado-cumprimento-principal: ${achados} achados (nova ação principal) · ${jaEraRaiz} já eram raiz (FOR-196) · ${erro} erro(s) · ${(duracaoMs / 1000).toFixed(1)}s`);
    if (erros.length) console.log(`  primeiros erros: ${JSON.stringify(erros.slice(0, 5), null, 2)}`);
  } catch (fatal) {
    if (run) await supabase.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { erro: String(fatal) } }).eq("id", run.id);
    throw fatal;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
