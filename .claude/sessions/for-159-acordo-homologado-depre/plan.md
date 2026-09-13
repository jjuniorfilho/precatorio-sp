<plan>
# FOR-159 — Persistir "acordo homologado" (.0500) como flag consultável

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

## FASE 1 — Schema + backfill imediato [Completada ✅]

Cria a coluna e popula o que já dá pra popular sem nenhum novo crawl (os `.0500`
cujo `andamentos` já foi persistido pelo parser novo, commit `2f36e91`, hoje).

### Migration: `sql/2026-09-13_for159_acordo_homologado_coluna.sql` [Completada ✅]

- `ALTER TABLE djen_depre ADD COLUMN IF NOT EXISTS acordo_homologado boolean;`
  (sem `DEFAULT` — novas linhas nascem `null` até o crawl calcular; ver decisão em
  architecture.md).
- `UPDATE djen_depre SET acordo_homologado = exists(select 1 from
  jsonb_array_elements(andamentos) elem where btrim(elem->>'descricao') ilike
  'Comunicado de Acordo de Requisit%') WHERE ficha_crawled_at >= '2026-09-13'::date;`
  — só atualiza quem já foi (re)crawleado com o parser novo (usa `ficha_crawled_at`,
  não a mera presença de `andamentos`, pra não confundir "verificado, sem acordo"
  com "nunca verificado" — ver Limitações do architecture.md).
- Comentário no script explicando a causa raiz (mesmo texto de
  `sql/2026-09-13_diag_acordo_depre.sql`) e "Aplicar no SQL Editor".

### Verificação manual (comentário no fim do script) [Completada ✅]

`select cnj, acordo_homologado from djen_depre where cnj_normalizado =
'01804644220218260500';` — esperado `true` (0180464-42.2021.8.26.0500, o exemplo
confirmado pelo usuário). Incluído como comentário no fim do script, junto com uma
segunda query de progresso (`acordo_homologado is null` vs total).

### Comentários:
- Script ainda NÃO aplicado no banco (sem acesso direto ao Postgres de produção
  nesta sessão) — aguardando o usuário rodar no SQL Editor e validar antes de
  seguir pra Fase 2.
- `add column if not exists` + `where ... and acordo_homologado is null` no UPDATE
  tornam o script idempotente (pode rodar de novo sem efeito colateral se algo
  falhar no meio).

## FASE 2 — Cálculo automático em todo crawl futuro [Completada ✅]

Garante que todo `.0500` (re)crawleado a partir de agora — não só o backfill —
já venha com `acordo_homologado` certo, sem depender de rodar SQL manual de novo.

### `worker-crawler/src/supabase.ts:persistRequisitorio()` [Completada ✅]

- `acordo_homologado` computado via `temAcordoHomologado(andamentos)` (nova função
  pura, ver abaixo) e incluído no `row` do upsert, ao lado de `andamentos`.

### Teste [Completada ✅]

- Refatorado: a lógica ficou como função pura `temAcordoHomologado()` em
  `parse.ts` (não inline em `supabase.ts`), mesmo padrão de `extractPeticoesDiversas`
  — testável sem mock de rede, e reaproveita o mesmo arquivo de teste
  (`parse.test.ts`) das outras funções puras do parser.
- 4 casos novos em `parse.test.ts`: (a) acha o andamento → `true`; (b) outros
  andamentos presentes mas não esse → `false`; (c) lista vazia → `false`
  (verificado, não achou); (d) frase genérica "de acordo com" não gera falso
  positivo (regressão do que o usuário já tinha pego manualmente nesta mesma
  investigação, antes do fix de hoje).
- `npm test`: 55/55 passando. `npx tsc --noEmit`: sem erros.

### Comentários:
- Dependências do `worker-crawler` não vieram do `npm ci` do fleet-provision (esse
  rodou só na raiz do repo) — precisou de `npm ci` manual dentro de
  `worker-crawler/` nesta worktree antes de rodar os testes. Vale considerar
  `FLEET_INSTALL_CMD` customizado em `.claude/fleet.config.sh` pra cobrir os dois
  `package.json` (raiz + `worker-crawler/`) em fleets futuras deste repo.

## FASE 3 — Backfill do restante da base (~55k) [Completada ✅]

Enfileira, sem atropelar prioridade, o resto dos `.0500` que ainda não passaram
pelo parser novo (ficam `acordo_homologado = null` até serem processados).

### `sql/2026-09-13_for159_enfileira_backfill_restante.sql` [Completada ✅]

- Seleciona `cnj` de `djen_depre` onde `acordo_homologado is null`.
- Enfileira via `enqueue_crawler_job_forcado(cnj, 'backfill')` — `origem=
  'backfill'`, não `'manual'` (lição do incidente de hoje mais cedo nesta mesma
  sessão).
- Não chama `priorizar_jobs_manual` — backfill não deve furar fila.
- Idempotente: `ON CONFLICT DO NOTHING` do `enqueue_crawler_job_forcado` cobre
  reexecução e overlap com o lote já rebaixado em
  `sql/2026-09-13_corrige_prioridade_recrawl_0500.sql` mais cedo hoje.

### Script de status (read-only): `sql/2026-09-13_for159_status_backfill.sql` [Completada ✅]

- Query 1: `acordo_homologado is null` (pendente/não) vs. total, com contagem de
  `com_acordo` já confirmados.
- Query 2 (opcional, mais fina): status na `crawler_queue` (pendente/processando/
  ok/erro) só pros `.0500` ainda sem `acordo_homologado`.

### Comentários:
- Ainda NÃO apliquei/enfileirei — script pronto, pendente do usuário rodar no SQL
  Editor (mesmo motivo de sempre: sem acesso direto ao Postgres de produção nesta
  sessão).
- `fleet-gate.sh` genérico não achou lint/test configurado na raiz do repo (os
  scripts reais estão em `worker-crawler/package.json`) — validação de Fase 2 feita
  manualmente (`npm test` + `tsc --noEmit` dentro de `worker-crawler/`). Mesma nota
  de `FLEET_INSTALL_CMD` da Fase 2 vale aqui: um `.claude/fleet.config.sh` com
  `FLEET_GATE_CMDS` apontando pra `worker-crawler/` deixaria isso automático em
  fleets futuras.

</plan>
