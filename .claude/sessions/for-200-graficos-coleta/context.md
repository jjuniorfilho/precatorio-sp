# Context: FOR-200 — /admin/coleta/graficos (aba "Ao vivo", 7 cards por robô)

> Modo autônomo (fleet-orchestration). A decisão de arquitetura central (tabela de log
> append-only, não Supabase Realtime) já foi tomada pelo humano (comentário de 2026-10-04 na
> issue). Este documento não reabre Gate 1 nessa parte — só registra o entendimento e o
> desenho concreto (que é escopo deste agente) para a implementação.

## Motivação

Protótipo iterado com o usuário (artifact `8PPH95e6pLSGeqWL3WKSPG`, artboard `Graficos.dc.html`,
aba "Ao vivo") pede: 2 gráficos de janela 24h, 1 painel de erro por categoria, e 7 cards (um por
robô), dos quais só 3 processam item a item continuamente (Crawler e-SAJ, Consulta DEPRE/.0500,
Consulta de pagamento TJSP) — só esses têm indicador "ao vivo" de verdade + feed ≥10 linhas. Os
outros 4 rodam 1x/dia (cron) ou sob demanda — mostram só a última execução, parada.

## Decisão já tomada (não é Gate 1 de novo)

Tabela de log append-only (Opção A), mesmo padrão de `pagamentos_consultas_log` (FOR-171/198):
1 INSERT por job concluído (ok/erro), nunca UPDATE in-place. Motivo documentado no comentário:
`crawler_queue` reusa a MESMA linha durante o ciclo de vida do job (UPDATE in-place,
pendente→processando→ok/erro) — Realtime nela dispararia múltiplos eventos por execução e não
sobrevive a F5.

## Achado real: NEM TUDO precisa de tabela nova

Investiguei os 3 robôs "contínuos" antes de desenhar, pra não duplicar o que já existe:

1. **Crawler e-SAJ** e **Consulta DEPRE (.0500)** são o MESMO pipeline (`worker-crawler/src/
   index.ts::processBatch`, mesma `crawler_queue`, mesmas RPCs `complete_crawler_job`/
   `fail_crawler_job`) — só se distinguem por `isDepre(job.processo_codigo)` (sufixo
   `.8.26.0500`, `esaj.ts:72`). `crawler_queue` já guarda `processo_codigo`/`erro_categoria`
   (FOR-198) mas **nunca guardou a raia** (lane) que processou o job — só existe em memória no
   worker (`lanes[]`, `index.ts`). Isso sim precisa de tabela nova (decisão da issue).
2. **Consulta de pagamento TJSP** (`pagamentos-tjsp.ts`) já grava 1 linha por consulta em
   `pagamentos_consultas_log` (FOR-171, estendida com `erro_categoria` no FOR-198) — já É uma
   tabela de log append-only, já no padrão que a decisão pede. Não tem raia (1 por vez,
   Playwright) — bate exatamente com a issue ("Consulta de pagamento não tem raia"). **Reuso
   total, sem migration nova** — só uma RPC de leitura nova (lista global, não por processo).
3. Os 2 gráficos agregados ("Execuções por hora", "Fila pendente") **não precisam da tabela
   nova** — dá pra computar direto de `crawler_queue.status`/`updated_at`/`created_at`, que já
   são atualizados nos pontos certos pelas RPCs existentes:
   - "Execuções por hora" (sucesso/erro): `status IN ('ok','erro')` são estados TERMINAIS (nunca
     mais mudam depois de alcançados) — `updated_at` é o timestamp real da conclusão. Mesma
     lógica que `crawler_ritmo_processamento` (FOR-108) já usa pra 'ok'; só falta agregar 'erro'
     também (RPC nova, não quebra a existente que o `/admin/coleta` atual consome).
   - "Fila pendente ao longo do dia": reconstruído por hora a partir de `created_at` (entrada na
     fila) + `updated_at` de linhas já terminais (saída da fila) — nenhum job "pendente" perde
     esse status sem passar por `complete_crawler_job`/`fail_crawral_job` tocando `updated_at`,
     então dá pra saber quantos jobs "ainda não tinham saído da fila" em qualquer hora passada
     sem precisar de snapshot periódico (que seria infraestrutura nova — pg_cron — fora do que
     foi decidido). Detalhe exato no architecture.md.
4. "Erros por categoria (24h)": agrega as DUAS fontes que já têm `erro_categoria` (FOR-198) —
   `crawler_queue` (status='erro', terminal) + `pagamentos_consultas_log` (resultado='falha').

**Única tabela nova real:** log das execuções de `crawler_queue` (cobre os robôs #1 e #2).
Reduz o raio de uma 2ª tabela/mais uma superfície de escrita no worker.

## Os 4 robôs periódicos (sem tabela nova — já existe em `coleta_runs`)

Rotinas confirmadas por grep em `worker-crawler/src/*.ts`:
- Ingestão DJE → `rotina = 'caderno_dje'` (ou `'backfill'`, filtrado fora) — `ingest-djen.ts`.
- Ingestão DJE Federal → `rotina = 'caderno_djen_' + tribunal.toLowerCase()` (ex.
  `caderno_djen_trf1`..`trf6`) — `ingest-djen-federal.ts:279`. Card mostra a execução mais
  recente entre QUALQUER tribunal (`rotina LIKE 'caderno_djen_%'`).
- Ingestão por OAB → DOIS scripts gravam rotinas distintas: `ingest_oab` (via Comunica,
  `ingest-oab.ts`) e `ingest_oab_cpopg` (via cpopg direto, `ingest-oab-cpopg.ts`) — tela
  `/admin/consulta-oab` (memória "Consulta OAB ad-hoc") pode disparar qualquer um dos dois ao
  longo do tempo. Card mostra a mais recente das duas.
- Refresh de ativos → `rotina = 'refresh_ativos'` (`refresh-ativos.ts`) — já consumida hoje em
  `/admin/coleta` (`admin.coleta.tsx` linha 74, `coleta-runs-refresh-ativos`).

RPC de leitura já existe (`coleta_runs_recentes`, FOR-108) — só precisa ser chamada com os
`p_rotina`/padrões certos (ou um `p_rotina_prefixo` novo pro caso `caderno_djen_%`/`ingest_oab%`).

## O que NÃO está no escopo

- Supabase Realtime (decisão já rejeitada).
- Snapshot periódico (pg_cron) de profundidade de fila — decisão evitada: a tendência da fila
  pendente é RECONSTRUÍDA matematicamente do que já existe (`crawler_queue`), não uma 2ª
  superfície de escrita nova. Ver architecture.md para a fórmula exata e suas limitações.
- Reaproveitar RPC do FOR-199 — não existe branch/PR da FOR-199 no momento desta sessão
  (confirmado: `gh pr list --search "FOR-199"` vazio). RPC de erro-por-categoria construída do
  zero aqui, independente.
- Mudar `/admin/coleta` (aba "Visão geral") — só adiciona a aba nova "Ao vivo" ao lado.

## Arquivos relevantes (confirmados por leitura real)

- `worker-crawler/src/index.ts` — `processBatch`/`runPool` (lane 0-based, `config.concurrency`),
  pontos de chamada de `completeJob`/`failJob`.
- `worker-crawler/src/supabase.ts` — `completeJob`/`failJob` (TS wrappers das RPCs).
- `worker-crawler/src/erro-categoria.ts` — `ErroCategoria`/`ERRO_CATEGORIAS` (7 categorias,
  reusadas tal qual no CHECK da tabela nova).
- `worker-crawler/src/esaj.ts:72` — `isDepre()` (regex `\.8\.26\.0500$`).
- `supabase/migrations/20260627195519_for73_fila_crons_monitor.sql` — schema original de
  `crawler_queue`/`complete_crawler_job`/`fail_crawler_job`.
- `sql/2026-10-04_for198_1_erro_categoria_crawler_queue.sql` — estado atual de
  `fail_crawler_job` (3 parâmetros, já com `p_categoria`) — base pro DROP+CREATE desta sessão
  (passa a 4: `+ p_raia`).
- `sql/2026-07-24_for108_observabilidade_coleta_rpcs.sql` — `crawler_ritmo_processamento`,
  `crawler_queue_status_counts`, `coleta_runs_recentes` (padrão RPC `security definer` já usado
  pro admin anônimo; novas RPCs desta sessão seguem o mesmo molde).
- `sql/2026-09-25_for171_1_tabela_pagamentos_consultas_log.sql` +
  `..._3_rpc_listar_consultas_pagamento.sql` — schema + RPC de leitura por-processo já
  existentes (nova RPC desta sessão é a versão "global, mais recentes" para o card).
- `frontend/src/lib/api/coleta.ts` — padrão de cliente RPC (`db.rpc`) + `ROTINA_LABEL`.
- `frontend/src/routes/admin.coleta.tsx` — rota existente "Visão geral" (layout/estilo a seguir
  na aba nova).

## Volume/retenção (achado real, não suposição)

`config.concurrency` default 3, mas produção roda `CONCURRENCY=6` (comentário em
`index.ts`/prototype: "conc=6"); `claimBatch` default 25; `delayMs` 400ms entre jobs por raia.
Em regime de fila cheia (backfill), 6 raias × ~1 job/(400ms+tempo de rede) é a ordem de grandeza
de throughput — poucas dezenas de milhares de linhas/dia no pior caso. Retenção por tempo (3
dias, igual ou maior que a janela de 24h que a tela usa) é suficiente e mais simples que o
padrão "últimas 20 por processo" de `pagamentos_consultas_log` (que faz sentido por processo,
não por robô agregado).
