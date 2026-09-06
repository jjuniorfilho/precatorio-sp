// FOR-70 (na VPS) — Ingestão DJEN/Comunica (TJSP) + flag SP + roteamento e-SAJ/eproc.
// Estratégia: filtra no servidor por `nomeParte` (ente público) — o caderno inteiro
// do TJSP é grande demais (>1500 págs/dia). Roda na VPS (IP aceito pelo PJe).
// Uso:
//   tsx src/ingest-djen.ts                      -> ontem
//   tsx src/ingest-djen.ts --date=2026-06-26
//   tsx src/ingest-djen.ts --from=2025-01-01 --to=2026-06-27 --backfill
import { supabase, ensureAuth } from "./supabase.js";
import { advogadosFromItem, normNome } from "./comunica.js";
import { config, sleep, assertConfig } from "./config.js";

/** Persiste os advogados do DJEN (fonte de verdade nome+OAB+UF) p/ o CNJ flagueado.
 * Dedup por chave (oab_normalizada || NOME); upsert idempotente. Best-effort. */
async function persistAdvogadosDjen(sb: any, cnj: string, item: unknown): Promise<void> {
  const advs = advogadosFromItem(item as Parameters<typeof advogadosFromItem>[0]);
  if (!advs.length) return;
  const cnjNorm = cnj.replace(/\D/g, "");
  const vistos = new Set<string>();
  const rows = [];
  for (const a of advs) {
    const chave = a.oab_normalizada || normNome(a.nome).toUpperCase();
    if (vistos.has(chave)) continue;
    vistos.add(chave);
    rows.push({
      cnj, cnj_normalizado: cnjNorm, advogado_nome: a.nome,
      oab_numero: a.oab_numero, uf_oab: a.uf_oab, oab: a.oab,
      oab_normalizada: a.oab_normalizada, chave_advogado: chave,
    });
  }
  if (rows.length) {
    await sb.from("djen_advogados").upsert(rows, { onConflict: "cnj_normalizado,chave_advogado", ignoreDuplicates: true });
  }
}

const API = "https://comunicaapi.pje.jus.br/api/v1/comunicacao";
const HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "pt-BR,pt;q=0.9",
  "Referer": "https://comunica.pje.jus.br/",
  "Origin": "https://comunica.pje.jus.br",
};

// Termos amplos de parte (passiva) que cobrem entes públicos de SP. Configurável em
// coleta_config.caderno_dje.params.partes_alvo.
const PARTES_ALVO_DEFAULT = [
  "FAZENDA", "MUNICIPIO", "PREFEITURA", "INSTITUTO DE PREVIDENCIA", "AUTARQUIA",
  "DEPARTAMENTO DE ESTRADAS", "UNIVERSIDADE", "CAMARA MUNICIPAL",
];

function esfera(nome: string): "Estadual" | "Municipal" | "Outro" {
  const n = (nome ?? "").toUpperCase();
  if (/\b(ESTADO|FAZENDA\s+(P[ÚU]BLICA\s+)?DO\s+ESTADO|FAZENDA\s+ESTADUAL|GOVERNO\s+DO\s+ESTADO|PROCURADORIA\s+GERAL\s+DO\s+ESTADO|UFESP|IPESP|DER|SPPREV|CDHU|CBPM)\b/.test(n)) return "Estadual";
  if (/\b(MUNIC[ÍI]PIO|PREFEITURA|FAZENDA\s+(P[ÚU]BLICA\s+)?MUNICIPAL|C[ÂA]MARA\s+MUNICIPAL)\b/.test(n)) return "Municipal";
  return "Outro";
}
const sistemaFromLink = (link: string | null): "esaj" | "eproc" | "outro" =>
  !link ? "outro" : /esaj\.tjsp\.jus\.br/i.test(link) ? "esaj" : /eproc.*\.tjsp\.jus\.br/i.test(link) ? "eproc" : "outro";
// DEPRE/precatório (.0500): vive no sistema de precatórios, não no cpopg de 1º grau →
// não é champeável pelo crawler e-SAJ. Não enfileira (evita churn de retries).
const isDepre = (cnj: string): boolean => /\.8\.26\.0500$/.test(cnj);
// Diagnóstico 2026-09 (ver sql/2026-09-03_diag_erros_categoria_hora.sql): foro 0000 nunca
// tem ficha no cpopg (processo ainda sem distribuição/vara própria) — confirmado, não é
// suspeita. Fica de fora igual ao .0500: nem crawler_queue nem eproc_pendentes.
const naoDistribuido = (cnj: string): boolean => /\.8\.26\.0000$/.test(cnj);
const norm = (s: string) => (s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

// FOR-146: match era bidirecional (alvo.includes(c) || c.includes(alvo)) \u2014 o ramo
// `c.includes(alvo)` deixava passar qualquer nomeClasse curto/gen\u00e9rico que fosse
// substring de uma config mais longa (ex.: "CUMPRIMENTO DE SENTEN\u00c7A" batia contra
// "Cumprimento de Senten\u00e7a contra a Fazenda P\u00fablica" sem nenhuma rela\u00e7\u00e3o sem\u00e2ntica
// real). Mantido s\u00f3 `alvo.includes(c)`: o nomeClasse observado precisa CONTER a
// classe configurada, nunca o contr\u00e1rio. `classesConfig` j\u00e1 chega normalizado
// (map(norm) na chamada), ent\u00e3o s\u00f3 normalizamos o nomeClasse aqui.
export function classeOk(nomeClasse: string | null | undefined, classesConfig: string[]): boolean {
  if (classesConfig.length === 0) return true;
  const alvo = norm(nomeClasse ?? "");
  return classesConfig.some((c) => alvo.includes(c));
}

/** GET de uma página da Comunica com retry/backoff (a API dá 500 esporádico). */
async function fetchPage(date: string, parte: string, pagina: number, pageSize: number): Promise<any[]> {
  const url = `${API}?siglaTribunal=TJSP&dataDisponibilizacaoInicio=${date}&dataDisponibilizacaoFim=${date}`
    + `&nomeParte=${encodeURIComponent(parte)}&pagina=${pagina}&itensPorPagina=${pageSize}`;
  let lastErr: unknown;
  for (let attempt = 0; attempt <= 4; attempt++) {
    try {
      const res = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(30_000) });
      if (res.status === 429 || res.status >= 500) throw new Error(`HTTP ${res.status}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const payload: any = await res.json();
      return payload.items ?? [];
    } catch (e) {
      lastErr = e;
      if (attempt < 4) await sleep(1000 * Math.pow(2, attempt)); // 1s,2s,4s,8s
    }
  }
  throw new Error(`Comunica falhou (parte=${parte} pagina=${pagina}): ${String(lastErr)}`);
}

export async function ingestDay(date: string, opts: { backfill?: boolean } = {}): Promise<{ date: string; status: string; total: number; flagueados: number; enfileirados: number; eproc: number; depre: number }> {
  const origem = opts.backfill ? "backfill" : "dje_diario";
  const sb = supabase as any;

  const { data: cfg } = await sb.from("coleta_config").select("enabled, params").eq("rotina", "caderno_dje").maybeSingle();
  if (cfg && cfg.enabled === false) return { date, status: "skipped", total: 0, flagueados: 0, enfileirados: 0, eproc: 0, depre: 0 };
  const params = (cfg?.params ?? {}) as { classes_relevantes?: string[]; itens_por_pagina?: number; partes_alvo?: string[] };
  const classes = (params.classes_relevantes ?? []).map(norm);
  const partes = params.partes_alvo?.length ? params.partes_alvo : PARTES_ALVO_DEFAULT;
  const pageSize = params.itens_por_pagina ?? 100;

  const { data: dia } = await sb.from("djen_dias").select("status").eq("data", date).maybeSingle();
  if (dia?.status === "ok") return { date, status: "ja_processado", total: 0, flagueados: 0, enfileirados: 0, eproc: 0, depre: 0 };

  await sb.from("djen_dias").upsert({ data: date, status: "parcial", erro: null }, { onConflict: "data" });
  const { data: run } = await sb.from("coleta_runs").insert({ rotina: origem === "backfill" ? "backfill" : "caderno_dje", status: "running" }).select("id").single();

  const t0 = Date.now();
  let total = 0, flagueados = 0, enfileirados = 0, eprocCount = 0, depreCount = 0, naoDistribuidoCount = 0;
  const seen = new Set<string>(); // dedupe de CNJ entre as várias partes-alvo
  try {
    for (const parte of partes) {
      let pagina = 1;
      for (;;) {
        const items = await fetchPage(date, parte, pagina, pageSize);
        if (items.length === 0) break;
        for (const it of items) {
          total++;
          const cnj: string | null = it.numeroprocessocommascara ?? null;
          if (!cnj || seen.has(cnj)) continue;
          const passivoPublico = (it.destinatarios ?? []).some((d: any) => d.polo === "P" && esfera(d.nome) !== "Outro");
          if (!(classeOk(it.nomeClasse, classes) && passivoPublico)) continue;
          seen.add(cnj);
          flagueados++;
          // DJEN-first: estrutura os advogados (nome+OAB+UF) já na ingestão.
          await persistAdvogadosDjen(sb, cnj, it);
          // O `link` do DJEN aponta p/ o Diário (www.dje.tjsp.jus.br), não p/ o sistema.
          // Logo: só parqueia quando é CLARAMENTE eproc; senão enfileira p/ o crawler e-SAJ
          // (que busca por CNJ; processos eproc-only retornam "não encontrado" e seguem).
          if (naoDistribuido(cnj)) {
            // Foro 0000: processo ainda sem distribuição/vara própria — nunca tem ficha no
            // cpopg (confirmado; ver naoDistribuido acima). Nem enfileira nem parqueia em
            // eproc_pendentes (não é eproc, é "ainda não existe em sistema nenhum") — só
            // ignora, evitando os 3 retries mortos (~1h15) que cada um gerava antes.
            naoDistribuidoCount++;
          } else if (isDepre(cnj)) {
            depreCount++;
            // .0500 (precatório/requisitório): mantém o registro DJEN E enfileira. O crawler
            // roteia .0500 p/ a Consulta de Requisitórios (show.do foro=0500), de onde tira
            // valor/status/partes/advogados + o CNJ de origem. O saldo legado segue casando
            // por numero_depre = precatorios.processo_depre.
            await sb.from("djen_depre").upsert({
              cnj, cnj_normalizado: cnj.replace(/\D/g, ""),
              numero_processo: it.numero_processo ?? null, link: it.link ?? null,
              nome_orgao: it.nomeOrgao ?? null, nome_classe: it.nomeClasse ?? null,
              data_disponibilizacao: date,
            }, { onConflict: "cnj_normalizado", ignoreDuplicates: true });
            const { error } = await sb.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: origem });
            if (!error) enfileirados++;
          } else if (sistemaFromLink(it.link ?? null) === "eproc") {
            eprocCount++;
            await sb.from("eproc_pendentes").upsert({
              cnj, numero_processo: it.numero_processo ?? null, link: it.link ?? null,
              nome_orgao: it.nomeOrgao ?? null, nome_classe: it.nomeClasse ?? null, data_disponibilizacao: date,
            }, { onConflict: "cnj", ignoreDuplicates: true });
          } else {
            // Diagnóstico (2026-09): "esaj" e "outro" (link vazio/desconhecido) caem aqui
            // igual — grava qual foi antes de enfileirar, pra depois cruzar com erro de
            // crawler_queue e confirmar se "outro" concentra a falha de "busca não retornou".
            const sistema = sistemaFromLink(it.link ?? null);
            await sb.from("djen_link_diag").insert({
              cnj, link: it.link ?? null, sistema_detectado: sistema,
              origem, data_disponibilizacao: date,
            }).then(() => {}, () => {});
            const { error } = await sb.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: origem });
            if (!error) enfileirados++;
          }
        }
        if (items.length < pageSize) break;
        pagina++;
        await sleep(config.delayMs);
      }
    }

    await sb.from("djen_dias").upsert({ data: date, status: "ok", total, flagueados, enfileirados, eproc: eprocCount, processado_em: new Date().toISOString() }, { onConflict: "data" });
    if (run) await sb.from("coleta_runs").update({ status: "sucesso", finished_at: new Date().toISOString(), itens_ok: enfileirados, itens_erro: 0, duracao_ms: Date.now() - t0, detalhe: { date, total, flagueados, enfileirados, eproc: eprocCount, depre: depreCount, nao_distribuido: naoDistribuidoCount } }).eq("id", run.id);
    return { date, status: "ok", total, flagueados, enfileirados, eproc: eprocCount, depre: depreCount };
  } catch (err) {
    await sb.from("djen_dias").upsert({ data: date, status: "erro", erro: String(err) }, { onConflict: "data" });
    if (run) await sb.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { date, erro: String(err) } }).eq("id", run.id);
    throw err;
  }
}

// ---- CLI ----
function arg(name: string): string | undefined {
  const p = process.argv.find((a) => a.startsWith(`--${name}=`));
  return p ? p.split("=")[1] : undefined;
}
function* dateRange(from: string, to: string): Generator<string> {
  const d = new Date(from + "T00:00:00Z"), end = new Date(to + "T00:00:00Z");
  while (d <= end) { yield d.toISOString().slice(0, 10); d.setUTCDate(d.getUTCDate() + 1); }
}
function yesterdayIso(): string { return new Date(Date.now() - 864e5).toISOString().slice(0, 10); }

async function main() {
  assertConfig();
  await ensureAuth();
  const backfill = process.argv.includes("--backfill");
  const from = arg("from"), to = arg("to"), date = arg("date");
  const dias = from && to ? [...dateRange(from, to)] : [date ?? yesterdayIso()];
  console.log(`ingest-djen: ${dias.length} dia(s) ${backfill ? "(backfill)" : ""}`);
  for (const d of dias) {
    try {
      const r = await ingestDay(d, { backfill });
      console.log(`[${d}] ${r.status} total=${r.total} flag=${r.flagueados} fila=${r.enfileirados} eproc=${r.eproc} depre=${r.depre}`);
    } catch (e) {
      console.error(`[${d}] ERRO:`, e);
    }
    await sleep(config.delayMs);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
