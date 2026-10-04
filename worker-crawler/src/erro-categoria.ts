// FOR-198 — Categorização estruturada dos erros de consulta (e-SAJ cpopg + Pagamentos
// Precatórios TJSP). Classifica NO WORKER, na hora do erro (decisão de arquitetura #1 da
// issue) — nunca depois, via regex sobre a mensagem já truncada/persistida. Mesmo padrão de
// `Etapa` em `pagamentos-passos.ts`: union TypeScript simples + array readonly, sem
// dependências, sem enum nativo do Postgres (decisão #3).
//
// "bloqueio_suspeito" é heurística, não fato (decisão #2) — página respondeu 200 OK sem o
// conteúdo esperado, e isso é indistinguível entre manutenção do TJSP, bloqueio de IP, e CNJ
// que nunca existiu naquele sistema (comentário original em crawl.ts). É exposta sempre, nunca
// escondida dentro de "outro" — mas quem lê o dado deve tratá-la como incerta.

export type ErroCategoria =
  | "captcha"
  | "timeout"
  | "rate_limit"
  | "site_indisponivel"
  | "bloqueio_suspeito"
  | "cnj_nao_encontrado"
  | "outro";

export const ERRO_CATEGORIAS: readonly ErroCategoria[] = [
  "captcha",
  "timeout",
  "rate_limit",
  "site_indisponivel",
  "bloqueio_suspeito",
  "cnj_nao_encontrado",
  "outro",
];

export interface ClassificarErroOpts {
  /** O chamador sabe que a página respondeu 200 OK sem o conteúdo esperado — a heurística de
   * bloqueio/manutenção da issue (decisão #2). Vence qualquer regex na mensagem: é informação
   * de quem lançou o erro, mais confiável que inferir de novo a partir do texto. */
  conteudoInesperado?: boolean;
  /** O chamador tem um sinal forte o bastante pra afirmar "não encontrado" (não só "incerto") —
   * ex.: mesmo erro ambíguo persistindo até a ÚLTIMA tentativa da fila. Vence `conteudoInesperado`. */
  naoEncontrado?: boolean;
}

/** HTTP 429/5xx explícito — já tratado de verdade (retry/backoff/circuit-breaker) em esaj.ts/
 * index.ts; aqui só rotula. `esaj.ts::fetchHtml` lança `Error("HTTP " + status)`, que chega até
 * aqui embutido em mensagens maiores (ex.: "fetchHtml falhou após retries: ... :: HTTP 429"). */
const RATE_LIMIT_RE = /HTTP (429|5\d\d)/;
const CAPTCHA_RE = /captcha/i;
/** Cobre tanto o `DOMException`/`TimeoutError` do `AbortSignal.timeout` (undici/esaj.ts) quanto
 * os timeouts do Playwright ("Timeout 25000ms exceeded", "page.waitForURL: Timeout ..."). */
const TIMEOUT_RE = /timeout|timed out/i;
/** Site/rede indisponível — a conexão nunca chegou a se completar (distinto de "respondeu 200
 * com conteúdo errado", que é `conteudoInesperado`/bloqueio_suspeito). Cobre também o que o
 * undici costuma embrulhar em `cause` quando a conexão cai no meio ("other side closed",
 * `fetch failed`) e `ETIMEDOUT` (timeout de conexão TCP — distinto do `TIMEOUT_RE` acima, que é
 * timeout de REQUISIÇÃO já em andamento). NÃO cobre "Target page/context/browser has been
 * closed" de propósito — é o Chromium LOCAL crashando (VPS com pouca memória, documentado em
 * pagamentos-tjsp.ts), não o TJSP fora do ar; rotular isso como site_indisponivel inflaria essa
 * categoria com um problema de infra própria. Cai em "outro", honestamente. */
const SITE_INDISPONIVEL_RE = /ECONNREFUSED|ECONNRESET|ENOTFOUND|EAI_AGAIN|ETIMEDOUT|net::ERR_|ERR_CONNECTION|other side closed|fetch failed/i;

/** Classifica um erro de consulta numa `ErroCategoria`. Pura — sem I/O, testável com qualquer
 * `Error`/string. Prioridade: `naoEncontrado` > `conteudoInesperado` > regex na mensagem
 * (rate_limit > captcha > timeout > site_indisponivel) > `"outro"` (default seguro: erro
 * classificado, mas sem categoria específica — nunca finge certeza que não tem). */
export function classificarErro(erro: unknown, opts: ClassificarErroOpts = {}): ErroCategoria {
  if (opts.naoEncontrado) return "cnj_nao_encontrado";
  if (opts.conteudoInesperado) return "bloqueio_suspeito";

  // undici (fetch/esaj.ts) costuma embrulhar o erro de rede real em `cause` (ex.: a mensagem
  // de topo é só "fetch failed", e ECONNRESET/ETIMEDOUT vivem em err.cause.code/message) — inclui
  // os dois na mesma string testada, em vez de só a mensagem de topo.
  const causa = erro instanceof Error && erro.cause !== undefined ? ` ${String(erro.cause)}` : "";
  const msg = String(erro instanceof Error ? erro.message : erro) + causa;
  if (RATE_LIMIT_RE.test(msg)) return "rate_limit";
  if (CAPTCHA_RE.test(msg)) return "captcha";
  if (TIMEOUT_RE.test(msg)) return "timeout";
  if (SITE_INDISPONIVEL_RE.test(msg)) return "site_indisponivel";
  return "outro";
}
