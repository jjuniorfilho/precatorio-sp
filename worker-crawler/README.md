# worker-crawler — Crawler e-SAJ TJSP (FOR-71)

Worker externo (roda na VPS) que consome a fila `crawler_queue` (FOR-73) e popula a base própria (FOR-69) via **service_role**, classificando cada processo (FOR-72). Estágio 1 — **deslogado**, HTTP puro (e-SAJ `cpopg` é GET, sem captcha; `#tabelaTodasMovimentacoes` já vem no HTML — sem navegador headless).

## Fluxo (loop)
`claim_crawler_jobs(N)` → para cada job: **normaliza à raiz** (`a.processoPrinc`) → desce cumprimentos→incidentes → extrai capa/partes/advogados-OAB/valor/data-base/numero_depre/andamentos → **persiste** (upsert + andamentos idempotentes) → `classify_processo` → `complete_crawler_job` (ou `fail_crawler_job` com retry/backoff).

## Contrato da fila (seed)
- `crawler_queue.processo_codigo` é usado como **seed**. **Recomendado: CNJ** (número unificado `NNNNNNN-DD.AAAA.8.26.FFFF`) — o worker resolve via `search.do` (NUMPROC) e sobe à raiz.
- Se o seed for um código interno e-SAJ, o worker tenta `show.do` direto (precisa do foro; derivado do CNJ quando disponível).
- ⚠️ **Reconciliar com FOR-73:** o `refresh-stale` enfileira `processos.processo_codigo` (código interno). Avaliar enfileirar `processos.cnj` para o worker resolver de forma uniforme. (TODO)

## Rodar
```bash
cp .env.example .env   # preencher SUPABASE_URL + SERVICE_ROLE_KEY (secreta)
npm install
npm run dev            # tsx watch
# produção:
npm run build && node dist/index.js
```
Seed manual p/ teste (no SQL Editor / psql):
```sql
SELECT enqueue_crawler_job('1003169-89.2019.8.26.0073', 'manual');
```

## Testes
```bash
npm test    # node:test nativo (Node ≥20), sem dependência nova — tsx --test src/*.test.ts
```
Cobre só **lógica pura, sem I/O** (`classifyEsfera` em `parse.ts`; `parseCsvLine`,
`normIncidente`, `parseValorCentavos`, `agruparPorChave`, `separarJaExistemEAInserir`,
`resolverProcessoRealPorCnj` em `import-csv-legado.ts`), incluindo regressão dos bugs reais
encontrados no code-review do FOR-143 (ver
`.claude/sessions/for-143-importar-precatorios-csv-legado/plan.md`). O código que fala com o
Supabase (`persistTree`, `reconcileLegadoProcesso`/`reconcileLegadoIncidente`, o próprio
`inserirLinha`/`main` do import) **não** tem teste automatizado — validado manualmente/em
produção, como sempre foi feito neste worker (sem mocks de Supabase; se algum dia isso mudar,
prefira um Supabase local/staging real a mockar o client). `main()` de `import-csv-legado.ts` só
roda quando o arquivo é executado diretamente (`tsx src/import-csv-legado.ts`), nunca ao ser
importado pelos testes.

## Deploy (VPS)
Processo gerenciado por **systemd** ou **pm2**. Env mínimo: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`. Educação com o e-SAJ via `CONCURRENCY`/`DELAY_MS` (conservador por padrão). A `SERVICE_ROLE_KEY` fica **só na VPS**.

## TODO / verificação
- **Validar seletores** de `src/parse.ts` contra páginas reais do e-SAJ (capa, `#tablePartesPrincipais`, `#tabelaTodasMovimentacoes`, `a.processoPrinc`, `a.incidente`) — a doc lista os principais, mas rótulos/ids podem variar.
- Resolver leitura do **código interno da raiz** (`selfCodigo`) — depende do hidden real da página.
- Opção A: incidente placeholder `Indefinido` (`<codigo>#placeholder`) para cumprimento/raiz sem incidente.
- Ler `concurrency/delay` de `coleta_config.params` (hoje via env).

## Referências
- Doc técnica: `../docs/business-context/crawler-tjsp-esaj/Documentacao_Crawler_TJSP_eSAJ.md`
- Schema: FOR-69 · Fila/RPCs: FOR-73 · Classificação: FOR-72

## Valor pago — portal "Pagamentos Precatórios" (FOR-102)
Consulta a situação/pagamentos reais de um requisitório `.0500` no portal TJSP
(`pesquisainternetv2.aspx`, GeneXus). Diferente do crawler e-SAJ acima: é **síncrono**,
sob demanda (não roda no loop de `claim/crawl/persist`), e usa **Playwright** — o portal
é uma aplicação AJAX própria com sessão/estado que não deu pra replicar via HTTP puro
(bateu em `440 Session timeout` consistentemente; ver `.claude/sessions/for-102-valor-pago-crawler/plan.md`
Fase 3 pra detalhes da investigação).

**Módulos:**
- `src/pagamentos-tjsp.ts` — navegação completa (sessão → busca por `processo_depre` →
  captcha → grade de resultado → PDF "Pagamentos do Processo"). `consultarEPersistirPagamentos`
  já persiste no Supabase (`precatorios_pagamentos` + `precatorios.pagamentos_consultado_em`)
  — é essa a função que os callers (abaixo) devem chamar, não `consultarPagamentos` direto.
- `src/captcha.ts` — OCR leve (`tesseract` + `convert`/ImageMagick via CLI, não libs Node) —
  ~50% de acerto por tentativa, mas o captcha é de graça pra recarregar, então o retry
  (dentro de `pagamentos-tjsp.ts`) compensa (~87,5% acumulado em 3 tentativas).
- `src/fila.ts` — serializa todo acesso ao Playwright (concorrência 1) — a VPS tem só 1
  vCPU/~2GB livres, compartilhada com outros serviços (`comunica-web-api`,
  `comunica-saas-api`); rodar múltiplos Chromiums em paralelo arrisca derrubar tudo.
- `src/http-server.ts` — expõe `POST /valor-pago { processo_depre }` (Node `http` nativo),
  autenticado via header `X-Worker-Secret` (env `WORKER_HTTP_SECRET`). Escuta só em
  `127.0.0.1:${HTTP_PORT}` — sobe junto com o loop principal (`startHttpServer()` em
  `index.ts`, antes de entrar no `claim/crawl/persist`), não é um processo separado.

**Dependências de sistema na VPS** (fora do `npm install`) — instalar antes do deploy:
```bash
apt-get install tesseract-ocr tesseract-ocr-por tesseract-ocr-eng imagemagick poppler-utils
npx playwright install --with-deps chromium
```

**Exposição pública (produção):** o `http-server.ts` só escuta em loopback — quem expõe pra
fora é um site nginx dedicado + Let's Encrypt em `crawler.forjuris.com.br` → proxy pra
`127.0.0.1:${HTTP_PORT}` (`proxy_read_timeout 300s`, acima do default de 60s — a consulta
real com retry de captcha pode passar disso). Config de referência em
`infra/nginx-crawler-worker.conf` (o arquivo real vive só na VPS,
`/etc/nginx/sites-enabled/`).

**Callers:**
- `supabase/functions/buscar-precatorio` (busca pública) — síncrono, a cada busca que bate
  num `.0500`, sem TTL/cache (decisão deliberada — ver plan.md).
- `supabase/functions/disparar-valor-pago` (disparo manual no `/admin/processos/:id`) —
  ponte fina, só existe pra manter `WORKER_HTTP_SECRET` fora do browser.
- Ambas as edge functions deployam via Lovable AI (API interna, não git) — atualizar o
  código aqui não propaga sozinho, precisa levar manualmente.

**Titular do requisitório:** `crawlRequisitorio`/`persistRequisitorio` (no crawler e-SAJ
acima, não neste módulo) já captura o nome do requerente (Reqte) toda vez que visita a
ficha de um `.0500` e grava em `djen_depre.titular_nome` — não depende do módulo de
pagamentos. Documento (CPF/CNPJ) nunca vem da ficha (TJSP não expõe); só é gravado
(`djen_depre.titular_documento`) quando o próprio titular busca por ele publicamente.

**Pendente (Fase 8):** validar taxa de sucesso do OCR contra volume real de produção antes
de decidir entre manter OCR ou plugar 2captcha como fallback (interface já isolada em
`captcha.ts` desde a Fase 2 pra trocar sem mexer no resto).

## Ingestão DJEN na VPS (FOR-70) — contorna 403 de IP
A API do Comunica/PJe bloqueia IP de datacenter da edge function (403). Por isso a
ingestão roda **aqui na VPS** (mesma do projeto Vitis/RN, IP aceito pelo PJe):

```bash
npm run ingest                              # ontem
npm run ingest -- --date=2026-06-27         # um dia específico
npm run ingest -- --from=2025-01-01 --to=2026-06-27 --backfill   # backfill (loop por dia)
# produção: node dist/ingest-djen.js --date=...
```
Lê `coleta_config.caderno_dje` (classes/itens_por_pagina), flag SP por parte passiva,
enfileira e-SAJ em `crawler_queue` (RPC `enqueue_crawler_job`), parqueia eproc em
`eproc_pendentes`, grava `djen_dias`/`coleta_runs`. Idempotente por dia.

### Agendar o diário (cron da VPS, ex.: 05:10 BRT)
```cron
10 8 * * *  cd /caminho/worker-crawler && /usr/bin/node dist/ingest-djen.js >> ingest.log 2>&1
```
(08 UTC ≈ 05 BRT). Mantém o crawler (`node dist/index.js`) rodando em paralelo via pm2/systemd.

### Desligar o cron da edge function (já que a ingestão agora é na VPS)
No SQL Editor:
```sql
SELECT cron.unschedule('caderno-dje-diario');
```

## Import de CSV legado (FOR-143)
Script **one-off** (`src/import-csv-legado.ts`) que importou um dump CSV legado de
precatórios de terceiro (`precatorio_sp_*.csv`, fora do git — ver `.gitignore`) pra preencher
lacunas na base própria. Compara em lote contra `processos`/`incidentes` existentes e insere só
o que falta — nunca sobrescreve dado real. Já rodado contra o dump completo em produção
(24.755 registros inseridos, 0 erros); documentado aqui só pra quem precisar reexecutar,
adaptar pra outro dump, ou entender os efeitos colaterais no crawler (abaixo). Não faz parte do
loop `claim/crawl/persist`.

```bash
# modo relatório (padrão — nunca grava, mesmo sem passar nada):
npm run import-csv-legado -- --csv=../precatorio_sp_202608161955.csv

# grava de verdade — --apply é obrigatório, opt-in explícito (não é --dry-run quem decide):
npm run import-csv-legado -- --apply --csv=../precatorio_sp_202608161955.csv

# smoke test em escala pequena antes de rodar o dump completo:
npm run import-csv-legado -- --apply --csv=../precatorio_sp_202608161955.csv --limit=5
```

**Convenção `LEGADO-`:** processos/incidentes que só existem no CSV (sem `processo_codigo`
real do e-SAJ) são gravados como `processos.processo_codigo = 'LEGADO-{cnj_normalizado}'` e
`incidentes.processo_codigo = 'LEGADO-{cnj_normalizado}-{numero_incidente}'`. Se você encontrar
esse prefixo debugando o crawler, é isso — não é lixo nem bug. `next_crawl_at=NULL` nesses
processos é deliberado: `enqueue_stale_processos()` os exclui explicitamente do cron de refresh
(`sql/2026-08-19_for143_exclui_legado_do_refresh.sql`), já que o código não existe no e-SAJ e o
worker falharia sempre.

**Reconciliação permanente em `persistTree()` (`src/supabase.ts`):** quando o crawler descobre
organicamente um processo/incidente que já tinha uma linha `LEGADO-`, `reconcileLegadoProcesso`/
`reconcileLegadoIncidente` reapontam `incidentes`/`partes` pro processo real e apagam (ou
mesclam via RPC `merge_legado_processo`/`merge_legado_incidente`, se o código real já existia)
a linha `LEGADO-` — em vez de deixar duas linhas pro mesmo CNJ/requisitório. Isso roda em **todo**
crawl (1 SELECT extra por processo), gateado por `config.legadoReconcile` (env
`LEGADO_RECONCILE`, default `true` — ver `.env.example`). Pode ser desligado depois que os
`LEGADO-` remanescentes forem absorvidos pelo backfill, já que a partir daí vira overhead morto.
