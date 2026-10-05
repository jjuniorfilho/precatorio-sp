// Cliente Supabase (service_role) + RPCs da fila (FOR-73) + persistência (FOR-69).
import { createClient } from "@supabase/supabase-js";
import { createHash } from "node:crypto";
import WebSocketImpl from "ws";
import { config } from "./config.js";
import { normNome } from "./comunica.js";
import type { ProcessoPrincipalInfo, ProcessoTree, QueueJob } from "./types.js";
import type { OrigemInfo } from "./parse.js";
import type { ErroCategoria } from "./erro-categoria.js";

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

// FOR-195 — exportado pro script de backfill (backfill-legado-cumprimento-principal.ts)
// reusar a mesma normalização ao reportar/logar, em vez de duplicar a regex.
export const cnjNorm = (cnj: string | null) => (cnj ? cnj.replace(/\D/g, "") : null);
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
/** FOR-200: `raia` é opcional NO CHAMADOR (`p_raia DEFAULT NULL` na RPC — chamador sem raia
 * continua funcionando, só não loga em `crawler_execucoes_log`). NÃO é opcional quanto à
 * migration: a RPC *precisa* já ter sido migrada pra aceitar esse parâmetro — mesmo risco do
 * `categoria` no FOR-198 (PGRST202 se o worker novo subir antes da migration
 * sql/2026-10-04_for200_2_...sql ser aplicada). Aplicar a migration ANTES de deployar este
 * código. `raia` é 1-based (lane 0-based do `runPool` + 1), só pra leitura humana no admin. */
export async function completeJob(id: string, raia?: number): Promise<void> {
  const { error } = await supabase.rpc("complete_crawler_job", { p_id: id, p_raia: raia ?? null });
  if (error) throw new Error(`complete_crawler_job: ${error.message}`);
}
/** FOR-198: `categoria` é opcional NO CHAMADOR (chamadores antigos continuam válidos — a RPC
 * tem `p_categoria DEFAULT NULL`). NÃO é opcional quanto à migration: a RPC *precisa* já ter
 * sido migrada pra aceitar esse parâmetro — se o worker novo subir antes da migration
 * (sql/2026-10-04_for198_1_...sql) ser aplicada, o PostgREST não resolve a função (parâmetro
 * desconhecido) e esta chamada falha por completo, não "ignora" o categoria. Aplicar a
 * migration ANTES de deployar este código.
 * FOR-200: `raia` segue o mesmo contrato opcional documentado em `completeJob` acima. */
export async function failJob(id: string, erro: string, categoria?: ErroCategoria | null, raia?: number): Promise<void> {
  const { error } = await supabase.rpc("fail_crawler_job", {
    p_id: id,
    p_erro: erro.slice(0, 2000),
    p_categoria: categoria ?? null,
    p_raia: raia ?? null,
  });
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
  // FOR-178 (achado do code review): com 2+ linhas legado e nenhuma real, renomear TODAS pro mesmo
  // processo_codigo estourava unique violation na 2ª. Agora só a 1ª é renomeada (vira o "real") e
  // as demais são fundidas nela pela RPC de merge.
  let alvoId = (real as { id: string } | null)?.id ?? null;
  for (const legadoId of legadoIds) {
    if (alvoId) {
      const { error } = await supabase.rpc(mergeRpc, { p_legado_id: legadoId, p_real_id: alvoId });
      if (error) throw new Error(`${mergeRpc}: ${error.message}`);
    } else {
      const { error } = await supabase.from(table).update({ processo_codigo: processoCodigoReal }).eq("id", legadoId);
      if (error) throw new Error(`reconcileLegado ${table} (rename): ${error.message}`);
      alvoId = legadoId;
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

/** FOR-178 — reconciliação LEGADO no nível do CUMPRIMENTO. O import legado (FOR-143) gravou em
 * `processos` (LEGADO-<cnj>) o CNJ do CUMPRIMENTO de sentença — um nível abaixo da raiz real que o
 * crawler descobre via normalizeToRoot — então reconcileLegadoProcesso (que casa pelo cnj da RAIZ)
 * nunca a encontrava e o crawl criava a hierarquia real em paralelo, deixando a linha legado órfã e
 * duplicando incidentes.numero_depre. Aqui, pra cada cumprimento persistido, procura linha
 * `processos` LEGADO- com o mesmo cnj_normalizado e a funde no processo raiz real + cumprimento
 * real (RPC merge_legado_processo_para_cumprimento: reaponta incidentes/partes e apaga a legado).
 * O caller (persistTree) roda isto pra TODOS os cumprimentos antes de montar o Map de incidentes
 * legado, pra que reconcileLegadoIncidente enxergue os incidentes que acabaram de ser reapontados. */
async function reconcileLegadoCumprimento(
  cnjNormalizado: string | null,
  processoId: string,
  cumprimentoId: string,
): Promise<void> {
  if (!config.legadoReconcile || !cnjNormalizado) return;
  const { data, error } = await supabase.from("processos").select("id").eq("cnj_normalizado", cnjNormalizado).like("processo_codigo", "LEGADO-%");
  if (error) throw new Error(`reconcileLegadoCumprimento (busca): ${error.message}`);
  for (const { id: legadoId } of (data ?? []) as Array<{ id: string }>) {
    if (legadoId === processoId) continue;
    const { error: eRpc } = await supabase.rpc("merge_legado_processo_para_cumprimento", {
      p_legado_processo_id: legadoId,
      p_real_processo_id: processoId,
      p_real_cumprimento_id: cumprimentoId,
    });
    if (eRpc) throw new Error(`merge_legado_processo_para_cumprimento: ${eRpc.message}`);
  }
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

// ---- FOR-195: ação principal real acima do cumprimento (legado) -----------
/** Usado pelo script one-off `backfill-legado-cumprimento-principal.ts`, um candidato por vez
 * (concorrência=1 — aprovado pelo humano, cautela com o e-SAJ/VPS de 1 vCPU).
 *
 * `processoAtualId` é o `processos.id` que hoje representa — por engano — a raiz (na verdade é
 * o CUMPRIMENTO). `principal` é a capa já extraída da ação principal real (via
 * `fetchProcessoPrincipal`, crawl.ts), que o CALLER confirmou existir buscando o e-SAJ de
 * verdade.
 *
 * O upsert por `processo_codigo` (igual a todo upsert de `processos` em `persistTree`) é seguro
 * sob concorrência por construção — `processo_codigo` já é `UNIQUE` (migration FOR-69) — então
 * duas reconciliações diferentes resolvendo pra MESMA ação principal (dois incidentes legado
 * distintos que sobem pro mesmo processo) nunca duplicam a linha `processos`: a 2ª chamada só
 * reaproveita o id que a 1ª já criou. Por isso NÃO depende de `cnj_normalizado` ter unique
 * constraint (que não tem, e não precisa ganhar uma só pra isto).
 *
 * Retorna o id do `processos` row do principal (novo ou reaproveitado). */
export async function reconcilePrincipalReal(
  processoAtualId: string,
  principal: ProcessoPrincipalInfo,
): Promise<string> {
  const principalId = await upsertReturningId("processos", {
    processo_codigo: principal.processo_codigo,
    cnj: principal.cnj,
    cnj_normalizado: cnjNorm(principal.cnj),
    foro: principal.foro,
    classe: principal.classe,
    assunto: principal.assunto,
    distribuicao: principal.distribuicao,
    valor_acao: principal.valor_acao,
    data_base: principal.data_base,
    ente_nome: principal.ente_nome,
    ente_esfera: principal.ente_esfera,
    flag_sp: principal.flag_sp,
    status: principal.status,
    last_crawled_at: new Date().toISOString(),
  }, "processo_codigo");

  if (principalId !== processoAtualId) {
    const { error } = await supabase.rpc("merge_legado_cumprimento_para_principal", {
      p_processo_atual_id: processoAtualId,
      p_processo_principal_id: principalId,
    });
    if (error) throw new Error(`merge_legado_cumprimento_para_principal: ${error.message}`);
  }
  return principalId;
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

  // Passo 1: TODOS os cumprimentos primeiro + FOR-178 (funde a linha processos LEGADO- que guardava
  // o CNJ do cumprimento, reapontando os incidentes LEGADO- dela pra este processo). Tem que
  // terminar ANTES de montar o Map de incidentes legado: o incidente real que casa com um legado
  // pendurado no cumprimento B pode estar sob o cumprimento A (achado do code review).
  const cumprimentoIds: string[] = [];
  for (const c of tree.cumprimentos) {
    const cumprimentoId = await upsertReturningId("cumprimentos", {
      processo_id: processoId,
      processo_codigo: c.processo_codigo,
      cnj: c.cnj,
      cnj_normalizado: cnjNorm(c.cnj),
    }, "processo_codigo");
    await reconcileLegadoCumprimento(cnjNorm(c.cnj), processoId, cumprimentoId);
    cumprimentoIds.push(cumprimentoId);
  }

  // Passo 2: Map montado uma vez, já enxergando os incidentes reapontados no passo 1.
  const incidentesLegadoDoProcesso = await buscarIncidentesLegadoDoProcesso(processoId);

  for (const [idx, c] of tree.cumprimentos.entries()) {
    const cumprimentoId = cumprimentoIds[idx]!;
    for (const inc of c.incidentes) {
      if (inc.numero_depre) {
        // Consome a entrada: um legado reconciliado não pode ser renomeado de novo por outro
        // incidente crawleado com o mesmo numero_depre (o rename o "moveria" de incidente).
        const legadoIds = incidentesLegadoDoProcesso.get(inc.numero_depre) ?? [];
        incidentesLegadoDoProcesso.delete(inc.numero_depre);
        await reconcileLegadoIncidente(legadoIds, inc.processo_codigo);
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
      for (const pa of inc.partes_ativas) {
        if (pa.advogados.length === 0) {
          partesRows.push({
            incidente_id: incidenteId, processo_id: processoId, papel: "ativa",
            nome: pa.nome, documento: pa.documento, sem_oab: false, fonte: "esaj",
          });
        }
        for (const adv of pa.advogados) {
          partesRows.push({
            incidente_id: incidenteId, processo_id: processoId, papel: "ativa",
            nome: pa.nome, documento: pa.documento,
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
export async function persistRequisitorio(tree: ProcessoTree, origemInfo: OrigemInfo[]): Promise<void> {
  const inc = tree.cumprimentos[0]?.incidentes[0];
  const cnj = tree.cnj ?? inc?.cnj ?? null;
  if (!cnj) throw new Error("persistRequisitorio: requisitório sem CNJ");

  const andamentos = (inc?.andamentos ?? []).map((a) => ({
    data: a.data,
    descricao: a.descricao,
    arquivo_url: a.arquivo_url,
  }));

  // origem_incidentes só guarda as entradas com sufixo "/NNNN" (numeroIncidente) — são
  // essas que permitem vincular_numero_depre_reverso() achar o incidente certo depois que
  // o CNJ de origem for crawleado (ver index.ts). Entradas sem sufixo (ex.: "Outros
  // números" da capa) não servem pra esse fim e ficam de fora.
  const origemComIncidente = origemInfo
    .filter((o): o is OrigemInfo & { numeroIncidente: string } => !!o.numeroIncidente)
    .map((o) => ({ cnj: o.cnj, numero_incidente: o.numeroIncidente }));

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
    // Requisitório normalmente tem 1 só credor; se vier mais de um (raro), fica o 1º.
    titular_nome: inc?.partes_ativas[0]?.nome ?? null,
    origem_cnjs: origemInfo.length ? origemInfo.map((o) => o.cnj) : null,
    origem_incidentes: origemComIncidente.length ? origemComIncidente : null,
    andamentos,
    ficha_crawled_at: new Date().toISOString(),
  };

  // upsert por cnj_normalizado (mescla com o registro criado na ingestão DJEN).
  const { error } = await supabase
    .from("djen_depre")
    .upsert(row, { onConflict: "cnj_normalizado" });
  if (error) throw new Error(`upsert djen_depre (requisitório): ${error.message}`);
}

/** FOR-156 — depois que um CNJ de origem (achado via djen_depre.origem_incidentes) é
 * crawleado, tenta vincular numero_depre no incidente certo usando o sufixo "/NNNN" já
 * conhecido — em vez de depender de extractDepre() reachar o .0500 na própria página do
 * incidente de origem (não funciona quando o requisitório nunca é citado lá, achado real
 * em processos de execução coletiva antiga com múltiplos "Precatório - 0000X" na mesma
 * ação). No-op (0 linhas) quando esse CNJ nunca foi origem de um .0500 com sufixo
 * conhecido, ou quando o incidente já tem numero_depre. */
export async function vincularNumeroDepreReverso(origemCnj: string, processoId: string): Promise<number> {
  const { data, error } = await supabase.rpc("vincular_numero_depre_reverso", {
    p_origem_cnj: origemCnj,
    p_processo_id: processoId,
  });
  if (error) throw new Error(`vincular_numero_depre_reverso: ${error.message}`);
  return (data as number) ?? 0;
}

// ---- FOR-102: pagamentos por processo_depre (portal TJSP "Pagamentos Precatórios") -------

/** Upsert idempotente dos pagamentos encontrados. Re-consultar não duplica (índice único
 * em processo_depre+data_pagamento+valor+tipo — colunas NOT NULL, ver
 * sql/2026-07-22_fix_precatorios_pagamentos_index.sql). `tipo` vira `''` em vez de NULL
 * (NULL não conflita com NULL num índice único do Postgres, o que quebraria a idempotência).
 *
 * Achado em produção (FOR-174, 2026-09-29): um `.upsert()` DIRETO na tabela como fazíamos antes
 * SEMPRE falhava com "new row violates row-level security policy" quando o worker roda sem
 * `SUPABASE_SERVICE_ROLE_KEY` (autentica como `authenticated` via login admin — "Opção B" logo
 * acima nesse arquivo). A tabela nunca teve policy de INSERT/UPDATE pra `authenticated`
 * (`sql/2026-07-21_pagamentos_tjsp.sql`: "escrita só via service_role"), então TODO pagamento
 * real encontrado pelo scraper (não "não consta") se perdia. Agora passa pela RPC
 * `SECURITY DEFINER` `upsert_precatorios_pagamentos`
 * (sql/2026-09-29_for174_fix_upsert_pagamentos_rls.sql), mesmo padrão de
 * `marcarPagamentosConsultado` logo abaixo — sem abrir uma policy geral de INSERT. */
export async function upsertPagamentos(
  processoDepre: string,
  pagamentos: Array<{ data: string | null; valorCentavos: number; tipo: string | null }>,
): Promise<void> {
  if (pagamentos.length === 0) return;
  const itens = pagamentos
    .filter((p) => p.data) // data_pagamento é NOT NULL na tabela (a RPC também filtra, defesa em profundidade)
    .map((p) => ({ data: p.data, valor: p.valorCentavos, tipo: p.tipo ?? "" }));
  const { error } = await supabase.rpc("upsert_precatorios_pagamentos", {
    p_processo_depre: processoDepre,
    p_pagamentos: itens,
  });
  if (error) throw new Error(`upsert_precatorios_pagamentos: ${error.message}`);
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

// ---- FOR-171: log das consultas ao portal TJSP (pagamentos_consultas_log) ---------------

export interface RegistroConsultaPagamento {
  processoDepre: string;
  iniciadaEm: Date;
  finalizadaEm: Date;
  origem: "manual" | "busca_publica" | "crawler";
  resultado: "encontrado" | "nao_consta" | "falha";
  tentativas: number;
  situacao: string | null;
  qtdPagamentos: number | null;
  dataConsultaPortal: string | null;
  erro: string | null;
  etapaFalha: string | null;
  /** FOR-198: categoria classificada no worker; null só quando não há erro. A RPC já precisa
   * aceitar `p_categoria` (migration sql/2026-10-04_for198_2_...sql aplicada) — se não aceitar,
   * a chamada falha por completo (best-effort: erro só no console, log da consulta não é
   * gravado), não grava null silenciosamente. */
  categoriaFalha: ErroCategoria | null;
  passos: unknown[];
}

/** Grava uma consulta no log (RPC SECURITY DEFINER `registrar_consulta_pagamento`; poda em 20 por
 * processo). O chamador trata como best-effort: erro aqui não deve derrubar a consulta. */
export async function registrarConsultaPagamento(r: RegistroConsultaPagamento): Promise<void> {
  const { error } = await supabase.rpc("registrar_consulta_pagamento", {
    p_processo_depre: r.processoDepre,
    p_iniciada_em: r.iniciadaEm.toISOString(),
    p_finalizada_em: r.finalizadaEm.toISOString(),
    p_origem: r.origem,
    p_resultado: r.resultado,
    p_tentativas: r.tentativas,
    p_situacao: r.situacao,
    p_qtd_pagamentos: r.qtdPagamentos,
    p_data_consulta_portal: r.dataConsultaPortal,
    p_erro: r.erro,
    p_etapa_falha: r.etapaFalha,
    p_passos: r.passos,
    p_categoria: r.categoriaFalha,
  });
  if (error) throw new Error(`registrarConsultaPagamento: ${error.message}`);
}

// ---- FOR-173: progresso incremental da consulta de valor pago (pagamentos_consultas_progresso) ----

export type EstadoProgresso = "na_fila" | "em_andamento" | "concluida" | "falha";

export interface RegistroProgressoPagamento {
  processoDepre: string;
  estado: EstadoProgresso;
  /** Etapa EM ANDAMENTO (na_fila | iniciando | uma Etapa do coletor); a RPC troca o que não conhecer por 'desconhecida'. */
  etapa: string;
  tentativa: number;
  maxTentativas: number;
  detalhe: string | null;
  resultado: "encontrado" | "nao_consta" | "falha" | null;
  etapaFalha: string | null;
  origem: "manual" | "busca_publica" | "crawler";
  /** true só no `na_fila`: renova `iniciada_em` (o front usa a mudança dele para reconhecer a consulta nova). */
  nova: boolean;
}

/** Teto por escrita de progresso: `supabase.rpc` não tem timeout próprio e uma RPC travada prenderia as
 * escritas seguintes da mesma consulta (o estado final nunca chegaria). */
export const PROGRESSO_TIMEOUT_MS = 5000;

/** Publica o progresso (RPC SECURITY DEFINER `registrar_progresso_consulta_pagamento`). Lança em caso de
 * erro; o reporter (pagamentos-progresso.ts) engole: progresso é auxiliar e não pode derrubar a consulta. */
export async function registrarProgressoPagamento(r: RegistroProgressoPagamento): Promise<void> {
  const { error } = await supabase
    .rpc("registrar_progresso_consulta_pagamento", {
    p_processo_depre: r.processoDepre,
    p_estado: r.estado,
    p_etapa: r.etapa,
    p_tentativa: r.tentativa,
    p_max_tentativas: r.maxTentativas,
    p_detalhe: r.detalhe,
    p_resultado: r.resultado,
    p_etapa_falha: r.etapaFalha,
    p_origem: r.origem,
    p_nova: r.nova,
    })
    .abortSignal(AbortSignal.timeout(PROGRESSO_TIMEOUT_MS));
  if (error) throw new Error(`registrarProgressoPagamento: ${error.message}`);
}
