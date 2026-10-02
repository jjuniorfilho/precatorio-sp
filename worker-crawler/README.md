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
npm test                  # node:test nativo (Node ≥20), sem dependência nova — tsx --test src/*.test.ts
npm run test:module-mocks # FOR-196 — precisa de Node ≥22.3 (--experimental-test-module-mocks), ver nota abaixo
```
Cobre só **lógica pura, sem I/O** (`classifyEsfera` em `parse.ts`; `parseCsvLine`,
`normIncidente`, `parseValorCentavos`, `agruparPorChave`, `separarJaExistemEAInserir`,
`resolverProcessoRealPorCnj` em `import-csv-legado.ts`), incluindo regressão dos bugs reais
encontrados no code-review do FOR-143 (ver
`.claude/sessions/for-143-importar-precatorios-csv-legado/plan.md`). Exceção (FOR-178):
`src/supabase-persist-tree-legado.test.ts` cobre a **orquestração** da reconciliação LEGADO- do
`persistTree` (raiz + cumprimento + incidente, idempotência) com um banco fake em memória no lugar
de `supabase.from`/`supabase.rpc`; o SQL real das RPCs é validado à parte em
`sql/sandbox/for178_validate_local.sh` (Postgres local descartável). O restante do código que fala
com o Supabase (o próprio `inserirLinha`/`main` do import) **não** tem teste automatizado —
validado manualmente/em produção. `main()` de `import-csv-legado.ts` só
roda quando o arquivo é executado diretamente (`tsx src/import-csv-legado.ts`), nunca ao ser
importado pelos testes.

Exceção (FOR-196): `src/crawl-cumprimento-sintetico.test.ts` cobre a **orquestração** de
`crawlSeed` (as 2 ramificações que criam o cumprimento "sintético") mockando a camada de rede
inteira (`esaj.js`/`comunica.js`/`supabase.js`) via `mock.module` (node:test nativo). Isso exige
o flag `--experimental-test-module-mocks`, só em Node ≥22.3 — por isso roda via
`npm run test:module-mocks` (script dedicado), não no `npm test` default (que seria quebrado em
Node 20/21, violando o piso de versão deste README). Sob `npm test` normal esses 2 testes se
auto-detectam e pulam (skip), em vez de falhar.

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

**Nível do cumprimento (FOR-178):** a linha `processos` `LEGADO-` do import guarda o CNJ do
**cumprimento de sentença**, um nível abaixo da raiz que o crawler descobre (`normalizeToRoot`) —
por isso `reconcileLegadoProcesso` (que casa pelo CNJ da raiz) não a achava e o crawl criava a
hierarquia real em paralelo, duplicando `incidentes.numero_depre`. Agora `persistTree` faz dois
passes: (1) upsert de todos os cumprimentos e, pra cada um, `reconcileLegadoCumprimento` procura
`processos` `LEGADO-` com o mesmo `cnj_normalizado` e chama a RPC
`merge_legado_processo_para_cumprimento` (reaponta incidentes/partes pro processo raiz + cumprimento
reais, apaga a linha legado); (2) monta o Map de incidentes `LEGADO-` do processo e roda o loop de
incidentes, que renomeia/mescla cada legado com o real pelo `numero_depre` (entrada do Map é
consumida — um legado nunca é renomeado duas vezes). A RPC
(`sql/2026-09-29_for178_merge_legado_processo_para_cumprimento.sql`) precisa estar aplicada
**antes** do deploy do worker. Incidentes legado cujo `numero_depre` o e-SAJ não devolve continuam
`LEGADO-`, mas já com `cumprimento_id` preenchido (a equivalência `LEGADO-% ⇔ cumprimento_id IS
NULL` deixa de valer pra eles).

### Ação principal real acima do cumprimento (FOR-195)

A FOR-178 reconcilia o legado até o nível do **cumprimento** — mas o `processos` row resultante
tem, por engano, o CNJ do PRÓPRIO CUMPRIMENTO (não da ação principal real um nível acima),
porque o seed que originou aquela reconciliação foi o próprio CNJ do cumprimento (único dado
que o import tinha) e o climb via `a.processoPrinc` nunca foi tentado a partir da página do
PRÓPRIO cumprimento nesse fluxo (`reconcileLegadoCumprimento` só casa por `cnj_normalizado`
contra uma linha já existente, não dispara crawl novo).

**`fetchProcessoPrincipal`** (`src/crawl.ts`): busca só a página do processo indicado (sem
climb, sem árvore, sem `persistTree`) e segue `a.processoPrinc` — mesmo parser que
`normalizeToRoot` usa, mas limitado a 1-2 páginas. `null` = a própria página já é raiz (regra
espelhada da FOR-196: nada a fazer).

**`reconcilePrincipalReal`** (`src/supabase.ts`): dado o id do `processos` row errado e a capa
da ação principal real (achada via `fetchProcessoPrincipal`), faz upsert do principal em
`processos` (mesmo padrão de `upsertReturningId(..., "processo_codigo")` de `persistTree` — já
é `UNIQUE`, seguro sob concorrência por construção, sem precisar de unique constraint nova em
`cnj_normalizado`) e chama a RPC nova `merge_legado_cumprimento_para_principal`
(`sql/2026-10-02_for195_merge_legado_cumprimento_para_principal.sql`, aplicar **antes** do
deploy): move `cumprimentos`/`incidentes`/`partes` pro principal e converte o antigo "processo"
numa linha `cumprimentos` de verdade (ele É um cumprimento — só estava um nível alto demais).

**Backfill** (`src/backfill-legado-cumprimento-principal.ts`, `npm run
backfill-legado-cumprimento-principal`): script one-off, mesma convenção do
`import-csv-legado.ts` — modo relatório por padrão (`buscarCandidatos`: incidentes `LEGADO-%`
com `cumprimento_id` já preenchido, dedup por `processo_id`), `--apply` obrigatório pra gravar,
`--limit=N` pra smoke test, loop **serial** (concorrência=1, sem `runPool` — cautela com o
e-SAJ/VPS de 1 vCPU pra um backfill pontual, não rede de segurança contra duplicata, que já não
existe). **Confirme a contagem de candidatos do modo relatório contra o ~24.292 esperado (card
FOR-195) antes de qualquer `--apply`.** Nunca dispara sozinho — só roda sob comando explícito do
operador na VPS.

### Valor pago: 3 resultados + log de consultas (FOR-171)

`POST /valor-pago { processo_depre, origem? }` (`origem`: `manual` (default) | `busca_publica` | `crawler`)
devolve `resultado`:

- `encontrado` — linha na grade do portal (com/sem pagamentos).
- `nao_consta` — o portal **respondeu** que o processo não consta na lista (mensagem `#TXTNENHUM`
  visível, grade vazia, rodapé "Data da Consulta"). Resultado válido: marca `pagamentos_consultado_em`.
- `falha` (HTTP 502 com `etapa`) — instabilidade/página inesperada. **Nunca** marca como consultado.

A classificação é `src/pagamentos-classificar.ts` (pura; testada com HTML real do portal em
`src/__fixtures__/pagamentos/`, tokens de sessão redigidos). Cada consulta (inclusive falha) é gravada
em `pagamentos_consultas_log` (últimas 20 por processo, passos com horário/status/etapa) via RPC
`registrar_consulta_pagamento`, em best-effort. Leitura pelo admin: RPC `listar_consultas_pagamento`.

SQL (aplicar em ordem no SQL Editor do banco que o worker usa): `sql/2026-09-25_for171_1_*.sql`,
`_2_*`, `_3_*`. **Antes**, confirmar o banco: `grep SUPABASE_URL /opt/precatorio-worker/.env | cut -c1-40`
(esperado `nxkvfc…`, mesmo projeto do frontend). Se for outro, os SQLs vão para o banco do worker e é
preciso o ramo alternativo (GET de consultas no worker + edge lendo dele) — ver
`.claude/sessions/for-171-crawler-pagamentos-log/architecture.md`.

### Progresso da consulta de valor pago (FOR-173)

Para o admin mostrar uma barra de progresso **real**, a consulta manual publica seu andamento em
`pagamentos_consultas_progresso` (uma linha por DEPRE, sobrescrita a cada consulta) via RPC
`registrar_progresso_consulta_pagamento`. O front lê por `obter_progresso_consulta_pagamento` (só `service_role`).

- **Só `origem: "manual"` grava** (`ORIGENS_COM_PROGRESSO` em `src/pagamentos-tjsp.ts`). Crawler e busca pública não.
- **Estados:** `na_fila` (nasce em `consultarEPersistirPagamentos`, ANTES da fila do Playwright, e renova
  `iniciada_em`) → `em_andamento` (a vez chegou; `PassosCollector.iniciar()`) → `concluida` | `falha`.
- **`etapa` = etapa EM ANDAMENTO.** O coletor registra os passos depois de concluídos, então o reporter
  (`src/pagamentos-progresso.ts`, `proximaEtapa`) converte "concluí X" em "agora está em Y";
  `PassosCollector.tentativa(n)` marca `busca` com a tentativa N sem virar passo do log FOR-171.
- **Nunca derruba a consulta:** as escritas saem em ordem (cadeia serial), erro do `registrar` só vai para o
  console, e fábrica/reporter que lançarem são desligados. O estado final é gravado e drenado (teto de 3s)
  **antes** do log do FOR-171. O `detalhe` nunca leva texto de passo `erro` (mensagem crua de exceção).
- **Linha órfã** (worker morto no meio) fica `em_andamento`; o front trata `atualizado_em` parado > 150s como timeout.
  A RPC de escrita apaga linhas `concluida|falha` com mais de 7 dias.
- **`nova` (renova `iniciada_em`)** vai no `na_fila` e é **reenviado em toda escrita até uma dar certo**: se a do `na_fila` falhar, a seguinte ainda renova (o front reconhece a consulta nova pela mudança de `iniciada_em`).
- **Timeout por escrita:** 5s (`PROGRESSO_TIMEOUT_MS`, `abortSignal`); uma RPC travada não prende as escritas seguintes. Pior caso: o `drenar` segura a resposta HTTP por até 3s no fim da consulta; o front deve tratar a resposta HTTP como a fonte de verdade do fim.
- **Chamada sem `origem`** (`POST /valor-pago` sem o campo) conta como `manual` e, portanto, publica progresso; a busca pública deve mandar `origem: "busca_publica"` (o código do repo manda; confirmar a versão publicada da edge `buscar-precatorio`).
- **Compatível com front antigo:** só grava progresso a mais; o contrato do `POST /valor-pago` não mudou.

Validação dos SQLs em Postgres real, sem tocar em produção: `sql/sandbox/for173_validate_local.sh` (requer `brew install postgresql@15`).

SQL (aplicar em ordem no SQL Editor do banco do worker): `sql/2026-09-28_for173_1_leads_avulso.sql`,
`_2_view_leads_processos_origem.sql`, `_3_tabela_progresso.sql`, `_4_rpcs_progresso.sql`; **depois** deploy do worker
(`git pull`, `npm install`, `pm2 restart` do processo do worker). Inspecionar:
`select * from pagamentos_consultas_progresso order by atualizado_em desc;`

