# Plan: FOR-198 — Categorizar erros de consulta

## Fase A — Classificador puro (novo módulo)

1. `worker-crawler/src/erro-categoria.ts`:
   - `export type ErroCategoria = "captcha" | "timeout" | "rate_limit" | "site_indisponivel" | "bloqueio_suspeito" | "cnj_nao_encontrado" | "outro"`
   - `export const ERRO_CATEGORIAS: readonly ErroCategoria[]` (mesmo padrão de `ORIGENS_CONSULTA`)
   - `export interface ClassificarErroOpts { conteudoInesperado?: boolean; naoEncontrado?: boolean }`
   - `export function classificarErro(erro: unknown, opts？: ClassificarErroOpts): ErroCategoria`
     — prioridade: `naoEncontrado` > `conteudoInesperado` > regex (rate_limit `/HTTP 429|HTTP 5\d\d/` >
     captcha `/captcha/i` > timeout `/timeout|timed out/i` > site_indisponivel
     `/ECONNREFUSED|ECONNRESET|ENOTFOUND|EAI_AGAIN|net::ERR_|browser has been closed|Target (page|closed)|ERR_CONNECTION/i`) > `"outro"`.
2. `erro-categoria.test.ts` — 1 caso real por categoria + 2 casos de prioridade (flag explícita
   vence regex; `naoEncontrado` vence `conteudoInesperado`). Ver seção "Verificação adversarial".

## Fase B — `pagamentos-passos.ts` + `pagamentos-tjsp.ts`

3. `ConsultaPagamentoErro`: 4º parâmetro `categoria: ErroCategoria` no construtor.
4. `pagamentos-tjsp.ts`:
   - import `classificarErro`, `type ErroCategoria`.
   - linha ~142 (falha de persistência): `new ConsultaPagamentoErro(msg, "persistir", passos, "outro")`.
   - catch-all (linha ~257-262): computa `conteudoInesperado` via regex nas 2 mensagens
     ambíguas conhecidas (`não encontrado no menu`, `portal não reconhecida`) e chama
     `classificarErro(e, { conteudoInesperado })`.
   - `consultarEPersistirPagamentos`: espelha `etapaFalha` → acrescenta `categoriaFalha =
     erro instanceof ConsultaPagamentoErro ? erro.categoria : classificarErro(erro)` e passa
     pro `deps.registrar`.
5. `supabase.ts`: `RegistroConsultaPagamento` ganha `categoria: ErroCategoria | null`;
   `registrarConsultaPagamento` manda `p_categoria: r.categoria`.
6. Ajustar `pagamentos-tjsp.test.ts` (2 chamadas de `new ConsultaPagamentoErro` ganham 4º arg).

## Fase C — `index.ts` (loop crawler e-SAJ)

7. Novo helper `requisitorioNaoRetornouDetalhe` (espelha `buscaNuncaSaiuDoSeed`, regex da
   mensagem de `crawlRequisitorio`).
8. No catch de `processBatch`: computa `ultimaTentativa`, `semFichaNoESaj` (ramifica por
   `isDepre`), `categoria = classificarErro(err, { conteudoInesperado: semFichaNoESaj,
   naoEncontrado: !isDepre(...) && ultimaTentativa && semFichaNoESaj })`; `failJob(job.id,
   String(err), categoria)`. Reusa `ultimaTentativa` no `if` existente de `parkAsEproc`
   (mesma expressão booleana, zero mudança de comportamento).
9. `supabase.ts`: `failJob(id, erro, categoria?: ErroCategoria | null)` → `p_categoria`.

## Fase D — Migrations SQL (preparadas, NÃO aplicadas)

10. `sql/2026-10-04_for198_1_erro_categoria_crawler_queue.sql`:
    `ALTER TABLE crawler_queue ADD COLUMN erro_categoria text CHECK (...)` +
    `DROP FUNCTION fail_crawler_job(uuid,text)` + `CREATE FUNCTION fail_crawler_job(uuid,text,text DEFAULT NULL)`
    + REVOKE/GRANT.
11. `sql/2026-10-04_for198_2_erro_categoria_pagamentos_consultas_log.sql`: mesma forma para
    `pagamentos_consultas_log`/`registrar_consulta_pagamento` (12→13 parâmetros).
12. `sql/sandbox/for198_validate_local.sh`: Postgres local efêmero (padrão `for195c_validate_local.sh`)
    — aplica as 2 migrations sobre um schema mínimo, confirma: coluna existe, CHECK rejeita
    valor fora da lista, `fail_crawler_job`/`registrar_consulta_pagamento` aceitam `p_categoria`
    e persistem, GRANT preservado pós DROP+CREATE.

## Fase E — Garantias + verificação adversarial

13. `npm run typecheck` + `npm test` em `worker-crawler/`.
14. Ler o diff inteiro de `index.ts`, `pagamentos-tjsp.ts`, `supabase.ts`.
15. Rodar `sql/sandbox/for198_validate_local.sh` até passar (Postgres 15 local via Homebrew).
16. Script pontual (scratchpad) exercitando `classificarErro` com 1 entrada real por categoria
    (mensagem exata extraída do código real, não inventada) + os 2 casos de prioridade.
17. code-reviewer + adr-compliance-checker (STRICT) sobre o diff.

## Fase F — pre-pr / pr

18. `/engineer:pre-pr` (branch-* + cross-doc + ADR STRICT).
19. `/engineer:pr` → abre PR, Linear → In Review. Relata as 2 migrations como pendentes de
    aplicação manual no SQL Editor (freio de mão: produção).
