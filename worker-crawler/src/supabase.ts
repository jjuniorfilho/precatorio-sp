// Cliente Supabase (service_role) + RPCs da fila (FOR-73) + persistência (FOR-69).
import { createClient } from "@supabase/supabase-js";
import { createHash } from "node:crypto";
import WebSocketImpl from "ws";
import { config } from "./config.js";
import { normNome } from "./comunica.js";
import type { ProcessoTree, QueueJob } from "./types.js";

// Node < 22 não tem WebSocket nativo (supabase realtime exige). Fornece o `ws`.
if (!(globalThis as { WebSocket?: unknown }).WebSocket) {
  (globalThis as { WebSocket?: unknown }).WebSocket = WebSocketImpl as unknown;
}

// Usa service_role se houver; senão anon key + login admin (Opção B).
const usingServiceRole = !!config.serviceRoleKey;
export const supabase = createClient(config.supabaseUrl, config.serviceRoleKey || config.anonKey, {
  auth: { persistSession: false, autoRefreshToken: !usingServiceRole },
});

let _authed = false;
/** Garante sessão: service_role não precisa; admin faz signInWithPassword uma vez. */
export async function ensureAuth(): Promise<void> {
  if (usingServiceRole || _authed) return;
  const { error } = await supabase.auth.signInWithPassword({
    email: config.adminEmail,
    password: config.adminPassword,
  });
  if (error) throw new Error(`login admin falhou: ${error.message}`);
  _authed = true;
  console.log(`autenticado como admin (${config.adminEmail})`);
}

const cnjNorm = (cnj: string | null) => (cnj ? cnj.replace(/\D/g, "") : null);
const md5 = (s: string) => createHash("md5").update(s).digest("hex");

/** DJEN-first: lê os advogados já estruturados na ingestão p/ os CNJs dados.
 * Retorna nome(normalizado) → OAB. Mapa vazio se a tabela não tiver nada (cai no fallback). */
export async function djenAdvogadosByCnj(cnjsNorm: string[]): Promise<Map<string, { oab: string; oab_normalizada: string }>> {
  const out = new Map<string, { oab: string; oab_normalizada: string }>();
  const list = [...new Set(cnjsNorm.filter(Boolean))];
  if (!list.length) return out;
  const { data, error } = await supabase
    .from("djen_advogados").select("advogado_nome, oab, oab_normalizada").in("cnj_normalizado", list);
  if (error) return out; // tabela ausente / RLS → fallback ao vivo
  for (const r of (data ?? []) as Array<{ advogado_nome: string; oab: string | null; oab_normalizada: string | null }>) {
    if (!r.oab || !r.oab_normalizada) continue;
    out.set(normNome(r.advogado_nome), { oab: r.oab, oab_normalizada: r.oab_normalizada });
  }
  return out;
}

// ---- RPCs da fila (FOR-73) --------------------------------------------------
export async function claimJobs(limit: number): Promise<QueueJob[]> {
  const { data, error } = await supabase.rpc("claim_crawler_jobs", { p_limit: limit });
  if (error) throw new Error(`claim_crawler_jobs: ${error.message}`);
  return (data ?? []) as QueueJob[];
}
export async function completeJob(id: string): Promise<void> {
  const { error } = await supabase.rpc("complete_crawler_job", { p_id: id });
  if (error) throw new Error(`complete_crawler_job: ${error.message}`);
}
export async function failJob(id: string, erro: string): Promise<void> {
  const { error } = await supabase.rpc("fail_crawler_job", { p_id: id, p_erro: erro.slice(0, 2000) });
  if (error) throw new Error(`fail_crawler_job: ${error.message}`);
}
/** FOR-107: reseta jobs "processando" órfãos (claimed_at > p_limiteMinutos atrás) pra
 * "pendente". RPC porque UPDATE direto em crawler_queue esbarra em RLS quando o worker
 * roda sem service_role (anon key + login admin — "Opção B" acima). Retorna quantos. */
export async function resetOrfaosCrawlerQueue(limiteMinutos = 60): Promise<number> {
  const { data, error } = await supabase.rpc("reset_orfaos_crawler_queue", { p_limite_minutos: limiteMinutos });
  if (error) throw new Error(`reset_orfaos_crawler_queue: ${error.message}`);
  return (data as number) ?? 0;
}
export async function classifyProcesso(processoId: string): Promise<void> {
  const { error } = await supabase.rpc("classify_processo", { p_processo_id: processoId });
  if (error) throw new Error(`classify_processo: ${error.message}`);
}
/** Enfileira um CNJ (ex.: processo de origem de um requisitório). Best-effort. */
export async function enqueueJob(cnj: string, origem: string): Promise<void> {
  const { error } = await supabase.rpc("enqueue_crawler_job", { p_processo_codigo: cnj, p_origem: origem });
  if (error) console.error(`enqueue_crawler_job(${cnj}): ${error.message}`);
}

/** Diagnóstico 2026-09 (sessão de investigação do circuit breaker): sistemaFromLink()
 * (ingest-djen.ts) não consegue detectar eproc de verdade — o `link` do DJEN aponta pro
 * Diário, não pro sistema — então CNJ eproc-only entra na crawler_queue e nunca resolve
 * ficha no e-SAJ. Em vez de tentar prever isso na ingestão (sem sinal confiável pra usar),
 * deixa o próprio e-SAJ decidir: quando um job esgota as 3 tentativas com a busca nunca
 * saindo do seed (ver crawl.ts blindagem), reclassifica pra eproc_pendentes — mesma tabela
 * que o ingest usa pro caminho "eproc" detectado via link, só que descoberta pelo resultado
 * real da busca em vez de adivinhada de antemão. Best-effort (não tem os metadados de DJEN
 * aqui — nome_orgao/nome_classe/link ficam null; só cnj é obrigatório na tabela).
 */
export async function parkAsEproc(cnj: string): Promise<void> {
  const { error } = await supabase.from("eproc_pendentes").upsert({ cnj }, { onConflict: "cnj", ignoreDuplicates: true });
  if (error) console.error(`parkAsEproc(${cnj}): ${error.message}`);
}

export async function upsertReturningId(table: string, row: Record<string, unknown>, onConflict: string): Promise<string> {
  const { data, error } = await supabase.from(table).upsert(row, { onConflict }).select("id").single();
  if (error) throw new Error(`upsert ${table}: ${error.message}`);
  return (data as { id: string }).id;
}

/** FOR-143 — reconcilia com uma linha "LEGADO-" pré-existente (import do CSV legado, sem
 * processo_codigo real do e-SAJ) antes do upsert normal. Sem isso, o upsert por processo_codigo
 * criaria uma segunda linha pro mesmo CNJ/requisitório em vez de completar a já existente.
 * Renomeia o processo_codigo da linha legado pro real quando esse código ainda não existe; se
 * já existir (import criou duplicata, ou o crawler descobriu o CNJ organicamente numa corrida
 * com o import), faz merge via RPC em vez de tentar renomear — renomear estouraria unique
 * violation em `processo_codigo`. No-op quando não há linha "LEGADO-" pra reconciliar. */
async function reconcileLegadoRows(
  table: "processos" | "incidentes",
  legadoIds: string[],
  processoCodigoReal: string,
  mergeRpc: "merge_legado_processo" | "merge_legado_incidente",
): Promise<void> {
  if (!legadoIds.length) return;
  const { data: real, error: eReal } = await supabase.from(table).select("id").eq("processo_codigo", processoCodigoReal).maybeSingle();
  if (eReal) throw new Error(`reconcileLegado ${table} (lookup real): ${eReal.message}`);
  for (const legadoId of legadoIds) {
    if (real) {
      const { error } = await supabase.rpc(mergeRpc, { p_legado_id: legadoId, p_real_id: (real as { id: string }).id });
      if (error) throw new Error(`${mergeRpc}: ${error.message}`);
    } else {
      const { error } = await supabase.from(table).update({ processo_codigo: processoCodigoReal }).eq("id", legadoId);
      if (error) throw new Error(`reconcileLegado ${table} (rename): ${error.message}`);
    }
  }
}

/** processos: escopado só por cnj_normalizado (chave natural do processo raiz). Gateado por
 * config.legadoReconcile (FOR-143) — desligável depois que o backfill for absorvido, já que a
 * partir daí vira 1 SELECT morto por processo crawleado, pra sempre. */
async function reconcileLegadoProcesso(cnjNormalizado: string | null, processoCodigoReal: string): Promise<void> {
  if (!config.legadoReconcile || !cnjNormalizado) return;
  const { data, error } = await supabase.from("processos").select("id").eq("cnj_normalizado", cnjNormalizado).like("processo_codigo", "LEGADO-%");
  if (error) throw new Error(`reconcileLegadoProcesso (busca): ${error.message}`);
  await reconcileLegadoRows("processos", (data ?? []).map((r: { id: string }) => r.id), processoCodigoReal, "merge_legado_processo");
}

/** Busca TODOS os incidentes "LEGADO-" de um processo numa única query (em vez de 1 SELECT por
 * incidente — achado do code-review: processos com centenas/milhares de incidentes pagavam um
 * round-trip extra por incidente, à toa na maioria das vezes já que a maior parte dos processos
 * não tem nenhuma linha LEGADO- pra reconciliar). Map por numero_depre pra lookup O(1) no loop
 * de incidentes do persistTree. */
async function buscarIncidentesLegadoDoProcesso(processoId: string): Promise<Map<string, string[]>> {
  const out = new Map<string, string[]>();
  if (!config.legadoReconcile) return out;
  const { data, error } = await supabase.from("incidentes").select("id, numero_depre").eq("processo_id", processoId).like("processo_codigo", "LEGADO-%");
  if (error) throw new Error(`buscarIncidentesLegadoDoProcesso: ${error.message}`);
  for (const row of (data ?? []) as Array<{ id: string; numero_depre: string | null }>) {
    if (!row.numero_depre) continue;
    const arr = out.get(row.numero_depre) ?? [];
    arr.push(row.id);
    out.set(row.numero_depre, arr);
  }
  return out;
}

/** incidentes: escopado por processo_id (já resolvido/reconciliado acima) **e** numero_depre —
 * numero_depre sozinho não é único (confirmado em produção: o mesmo numero_depre pode aparecer
 * em incidentes de processos diferentes), então sem o escopo por processo_id um crawl de um
 * processo A não-relacionado poderia sequestrar/corromper um incidente LEGADO- do processo B só
 * porque coincide o numero_depre. Recebe os ids já resolvidos por buscarIncidentesLegadoDoProcesso
 * (sem query própria — é só o passo de decidir renomear vs. merge). */
async function reconcileLegadoIncidente(legadoIds: string[], processoCodigoReal: string): Promise<void> {
  if (!config.legadoReconcile || !legadoIds.length) return;
  await reconcileLegadoRows("incidentes", legadoIds, processoCodigoReal, "merge_legado_incidente");
}

// ---- Persistência da árvore -------------------------------------------------
/** Grava a árvore e retorna o id (uuid) do processo raiz. e-SAJ prevalece sobre DJEN. */
export async function persistTree(tree: ProcessoTree): Promise<string> {
  // flag_sp / ente: derivado das partes passivas dos incidentes
  const passivas = tree.cumprimentos.flatMap((c) => c.incidentes.map((i) => i.parte_passiva)).filter(Boolean);
  const enteSP = passivas.find((p) => p && p.ente_esfera !== "Outro") ?? passivas[0] ?? null;

  await reconcileLegadoProcesso(cnjNorm(tree.cnj), tree.processo_codigo);
  const processoId = await upsertReturningId("processos", {
    processo_codigo: tree.processo_codigo,
    cnj: tree.cnj,
    cnj_normalizado: cnjNorm(tree.cnj),
    foro: tree.foro,
    classe: tree.classe,
    assunto: tree.assunto,
    distribuicao: tree.distribuicao,
    valor_acao: tree.valor_acao,
    data_base: tree.data_base,
    ente_nome: enteSP?.nome ?? null,
    ente_esfera: enteSP?.ente_esfera ?? null,
    flag_sp: !!enteSP && enteSP.ente_esfera !== "Outro",
    status: tree.status,
    last_crawled_at: new Date().toISOString(),
  }, "processo_codigo");

  const incidentesLegadoDoProcesso = await buscarIncidentesLegadoDoProcesso(processoId);

  for (const c of tree.cumprimentos) {
    const cumprimentoId = await upsertReturningId("cumprimentos", {
      processo_id: processoId,
      processo_codigo: c.processo_codigo,
      cnj: c.cnj,
      cnj_normalizado: cnjNorm(c.cnj),
    }, "processo_codigo");

    for (const inc of c.incidentes) {
      if (inc.numero_depre) {
        await reconcileLegadoIncidente(incidentesLegadoDoProcesso.get(inc.numero_depre) ?? [], inc.processo_codigo);
      }
      const incidenteId = await upsertReturningId("incidentes", {
        cumprimento_id: cumprimentoId,
        processo_id: processoId,
        processo_codigo: inc.processo_codigo,
        numero_incidente: inc.numero_incidente,
        tipo_previsto: inc.tipo_previsto,
        numero_depre: inc.numero_depre,
        cnj: inc.cnj,
        cnj_normalizado: cnjNorm(inc.cnj),
        status: inc.status,
        tramitacao_prioritaria: inc.tramitacao_prioritaria,
        valor_acao: inc.valor_acao,
        data_base: inc.data_base,
      }, "processo_codigo");

      // partes: e-SAJ prevalece → substitui as do incidente
      await supabase.from("partes").delete().eq("incidente_id", incidenteId);
      const partesRows: Record<string, unknown>[] = [];
      if (inc.parte_ativa) {
        if (inc.parte_ativa.advogados.length === 0) {
          partesRows.push({
            incidente_id: incidenteId, processo_id: processoId, papel: "ativa",
            nome: inc.parte_ativa.nome, documento: inc.parte_ativa.documento, sem_oab: false, fonte: "esaj",
          });
        }
        for (const adv of inc.parte_ativa.advogados) {
          partesRows.push({
            incidente_id: incidenteId, processo_id: processoId, papel: "ativa",
            nome: inc.parte_ativa.nome, documento: inc.parte_ativa.documento,
            advogado_nome: adv.nome, oab: adv.oab, oab_normalizada: adv.oab_normalizada,
            sem_oab: adv.sem_oab, fonte: "esaj",
          });
        }
      }
      if (inc.parte_passiva) {
        partesRows.push({
          incidente_id: incidenteId, processo_id: processoId, papel: "passiva",
          nome: inc.parte_passiva.nome, sem_oab: false, fonte: "esaj",
        });
      }
      if (partesRows.length) {
        const { error } = await supabase.from("partes").insert(partesRows);
        if (error) throw new Error(`insert partes: ${error.message}`);
      }

      // andamentos idempotentes (hash); ignora duplicados
      if (inc.andamentos.length) {
        const rows = inc.andamentos.map((a) => ({
          incidente_id: incidenteId,
          data: a.data,
          descricao: a.descricao,
          arquivo_url: a.arquivo_url,
          hash: md5(`${a.data ?? ""}|${a.descricao}|${a.arquivo_url ?? ""}`),
        }));
        const { error } = await supabase
          .from("andamentos")
          .upsert(rows, { onConflict: "incidente_id,hash", ignoreDuplicates: true });
        if (error) throw new Error(`upsert andamentos: ${error.message}`);
      }
    }
  }

  return processoId;
}

/**
 * Persiste um requisitório .0500 na tabela DEPRE (djen_depre) — ficha + andamentos —
 * SEM criar processo principal. Regra de negócio: nenhum .0500 é principal; o
 * vínculo ocorre depois, quando o processo de ORIGEM é crawleado e um dos seus
 * incidentes referencia este .0500 pelo numero_depre. `origem` são os CNJs de
 * origem extraídos da ficha do requisitório (já enfileirados pelo caller).
 */
export async function persistRequisitorio(tree: ProcessoTree, origem: string[]): Promise<void> {
  const inc = tree.cumprimentos[0]?.incidentes[0];
  const cnj = tree.cnj ?? inc?.cnj ?? null;
  if (!cnj) throw new Error("persistRequisitorio: requisitório sem CNJ");

  const andamentos = (inc?.andamentos ?? []).map((a) => ({
    data: a.data,
    descricao: a.descricao,
    arquivo_url: a.arquivo_url,
  }));

  const row = {
    cnj,
    cnj_normalizado: cnjNorm(cnj),
    valor_acao: inc?.valor_acao ?? tree.valor_acao ?? null,
    status: inc?.status ?? tree.status ?? null,
    classe: tree.classe ?? null,
    data_base: inc?.data_base ?? tree.data_base ?? null,
    devedora: inc?.parte_passiva?.nome ?? null,
    // Reqte/requerente: sempre presente na ficha (PARTES DO PROCESSO), diferente do
    // documento (CPF/CNPJ), que o TJSP nunca expõe aqui — só chega via busca informada
    // pelo próprio titular (buscar-precatorio grava titular_documento nesse caso).
    titular_nome: inc?.parte_ativa?.nome ?? null,
    origem_cnjs: origem.length ? origem : null,
    andamentos,
    ficha_crawled_at: new Date().toISOString(),
  };

  // upsert por cnj_normalizado (mescla com o registro criado na ingestão DJEN).
  const { error } = await supabase
    .from("djen_depre")
    .upsert(row, { onConflict: "cnj_normalizado" });
  if (error) throw new Error(`upsert djen_depre (requisitório): ${error.message}`);
}

// ---- FOR-102: pagamentos por processo_depre (portal TJSP "Pagamentos Precatórios") -------

/** Upsert idempotente dos pagamentos encontrados. Re-consultar não duplica (índice único
 * em processo_depre+data_pagamento+valor+tipo — colunas NOT NULL, ver
 * sql/2026-07-22_fix_precatorios_pagamentos_index.sql). `tipo` vira `''` em vez de NULL
 * (NULL não conflita com NULL num índice único do Postgres, o que quebraria a idempotência). */
export async function upsertPagamentos(
  processoDepre: string,
  pagamentos: Array<{ data: string | null; valorCentavos: number; tipo: string | null }>,
): Promise<void> {
  if (pagamentos.length === 0) return;
  const rows = pagamentos
    .filter((p) => p.data) // data_pagamento é NOT NULL na tabela
    .map((p) => ({
      processo_depre: processoDepre,
      data_pagamento: p.data,
      valor: p.valorCentavos,
      tipo: p.tipo ?? "",
    }));
  const { error } = await supabase
    .from("precatorios_pagamentos")
    .upsert(rows, { onConflict: "processo_depre,data_pagamento,valor,tipo", ignoreDuplicates: true });
  if (error) throw new Error(`upsert precatorios_pagamentos: ${error.message}`);
}

/** Marca que a consulta de pagamentos foi feita (mesmo sem pagamentos encontrados —
 * ausência é resultado válido, não erro; ver context.md da sessão FOR-102).
 *
 * Via RPC (não update direto na tabela): `precatorios` só permite escrita via
 * service_role (dado público DEPRE); o worker autentica como `authenticated`, então precisa
 * da RPC SECURITY DEFINER `marcar_pagamentos_consultado` (sql/2026-07-22_marcar_pagamentos_
 * consultado_rpc.sql) em vez de abrir UPDATE geral na tabela pra authenticated. */
export async function marcarPagamentosConsultado(processoDepre: string): Promise<void> {
  const { error } = await supabase.rpc("marcar_pagamentos_consultado", { p_processo_depre: processoDepre });
  if (error) throw new Error(`marcarPagamentosConsultado: ${error.message}`);
}
