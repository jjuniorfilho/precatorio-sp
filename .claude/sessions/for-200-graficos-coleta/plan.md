# Plan: FOR-200 — cortex-v1 (backend)

## Fase A — Migrations (3 arquivos, re-executáveis, não aplicadas por este agente)

1. `sql/2026-10-04_for200_1_tabela_crawler_execucoes_log.sql` — `CREATE TABLE IF NOT EXISTS`
   + índice + RLS (enable, revoke all de anon/authenticated).
2. `sql/2026-10-04_for200_2_completa_falha_job_com_raia.sql` — DROP+CREATE de
   `complete_crawler_job`/`fail_crawler_job` com `p_raia`, INSERT condicional no log +
   retenção por tempo, REVOKE+GRANT explícitos pros dois.
3. `sql/2026-10-04_for200_3_rpcs_leitura_graficos.sql` — as 5 RPCs de leitura
   (`crawler_execucoes_recentes`, `pagamentos_consultas_recentes`,
   `crawler_execucoes_por_hora`, `crawler_fila_pendente_tendencia`,
   `erros_por_categoria_24h`) + GRANTs a `anon, authenticated`.

## Fase B — Sandbox local (`sql/sandbox/for200_validate_local.sh`)

Mesmo molde do `for198_validate_local.sh`: Postgres efêmero, schema mínimo pré-FOR-200
(crawler_queue com `erro_categoria` do FOR-198 já aplicado, pagamentos_consultas_log idem),
aplica as 3 migrations em ordem, valida:
- `complete_crawler_job`/`fail_crawler_job` sem `p_raia` → não quebra, não loga (compat).
- Com `p_raia` → loga 1 linha em `crawler_execucoes_log` com os campos certos.
- `fail_crawler_job` com `tentativas+1 < 3` → `terminal=false`; com `>=3` → `terminal=true`.
- CHECK rejeita `resultado`/`erro_categoria` fora da lista.
- GRANTs: `service_role`/`authenticated` têm EXECUTE nas novas assinaturas; `anon` não tem nas
  de escrita, tem nas de leitura.
- `requeue_failed` continua funcionando sem mudança (assinatura intocada).
- As 5 RPCs de leitura retornam o formato esperado com dado de teste inserido manualmente.

## Fase C — Worker (`worker-crawler/src`)

1. `supabase.ts::completeJob`/`failJob` — parâmetro `raia?: number`, repassado como `p_raia`.
2. `index.ts::processBatch` — `completeJob(job.id, lane + 1)` e
   `failJob(job.id, String(err), categoria, lane + 1)`.
3. Rodar a suite de testes do worker isolada (`npm test` em `worker-crawler/`) — nenhuma
   mudança de assertion esperada nos testes existentes (só passagem de parâmetro novo opcional);
   se algum teste mocka `completeJob`/`failJob` com assinatura fixa, ajustar a chamada mockada.

## Fase D — Verificação adversarial (lead, antes do PR)

- Sandbox local: rodar `for200_validate_local.sh`, confirmar TODOS os cenários OK.
- `npm test` isolado em `worker-crawler/` (não só o agregado do monorepo, se houver).
- Ler o diff inteiro de `supabase.ts`/`index.ts` — confirmar que nenhuma lógica de
  retry/circuit-breaker/sessão foi tocada, só a passagem de `raia`.
- Grep final por `complete_crawler_job(` e `fail_crawler_job(` em todo o repo — confirmar que
  `supabase.ts` é o ÚNICO chamador (nenhuma outra integração quebrada pela mudança de
  assinatura).
