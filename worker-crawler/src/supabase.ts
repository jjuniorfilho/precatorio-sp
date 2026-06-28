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
export async function classifyProcesso(processoId: string): Promise<void> {
  const { error } = await supabase.rpc("classify_processo", { p_processo_id: processoId });
  if (error) throw new Error(`classify_processo: ${error.message}`);
}

async function upsertReturningId(table: string, row: Record<string, unknown>, onConflict: string): Promise<string> {
  const { data, error } = await supabase.from(table).upsert(row, { onConflict }).select("id").single();
  if (error) throw new Error(`upsert ${table}: ${error.message}`);
  return (data as { id: string }).id;
}

// ---- Persistência da árvore -------------------------------------------------
/** Grava a árvore e retorna o id (uuid) do processo raiz. e-SAJ prevalece sobre DJEN. */
export async function persistTree(tree: ProcessoTree): Promise<string> {
  // flag_sp / ente: derivado das partes passivas dos incidentes
  const passivas = tree.cumprimentos.flatMap((c) => c.incidentes.map((i) => i.parte_passiva)).filter(Boolean);
  const enteSP = passivas.find((p) => p && p.ente_esfera !== "Outro") ?? passivas[0] ?? null;

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

  for (const c of tree.cumprimentos) {
    const cumprimentoId = await upsertReturningId("cumprimentos", {
      processo_id: processoId,
      processo_codigo: c.processo_codigo,
      cnj: c.cnj,
      cnj_normalizado: cnjNorm(c.cnj),
    }, "processo_codigo");

    for (const inc of c.incidentes) {
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
