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
// (smoke test) antes de rodar os ~11.202 completos.
//
// Candidatos: `processos` rows cujo `processo_codigo` ainda é `LEGADO-...` — esses hoje
// representam, por engano, o CUMPRIMENTO como se fosse a raiz (o seed que originou a
// reconciliação da FOR-178 foi o próprio CNJ do cumprimento, nunca um código e-SAJ real).
//
// Achado de code-review (pós-validação manual de um caso real, FOR-195): a versão original desta
// query filtrava por `incidentes.processo_codigo LIKE 'LEGADO-%' AND cumprimento_id IS NOT NULL`
// — um PROXY que só pegava ~200 processos (os já promovidos a código e-SAJ real por algum crawl
// anterior). A população real é `processos.processo_codigo LIKE 'LEGADO-%'` diretamente: ~11.202
// processos, dos quais ~98% têm `cumprimento_id IS NULL` (mesma heurística documentada na FOR-178
// — nunca foram re-crawleados desde a reconciliação ao nível do cumprimento) e por isso ficavam
// de fora do backfill inteiro, silenciosamente. Pra esses, `processo_codigo` não é um código e-SAJ
// válido — só o `cnj` serve de ponto de entrada (ver seleção de seed em `main`, abaixo, e o
// caminho por CNJ em `fetchProcessoPrincipal`, crawl.ts).
//
// A contagem exata deve ser confirmada contra a base real pelo MODO RELATÓRIO (abaixo) antes de
// qualquer --apply — mesma cautela de `import-csv-legado.ts`: se o número não bater com o
// ~11.202 esperado, pare e investigue antes de gravar.
//
// Concorrência=1 (serial, SEM runPool) — aprovado pelo humano: cautela com o e-SAJ e a VPS de 1
// vCPU pra um backfill pontual de ~11k itens, não como rede de segurança contra duplicata (que
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
  cnj: string | null;
  foro: string;
}

/** Paginado (mesmo idiom de `import-csv-legado.ts`: `.range()` em lotes de 1000 — o REST do
 * Supabase tem teto de página, e a população real (~11.202) ultrapassa o default). Direto em
 * `processos`, sem passar por `incidentes`: ver o comentário de topo do arquivo sobre o bug do
 * proxy anterior. */
export async function buscarCandidatos(): Promise<Candidato[]> {
  const candidatos: Candidato[] = [];
  for (let from = 0; ; from += 1000) {
    const { data, error } = await supabase
      .from("processos").select("id, processo_codigo, cnj, foro")
      .like("processo_codigo", "LEGADO-%").range(from, from + 999);
    if (error) throw new Error(`buscarCandidatos: ${error.message}`);
    for (const row of (data ?? []) as Array<{ id: string; processo_codigo: string; cnj: string | null; foro: string | null }>) {
      candidatos.push({ processoId: row.id, processoCodigo: row.processo_codigo, cnj: row.cnj, foro: row.foro ?? "" });
    }
    if (!data || data.length < 1000) break;
  }
  return candidatos;
}

/** `processo_codigo` só serve de seed pro e-SAJ quando já é um código real (não `LEGADO-...`) —
 * caso dos ~200 candidatos que outro crawl anterior já promoveu. Pro resto (~98%), só o CNJ é um
 * ponto de entrada válido; `fetchProcessoPrincipal` aceita os dois (ver crawl.ts). `null` = sem
 * seed utilizável (nem código real, nem cnj conhecido) — candidato é pulado e contado à parte. */
export function seedDoCandidato(c: Candidato): string | null {
  return c.processoCodigo.startsWith("LEGADO-") ? c.cnj : c.processoCodigo;
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
  console.log(`  ${candidatos.length} processos candidatos (esperado ~11.202 — confira antes de --apply se divergir muito).`);
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
  let achados = 0, jaEraRaiz = 0, erro = 0, semSeed = 0, processados = 0;
  const erros: Array<{ processoCodigo: string; erro: string }> = [];

  try {
    for (const c of paraProcessar) {
      const seed = seedDoCandidato(c);
      if (!seed) {
        semSeed++; // nem código e-SAJ real, nem cnj conhecido — não há como buscar no e-SAJ.
        processados++;
        continue;
      }
      try {
        const principal = await fetchProcessoPrincipal(seed, c.foro, session);
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
      if (processados % 500 === 0) console.log(`  processados=${processados}/${paraProcessar.length} achados=${achados} já_raiz=${jaEraRaiz} sem_seed=${semSeed} erro=${erro}`);
      await sleep(config.delayMs);
    }

    const duracaoMs = Date.now() - t0;
    if (run) {
      await supabase.from("coleta_runs").update({
        status: erro > 0 ? "erro_parcial" : "sucesso",
        finished_at: new Date().toISOString(), itens_ok: achados + jaEraRaiz, itens_erro: erro, duracao_ms: duracaoMs,
        detalhe: { total: paraProcessar.length, achados, jaEraRaiz, semSeed, erro, erros: erros.slice(0, 50) },
      }).eq("id", run.id);
    }
    console.log(`\n✓ backfill-legado-cumprimento-principal: ${achados} achados (nova ação principal) · ${jaEraRaiz} já eram raiz (FOR-196) · ${semSeed} sem seed utilizável · ${erro} erro(s) · ${(duracaoMs / 1000).toFixed(1)}s`);
    if (erros.length) console.log(`  primeiros erros: ${JSON.stringify(erros.slice(0, 5), null, 2)}`);
  } catch (fatal) {
    if (run) await supabase.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { erro: String(fatal) } }).eq("id", run.id);
    throw fatal;
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  main().catch((e) => { console.error(e); process.exit(1); });
}
