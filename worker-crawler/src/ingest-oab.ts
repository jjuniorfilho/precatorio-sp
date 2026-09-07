// Consulta DJEN/Comunica por OAB (numeroOab + ufOab) e enfileira TODOS os processos do
// advogado no TJSP (Precatório .0500 vai pelo caminho de requisitório; eproc é parqueado).
// Descobre + estrutura advogados (djen_advogados) + enfileira; o crawler faz o resto.
// Uso (na VPS, IP liberado pelo PJe):
//   tsx src/ingest-oab.ts --oab=203901 --uf=SP
//   tsx src/ingest-oab.ts --oab=203901 --uf=SP --from=2024-01-01 --to=2026-06-30
import { supabase, ensureAuth } from "./supabase.js";
import { isDepre } from "./esaj.js";
import { advogadosFromItem, normNome } from "./comunica.js";
import { config, sleep, assertConfig } from "./config.js";

const API = "https://comunicaapi.pje.jus.br/api/v1/comunicacao";
const HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "pt-BR,pt;q=0.9",
  "Referer": "https://comunica.pje.jus.br/",
  "Origin": "https://comunica.pje.jus.br",
};

const sistemaFromLink = (link: string | null): "esaj" | "eproc" | "outro" =>
  !link ? "outro" : /esaj\.tjsp\.jus\.br/i.test(link) ? "esaj" : /eproc.*\.tjsp\.jus\.br/i.test(link) ? "eproc" : "outro";

function arg(name: string): string | undefined {
  const p = process.argv.find((a) => a.startsWith(`--${name}=`));
  return p ? p.split("=")[1] : undefined;
}

async function fetchPage(oab: string, uf: string, pagina: number, pageSize: number, from?: string, to?: string): Promise<any[]> {
  let url = `${API}?siglaTribunal=TJSP&numeroOab=${encodeURIComponent(oab)}&ufOab=${encodeURIComponent(uf)}`
    + `&pagina=${pagina}&itensPorPagina=${pageSize}`;
  if (from && to) url += `&dataDisponibilizacaoInicio=${from}&dataDisponibilizacaoFim=${to}`;
  let lastErr: unknown;
  for (let attempt = 0; attempt <= 4; attempt++) {
    try {
      const res = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(30_000) });
      if (res.status === 429 || res.status >= 500 || !res.ok) throw new Error(`HTTP ${res.status}`);
      const payload: any = await res.json();
      return payload.items ?? [];
    } catch (e) {
      lastErr = e;
      if (attempt < 4) await sleep(1000 * Math.pow(2, attempt));
    }
  }
  throw new Error(`Comunica falhou (oab=${oab}/${uf} pagina=${pagina}): ${String(lastErr)}`);
}

/** Estrutura os advogados do item em djen_advogados (fonte de verdade nome+OAB+UF). */
async function persistAdvogados(sb: any, cnj: string, item: unknown): Promise<void> {
  const advs = advogadosFromItem(item as Parameters<typeof advogadosFromItem>[0]);
  if (!advs.length) return;
  const cnjNorm = cnj.replace(/\D/g, "");
  const vistos = new Set<string>();
  const rows = advs
    .filter((a) => { const k = a.oab_normalizada || normNome(a.nome).toUpperCase(); return vistos.has(k) ? false : (vistos.add(k), true); })
    .map((a) => ({
      cnj, cnj_normalizado: cnjNorm, advogado_nome: a.nome, oab_numero: a.oab_numero, uf_oab: a.uf_oab,
      oab: a.oab, oab_normalizada: a.oab_normalizada, chave_advogado: a.oab_normalizada || normNome(a.nome).toUpperCase(),
    }));
  if (rows.length) await sb.from("djen_advogados").upsert(rows, { onConflict: "cnj_normalizado,chave_advogado", ignoreDuplicates: true });
}

async function main() {
  assertConfig();
  await ensureAuth();
  const sb = supabase as any;

  const oab = arg("oab");
  const uf = (arg("uf") ?? "SP").toUpperCase();
  const from = arg("from"), to = arg("to");
  const pageSize = Number(arg("pageSize") ?? 100);
  const fromPage = Math.max(1, Number(arg("fromPage") ?? 1)); // retomar de uma página (API do Comunica cai com 500)
  if (!oab) { console.error("uso: tsx src/ingest-oab.ts --oab=NNNNNN --uf=SP [--from=YYYY-MM-DD --to=YYYY-MM-DD]"); process.exit(1); }

  console.log(`ingest-oab: OAB ${oab}/${uf} ${from && to ? `(${from}..${to})` : "(todo o histórico)"}`);
  const { data: run } = await sb.from("coleta_runs").insert({ rotina: "ingest_oab", status: "running" }).select("id").single();

  const seen = new Set<string>();
  let total = 0, enfileirados = 0, eproc = 0, depre = 0, pagina = fromPage;
  const t0 = Date.now();
  try {
    for (;;) {
      const items = await fetchPage(oab, uf, pagina, pageSize, from, to);
      if (items.length === 0) break;
      for (const it of items) {
        total++;
        const cnj: string | null = it.numeroprocessocommascara ?? null;
        if (!cnj || seen.has(cnj)) continue;
        seen.add(cnj);
        await persistAdvogados(sb, cnj, it);

        if (isDepre(cnj)) {
          depre++;
          await sb.from("djen_depre").upsert({
            cnj, cnj_normalizado: cnj.replace(/\D/g, ""), numero_processo: it.numero_processo ?? null,
            link: it.link ?? null, nome_orgao: it.nomeOrgao ?? null, nome_classe: it.nomeClasse ?? null,
            data_disponibilizacao: it.data_disponibilizacao ?? null,
          }, { onConflict: "cnj_normalizado", ignoreDuplicates: true });
          const { error } = await sb.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: "manual" });
          if (!error) enfileirados++;
        } else if (sistemaFromLink(it.link ?? null) === "eproc") {
          eproc++;
          await sb.from("eproc_pendentes").upsert({
            cnj, numero_processo: it.numero_processo ?? null, link: it.link ?? null,
            nome_orgao: it.nomeOrgao ?? null, nome_classe: it.nomeClasse ?? null, data_disponibilizacao: it.data_disponibilizacao ?? null,
          }, { onConflict: "cnj", ignoreDuplicates: true });
        } else {
          const { error } = await sb.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: "manual" });
          if (!error) enfileirados++;
        }
      }
      console.log(`  pág ${pagina}: +${items.length} (distintos até agora: ${seen.size} · fila: ${enfileirados} · depre: ${depre} · eproc: ${eproc})`);
      if (items.length < pageSize) break;
      pagina++;
      await sleep(config.delayMs);
    }
    if (run) await sb.from("coleta_runs").update({ status: "sucesso", finished_at: new Date().toISOString(), itens_ok: enfileirados, duracao_ms: Date.now() - t0, detalhe: { oab, uf, total, distintos: seen.size, enfileirados, depre, eproc } }).eq("id", run.id);
    console.log(`\n✓ OAB ${oab}/${uf}: ${total} publicações · ${seen.size} processos distintos · ${enfileirados} enfileirados (${depre} .0500) · ${eproc} eproc parqueados`);
  } catch (err) {
    if (run) await sb.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { oab, uf, erro: String(err) } }).eq("id", run.id);
    throw err;
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
