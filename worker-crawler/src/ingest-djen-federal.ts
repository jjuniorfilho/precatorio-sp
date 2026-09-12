// FOR-145 — Ingestão DJEN federal (TRF1-6). Arquivo dedicado (não reaproveita
// ingest-djen.ts) — decisão de arquitetura: zero risco de regressão no job
// diário do TJSP já em produção. Ver .claude/sessions/for-145-*/architecture.md.
//
// FASE 2 do plan.md: só fetch + observabilidade (djen_dias/coleta_runs).
// Classificação (nomeClasse/classificacao_regras) e persistência
// (processos/cumprimentos/incidentes/andamentos) entram nas Fases 3/4.
//
// Diferenças deliberadas em relação a ingest-djen.ts:
// - SEM filtro nomeParte no servidor (ainda não existe lista curada de entes
//   públicos federais) — aceita o volume maior (15k+/dia medido no TRF3).
// - siglaTribunal parametrizado (TRF1..TRF6), não hardcoded TJSP.
// - delay entre páginas mais conservador (nunca rodamos isso em produção).
//
// Uso:
//   tsx src/ingest-djen-federal.ts --tribunal=TRF3                    -> ontem
//   tsx src/ingest-djen-federal.ts --tribunal=TRF3 --date=2026-09-01
//   tsx src/ingest-djen-federal.ts --tribunal=TRF3 --from=2026-09-01 --to=2026-09-05 --backfill
import { createHash } from "node:crypto";
import { supabase, ensureAuth, upsertReturningId, classifyProcesso } from "./supabase.js";

/** FOR-145 — teto de tempo por dia (ver rationale em config.ts `dayTimeoutMs`). Mesmo padrão
 * de `withJobTimeout` em index.ts (FOR-116): a promise perdedora continua rodando em segundo
 * plano até resolver sozinha (Node não tem "cancelar await" de verdade), mas o processo segue
 * pro próximo dia em vez de travar pra sempre. */
class DayTimeoutError extends Error {}
function withDayTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new DayTimeoutError(`dia excedeu o teto de ${ms}ms`)), ms);
    promise.then(
      (v) => { clearTimeout(timer); resolve(v); },
      (e) => { clearTimeout(timer); reject(e); },
    );
  });
}
import { config, sleep, assertConfig } from "./config.js";

const md5 = (s: string) => createHash("md5").update(s).digest("hex");

const API = "https://comunicaapi.pje.jus.br/api/v1/comunicacao";
const HEADERS = {
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "pt-BR,pt;q=0.9",
  "Referer": "https://comunica.pje.jus.br/",
  "Origin": "https://comunica.pje.jus.br",
};

const TRIBUNAIS_VALIDOS = ["TRF1", "TRF2", "TRF3", "TRF4", "TRF5", "TRF6"] as const;
type Tribunal = (typeof TRIBUNAIS_VALIDOS)[number];

const norm = (s: string) => (s ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().trim();

// FASE 3 — Classificação. Balde estrutural derivado de nomeClasse (padronizada
// nacionalmente pelo CNJ — ver docs/business-context/brainstorm/
// precatorio-federal-classificacao-djen-2026-09-05.md). Diferente do que o PRD
// original dizia ("demais classes = conhecimento", corrigido 2026-09-06): só
// as 6 classes abaixo são capturadas — qualquer outra classe é ignorada, igual
// ao modelo estadual (que também só olha `classes_relevantes`).
export type BaldeClassificacao = "conhecimento" | "cumprimento_sentenca" | "precatorio" | "rpv";

/** Mapa fixo classe→balde (decisão de negócio, não tunável via coleta_config).
 * `classesRelevantes` (vindo de coleta_config.params) só controla QUAIS dessas
 * classes estão ativas no matching — adicionar uma 7ª classe em produção exige
 * também adicionar aqui, não só no config. */
const CLASSE_BALDE: Record<string, BaldeClassificacao> = {
  "precatorio": "precatorio",
  "requisicao de pequeno valor": "rpv",
  "cumprimento de sentenca contra a fazenda publica": "cumprimento_sentenca",
  "cumprimento provisorio de sentenca contra a fazenda publica": "cumprimento_sentenca",
  "execucao contra a fazenda publica": "cumprimento_sentenca",
  "procedimento do juizado especial da fazenda publica": "conhecimento",
};

/** Classifica pelo nomeClasse do payload DJEN, usando a lista de
 * `classes_relevantes` vinda de coleta_config. Match numa única direção —
 * a classe observada CONTÉM a classe configurada (`alvo.includes(c)`), nunca
 * o contrário. Descoberta em amostra real (2026-09-06, TRF3): um match
 * bidirecional deixa "CUMPRIMENTO DE SENTENÇA" (genérico, entre particulares)
 * bater contra a config "cumprimento de sentença CONTRA A FAZENDA PÚBLICA",
 * porque o nome curto observado é prefixo do nome longo configurado — falso
 * positivo que classificaria execução privada como caso público. Retorna null
 * quando a classe não é uma das relevantes — a publicação é IGNORADA, não vira
 * "conhecimento" por padrão (correção 2026-09-06). Pura, testável. */
export function classificaPorNomeClasse(nomeClasse: string | null, classesRelevantes: string[]): BaldeClassificacao | null {
  const alvo = norm(nomeClasse ?? "");
  if (!alvo) return null;
  for (const classeConfig of classesRelevantes) {
    const c = norm(classeConfig);
    if (alvo.includes(c)) {
      return CLASSE_BALDE[c] ?? null;
    }
  }
  return null;
}

// Entes públicos federais reconhecidos — usado só como FALLBACK informativo
// (ver deveCapturar/detectaEnteFederal abaixo), não como filtro obrigatório.
// Descoberta ao vivo em 2026-09-06 (amostra real TRF3, 1000 publicações):
// `destinatarios` no payload federal só lista quem é INTIMADO (normalmente o
// autor/credor, polo "A") — o réu (União/INSS/etc.) quase nunca aparece com
// polo "P" (2/1000 na amostra). Diferente do TJSP, onde destinatarios inclui
// as duas partes. Por isso a classe processual é o filtro PRINCIPAL (classes
// como "...CONTRA A FAZENDA PÚBLICA" já restringem a casos contra ente público
// por definição da própria Tabela Processual Unificada do CNJ) — o nome da
// parte passiva vira só um enriquecimento best-effort, tentando primeiro em
// destinatarios (raro) e depois no teor da publicação (`texto`, onde o réu
// costuma aparecer como "REU: <nome>" em texto livre).
const ENTES_FEDERAIS_DEFAULT = [
  "UNIAO", "UNIÃO",
  "FAZENDA NACIONAL", "FAZENDA PUBLICA FEDERAL", "FAZENDA PÚBLICA FEDERAL",
  "INSS", "INSTITUTO NACIONAL DO SEGURO SOCIAL",
  "CEF", "CAIXA ECONOMICA FEDERAL", "CAIXA ECONÔMICA FEDERAL",
  "ECT", "CORREIOS", "EMPRESA BRASILEIRA DE CORREIOS",
  "INCRA", "IBAMA", "FUNAI", "ANATEL", "ANVISA", "ANEEL", "DNIT", "INMETRO",
  "AUTARQUIA FEDERAL", "AGENCIA NACIONAL", "AGÊNCIA NACIONAL",
];

/** true se `nome` bate com algum ente público federal reconhecido (lista
 * default + extras vindos de coleta_config.params.entes_federais). Pura,
 * testável — ver ingest-djen-federal.test.ts. */
export function enteFederalPublico(nome: string | null, extras: string[] = []): boolean {
  const n = norm(nome ?? "");
  if (!n) return false;
  return [...ENTES_FEDERAIS_DEFAULT, ...extras].some((e) => n.includes(norm(e)));
}

/** Fallback best-effort pra descobrir qual ente federal é o réu, quando a
 * publicação não deixa isso explícito em `destinatarios` (o caso comum — ver
 * comentário acima). Tenta destinatarios (polo "P") primeiro; se não achar,
 * varre o teor (`texto`) atrás de menções a um ente reconhecido (ex: "REU:
 * INSTITUTO NACIONAL DO SEGURO SOCIAL - INSS" no texto livre da intimação).
 * Retorna null se não achar em nenhum lugar — é informativo, nunca bloqueia
 * a captura (isso é decidido só pela classe, em deveCapturar). */
export function detectaEnteFederal(
  item: { destinatarios?: Array<{ polo?: string; nome?: string }> | null; texto?: string | null },
  extras: string[] = [],
): string | null {
  const viaDestinatario = (item.destinatarios ?? []).find((d) => d.polo === "P" && enteFederalPublico(d.nome ?? null, extras));
  if (viaDestinatario?.nome) return viaDestinatario.nome;
  const texto = norm(item.texto ?? "");
  if (!texto) return null;
  const achado = [...ENTES_FEDERAIS_DEFAULT, ...extras].find((e) => texto.includes(norm(e)));
  return achado ?? null;
}

/** Decide se uma publicação é capturada — só pela classe processual (a
 * própria classe já restringe a casos contra Fazenda Pública, ver comentário
 * acima). Publicação com classe fora da lista de relevantes é ignorada. */
export function deveCapturar(
  item: { nomeClasse?: string | null },
  classesRelevantes: string[],
): BaldeClassificacao | null {
  return classificaPorNomeClasse(item.nomeClasse ?? null, classesRelevantes);
}

// FASE 4 — Persistência. Sem crawler de origem, não há árvore real a
// descobrir — usa o padrão de placeholder já existente no projeto (incidente
// tipo_previsto='Indefinido' do FOR-71; linhas LEGADO- do FOR-143). Ver
// architecture.md para a decisão completa.
export interface PlanoPersistencia {
  processo: { processo_codigo: string; cnj: string | null; cnj_normalizado: string | null; tribunal: string; sistema: string; ente_esfera: "Federal"; classe: string | null };
  cumprimento?: { processo_codigo: string; cnj: string; cnj_normalizado: string; tribunal: string; sistema: string };
  incidenteVaso?: { processo_codigo: string; tipo_previsto: "Precatorio" | "RPV" | "Indefinido" };
  andamento?: { data: string | null; descricao: string | null; arquivo_url: string | null; hash: string };
}

/** Monta o plano de persistência (puro, sem I/O) a partir de um item já
 * classificado. `conhecimento` vira só um `processos` real (o próprio CNJ
 * é o processo de conhecimento). Qualquer outro balde vira um `processos`
 * placeholder (`FEDPLACEHOLDER-<cnj_normalizado>`) + `cumprimentos` (o CNJ
 * real) + `incidentes` "vaso" 1:1 (não é registro jurídico separado —
 * `numero_depre` sempre NULL) + `andamentos` (o teor da publicação). Pura,
 * testável — ver ingest-djen-federal.test.ts. */
export function planoPersistencia(
  item: { numeroprocessocommascara?: string | null; nomeClasse?: string | null; link?: string | null; texto?: string | null },
  balde: BaldeClassificacao,
  tribunal: Tribunal,
  sistema: "pje" | "eproc" | "outro",
  date: string,
): PlanoPersistencia | null {
  const cnj = item.numeroprocessocommascara ?? null;
  if (!cnj) return null;
  const cnjNorm = cnj.replace(/\D/g, "");

  if (balde === "conhecimento") {
    return {
      processo: { processo_codigo: cnj, cnj, cnj_normalizado: cnjNorm, tribunal, sistema, ente_esfera: "Federal", classe: item.nomeClasse ?? null },
    };
  }

  const tipoPrevisto = balde === "precatorio" ? "Precatorio" : balde === "rpv" ? "RPV" : "Indefinido";
  return {
    processo: { processo_codigo: `FEDPLACEHOLDER-${cnjNorm}`, cnj: null, cnj_normalizado: null, tribunal, sistema, ente_esfera: "Federal", classe: null },
    cumprimento: { processo_codigo: cnj, cnj, cnj_normalizado: cnjNorm, tribunal, sistema },
    incidenteVaso: { processo_codigo: `${cnj}-VASO`, tipo_previsto: tipoPrevisto },
    andamento: { data: date, descricao: item.texto ?? null, arquivo_url: item.link ?? null, hash: md5(`${date}|${item.texto ?? ""}|${item.link ?? ""}`) },
  };
}

/** Executa o plano (upserts idempotentes + classify_processo no final).
 * Reaproveita upsertReturningId/classifyProcesso de supabase.ts, intocados. */
export async function persistFederal(plano: PlanoPersistencia): Promise<void> {
  const processoId = await upsertReturningId("processos", plano.processo, "processo_codigo");
  if (!plano.cumprimento || !plano.incidenteVaso) return; // balde=conhecimento — só o processo, nada mais a persistir

  const cumprimentoId = await upsertReturningId("cumprimentos", { ...plano.cumprimento, processo_id: processoId }, "processo_codigo");
  const incidenteId = await upsertReturningId("incidentes", {
    ...plano.incidenteVaso,
    cumprimento_id: cumprimentoId,
    processo_id: processoId,
    numero_depre: null,
  }, "processo_codigo");

  if (plano.andamento) {
    const { error } = await supabase.from("andamentos").upsert(
      { incidente_id: incidenteId, ...plano.andamento },
      { onConflict: "incidente_id,hash", ignoreDuplicates: true },
    );
    if (error) throw new Error(`upsert andamentos (federal): ${error.message}`);
  }

  await classifyProcesso(processoId);
}

/** Detecta o sistema de origem pelo domínio do link (payload DJEN aponta pro
 * Diário, não pro sistema — mas o domínio do documento entrega o sistema real).
 * Confirmado ao vivo em 2026-09-05: TRF1/TRF3/TRF5 = pje (pje1g.trfN.jus.br),
 * TRF2/TRF4/TRF6 = eproc (eproc*.jf*.jus.br / eproc1g.trf6.jus.br). Pura,
 * testável isoladamente — ver ingest-djen-federal.test.ts. */
export function sistemaFromLink(link: string | null): "pje" | "eproc" | "outro" {
  if (!link) return "outro";
  if (/pje\d*g?\.trf\d\.jus\.br/i.test(link)) return "pje";
  if (/eproc/i.test(link)) return "eproc";
  return "outro";
}

/** Executa fn sobre items com no máximo `limit` em paralelo. Mesmo padrão de
 * index.ts (crawler e-SAJ) — sem isso, persistência sequencial (~5 idas ao
 * banco por item) não escala pros volumes reais (12k-20k+ capturados/dia no
 * TRF1, dias passando de 3h). Confirmado em produção 2026-09-07. */
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

/** GET de uma página da Comunica com retry/backoff (a API dá 429/500/504 esporádico —
 * confirmado ao vivo nesta sessão após bateria de testes exploratórios). */
async function fetchPage(tribunal: Tribunal, date: string, pagina: number, pageSize: number): Promise<any[]> {
  const url = `${API}?siglaTribunal=${tribunal}&dataDisponibilizacaoInicio=${date}&dataDisponibilizacaoFim=${date}`
    + `&pagina=${pagina}&itensPorPagina=${pageSize}`;
  let lastErr: unknown;
  for (let attempt = 0; attempt <= 4; attempt++) {
    try {
      const res = await fetch(url, { headers: HEADERS, signal: AbortSignal.timeout(config.requestTimeoutMs) });
      if (res.status === 429 || res.status >= 500) throw new Error(`HTTP ${res.status}`);
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const payload: any = await res.json();
      return payload.items ?? [];
    } catch (e) {
      lastErr = e;
      if (attempt < 4) await sleep(2000 * Math.pow(2, attempt)); // 2s,4s,8s,16s — mais conservador que o estadual (1s base)
    }
  }
  throw new Error(`Comunica falhou (tribunal=${tribunal} pagina=${pagina}): ${String(lastErr)}`);
}

export async function ingestDayFederal(
  tribunal: Tribunal,
  date: string,
  opts: { backfill?: boolean } = {},
): Promise<{ date: string; tribunal: Tribunal; status: string; total: number; pje: number; eproc: number; outro: number; capturados: number; porBalde: Record<string, number>; erros: number }> {
  const rotina = `caderno_djen_${tribunal.toLowerCase()}`;
  const origem = opts.backfill ? "backfill" : "dje_diario";
  const sb = supabase as any;
  const vazio = { total: 0, pje: 0, eproc: 0, outro: 0, capturados: 0, porBalde: {}, erros: 0 };

  const { data: cfg } = await sb.from("coleta_config").select("enabled, params").eq("rotina", rotina).maybeSingle();
  if (cfg && cfg.enabled === false) {
    return { date, tribunal, status: "skipped", ...vazio };
  }
  const params = (cfg?.params ?? {}) as { itens_por_pagina?: number; classes_relevantes?: string[] };
  const pageSize = params.itens_por_pagina ?? 100;
  const classesRelevantes = params.classes_relevantes ?? [];

  const { data: dia } = await sb.from("djen_dias").select("status").eq("data", date).eq("tribunal", tribunal).maybeSingle();
  if (dia?.status === "ok") {
    return { date, tribunal, status: "ja_processado", ...vazio };
  }

  // Diagnóstico 2026-09-06: upsert de djen_dias silenciosamente sem erro checado
  // fazia dias com muito volume (400+ páginas) sumirem da tabela sem deixar rastro
  // — coleta_runs (INSERT simples) sempre gravou certo, então não era RLS/auth.
  // Logar o erro real na próxima falha, em vez de engolir silenciosamente.
  const upsertDjenDias = async (row: Record<string, unknown>) => {
    const { error } = await sb.from("djen_dias").upsert(row, { onConflict: "data,tribunal" });
    if (error) console.error(`[djen_dias upsert] tribunal=${tribunal} data=${date}:`, error);
  };

  await upsertDjenDias({ data: date, tribunal, status: "parcial", erro: null });
  const { data: run } = await sb.from("coleta_runs").insert({ rotina, status: "running" }).select("id").single();

  const t0 = Date.now();
  let total = 0, pje = 0, eproc = 0, outro = 0, capturados = 0, erros = 0, pagina = 1;
  const porBalde: Record<string, number> = {};
  try {
    for (;;) {
      const items = await fetchPage(tribunal, date, pagina, pageSize);
      if (items.length === 0) break;

      // Fase síncrona/barata: classifica e monta o plano de todo mundo.
      const paraPersistir: Array<{ cnj: unknown; balde: BaldeClassificacao; plano: PlanoPersistencia }> = [];
      for (const it of items) {
        total++;
        const sistema = sistemaFromLink(it.link ?? null);
        switch (sistema) {
          case "pje": pje++; break;
          case "eproc": eproc++; break;
          default: outro++; break;
        }

        const balde = deveCapturar(it, classesRelevantes);
        if (!balde) continue;
        const plano = planoPersistencia(it, balde, tribunal, sistema, date);
        if (!plano) continue; // sem CNJ no item — não deveria acontecer, mas não é motivo pra derrubar o dia inteiro
        paraPersistir.push({ cnj: it.numeroprocessocommascara, balde, plano });
      }

      // Fase de I/O: persiste em paralelo (config.persistConcurrency lanes).
      // Falha em 1 publicação não derruba o dia inteiro — loga e segue.
      await runPool(paraPersistir, config.persistConcurrency, async ({ cnj, balde, plano }) => {
        try {
          await persistFederal(plano);
          capturados++;
          porBalde[balde] = (porBalde[balde] ?? 0) + 1;
        } catch (errItem) {
          erros++;
          console.error(`[persist] tribunal=${tribunal} cnj=${cnj}:`, errItem);
        }
      });

      await upsertDjenDias({ data: date, tribunal, status: "parcial", total, ultima_pagina: pagina });
      if (items.length < pageSize) break;
      pagina++;
      await sleep(config.delayMs * 2); // mais conservador — Fase 5 decide se ajusta pra cima
    }

    await upsertDjenDias(
      { data: date, tribunal, status: "ok", total, flagueados: capturados, enfileirados: capturados, eproc, processado_em: new Date().toISOString() },
    );
    if (run) {
      await sb.from("coleta_runs").update({
        status: erros > 0 ? "erro_parcial" : "sucesso", finished_at: new Date().toISOString(), itens_ok: capturados, itens_erro: erros,
        duracao_ms: Date.now() - t0, detalhe: { date, tribunal, origem, total, pje, eproc, outro, capturados, porBalde },
      }).eq("id", run.id);
    }
    return { date, tribunal, status: "ok", total, pje, eproc, outro, capturados, porBalde, erros };
  } catch (err) {
    await upsertDjenDias({ data: date, tribunal, status: "erro", erro: String(err) });
    if (run) await sb.from("coleta_runs").update({ status: "erro", finished_at: new Date().toISOString(), detalhe: { date, tribunal, erro: String(err) } }).eq("id", run.id);
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
  const tribunal = arg("tribunal") as Tribunal | undefined;
  if (!tribunal || !TRIBUNAIS_VALIDOS.includes(tribunal)) {
    console.error(`--tribunal obrigatório, um de: ${TRIBUNAIS_VALIDOS.join(", ")}`);
    process.exit(1);
  }
  const backfill = process.argv.includes("--backfill");
  const from = arg("from"), to = arg("to"), date = arg("date");
  const dias = from && to ? [...dateRange(from, to)] : [date ?? yesterdayIso()];
  console.log(`ingest-djen-federal: tribunal=${tribunal} ${dias.length} dia(s) ${backfill ? "(backfill)" : ""}`);
  for (const d of dias) {
    try {
      const r = await withDayTimeout(ingestDayFederal(tribunal, d, { backfill }), config.dayTimeoutMs);
      console.log(`[${tribunal} ${d}] ${r.status} total=${r.total} pje=${r.pje} eproc=${r.eproc} outro=${r.outro} capturados=${r.capturados} erros=${r.erros} balde=${JSON.stringify(r.porBalde)}`);
    } catch (e) {
      console.error(`[${tribunal} ${d}] ERRO:`, e);
      if (e instanceof DayTimeoutError) {
        // ingestDayFederal ainda pode estar rodando em segundo plano (a promise perdedora não
        // é cancelada) — marca "erro" agora pra não deixar o dia preso em "parcial" pra sempre;
        // se a promise perdedora terminar depois e sobrescrever com "ok", tanto melhor.
        const { error } = await (supabase as any)
          .from("djen_dias")
          .upsert({ data: d, tribunal, status: "erro", erro: String(e) }, { onConflict: "data,tribunal" });
        if (error) console.error(`[djen_dias upsert timeout] tribunal=${tribunal} data=${d}:`, error);
      }
    }
    await sleep(config.delayMs);
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().then(() => process.exit(0)).catch((e) => { console.error("fatal:", e); process.exit(1); });
}
