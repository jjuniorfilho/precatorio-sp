# FOR-143 — Importar precatórios de dump CSV legado

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md
conforme progride.

> Referência: `context.md` e `architecture.md` nesta mesma pasta. Linear: FOR-143.
> Sem frontend envolvido (script backend one-off) — não há fase de integração Lovable.

**Paralelização**: FASE 1, FASE 2 e FASE 3 são independentes entre si (arquivos diferentes,
sem dependência de código) e podem ser feitas em qualquer ordem ou em paralelo. FASE 4 também
é independente (só lê CSV + faz SELECT, não escreve). FASE 5 depende de 1+2+3+4 (usa tudo).
FASE 6 depende de 5.

## FASE 8 — Import mensal do PDF "Consulta do Total da Dívida Anual" (DEPRE) [Completada ✅]

Trabalho paralelo/relacionado, não faz parte do escopo original de FOR-143 (CSV legado), mas
mora no mesmo branch e mexe na mesma tabela `precatorios`. Objetivo: permitir reimportar
mensalmente os dois relatórios PDF do TJSP (Estado FE001 + Prefeitura SP PM576) sem apagar uma
fonte ao reimportar a outra.

### Schema + RPCs [Completada ✅]

`sql/2026-08-24_import_depre_pdf_schema.sql`: coluna `precatorios.fonte_relatorio`
(`'estado'|'municipio'`), UNIQUE em `processo_depre`, RPCs `precatorios_delete_fonte` e
`precatorios_insert_lote` (SECURITY DEFINER, mesmo padrão de bypass de RLS já usado em
`enqueue_crawler_job`/`merge_legado_*`). Aplicado no SQL Editor antes desta sessão.

### Script de import [Completada ✅]

`worker-crawler/src/import-depre-pdf.ts`: `pdftotext -layout` + parser de linha fixa +
checksum contra o "TOTAL GERAL" impresso no próprio PDF (aborta sem gravar se não bater —
proteção contra erro silencioso de parser). `--apply` sem `--limit` faz delete+reimport
completo da fonte (o PDF já traz o saldo atualizado, não vale a pena diffar linha a linha).

### Execução real [Completada ✅]

Rodado na VPS (mesmo padrão de diretório isolado `/root/for143-*` das fases anteriores —
`.env` real copiado de `/opt/precatorio-worker`, sem tocar no deploy ativo/pm2). Dry-run dos
dois PDFs bateu checksum exato antes de aplicar. Resultado:
- **Estado (FE001)**: 189.107 inseridos, 0 erros, 27,6s.
- **Município (PM576)**: 70.150 inseridos, 0 erros, 9,5s.

Diretório temporário e PDFs apagados da VPS ao final. `.gitignore` atualizado
(`depre_*.PDF`, `query-results-export-*.csv`) — esses arquivos ficaram na raiz do repo local
mas nunca devem ser commitados (financeiro + grandes).

### Achado: 8.819 registros órfãos (`fonte_relatorio IS NULL`) [Pendente — decisão de produto]

A tabela já tinha ~268.004 linhas antes desta carga (import manual anterior, fora do git,
mencionado no comentário do schema). `precatorios_delete_fonte('estado'|'municipio')` só apaga
linhas que **já tinham** aquela fonte marcada — como antes desta carga só 5 linhas tinham fonte
(smoke test), o delete não tocou nas ~268k antigas. O upsert por `processo_depre` casou e
atualizou a maioria (259.257 = 189.107+70.150), sobrando **8.819** que não bateram com nenhum
dos dois PDFs de agosto/2026. Investigado via 3 queries no SQL Editor (worker/Opção B tem RLS
bloqueando SELECT direto nessa tabela também, mesmo padrão já documentado pra
`crawler_queue` — não dá pra verificar por script, só pelo SQL Editor):

- **8.805 desses 8.819** são de uma única batida em `updated_at=2026-06-02` — têm `natureza` e
  `saldo_depre` **reais** (não zero). Como o PDF é "Total da **Dívida** Anual" (débito em
  aberto), sumir da lista de agosto depois de estar na de junho é o sinal esperado de
  **quitação/baixa** entre junho e agosto — dado financeiro real, não lixo.
- **14 restantes** (`updated_at` em 06-05/06-06/06-10) têm `natureza` vazia e `saldo_depre=0`
  — padrão de stub/placeholder de outra origem (provavelmente o crawler criando uma linha ao
  descobrir um `numero_depre` novo, antes de qualquer PDF cobrir aquele registro), não
  relacionado a este import.
- **3.503 dos 8.819** ainda têm um `incidente` ativo linkado por `numero_depre` — apagar em
  massa arriscaria remover o único registro de saldo de um precatório que a base ainda
  rastreia.

**Decisão do usuário**: manter como está por enquanto — não apagar. Como/se rotular "quitado"
na busca pública (ou distinguir esses dois subgrupos) fica como pendência de produto, não
resolvida nesta sessão.

## FASE 7 — Correções do `/engineer:pre-pr` (code review) [Completada ✅]

O `branch-code-reviewer` (rodado antes de abrir a PR) achou **4 problemas críticos** que a
FASE 6 não pegou porque nenhum deles se manifestava no volume/tempo testado até então. Todos
corrigidos e verificados em produção.

### C1 — `next_crawl_at` nunca ficou NULL de verdade [Corrigido ✅]

`classify_processo()` (chamado em todo insert, inclusive pelos LEGADO-) sempre sobrescreve
`next_crawl_at = COALESCE(last_crawled_at, NOW()) + TTL` — com `last_crawled_at=NULL` isso virou
`NOW()+7 dias` pra todos os ~12.126 LEGADO-, contrariando a premissa documentada em
`context.md`/`architecture.md` ("`next_crawl_at=NULL` garante que nunca entram no refresh").
Confirmado em produção: todos com `next_crawl_at ≈ 2026-08-24`. Sem fix, o cron horário
`refresh-stale-hourly` ia enfileirar os 12.126 códigos `LEGADO-...` com `origem='refresh'`
(prioridade MAIOR que `backfill`) a partir de ~23-24/08, o worker falharia sempre (código não
existe no e-SAJ), `fail_crawler_job` reenfileiraria de hora em hora — loop infinito que também
travaria o backfill legítimo pra sempre e arriscava disparar o circuit breaker do worker.

**Fix**: `sql/2026-08-19_for143_exclui_legado_do_refresh.sql` — `enqueue_stale_processos()`
passa a excluir `processo_codigo LIKE 'LEGADO-%'` do CTE de stale. Aplicado em produção e
verificado (`enqueue_stale_processos()` rodado manualmente, 0 jobs `LEGADO-` foram parar em
`crawler_queue`).

### C2 — `reconcileLegado` podia corromper processos não-relacionados [Corrigido ✅]

Dois problemas: (a) renomear `processo_codigo` sem checar se o código real já existe estourava
unique violation e quebrava o crawl pra sempre; (b) o reconcile de `incidentes` era escopado só
por `numero_depre` (não é único — confirmado na FASE 6) sem exigir o mesmo `processo_id`, então
o crawl de um processo A não-relacionado podia sequestrar/corromper um incidente LEGADO- do
processo B só por coincidência de `numero_depre`.

**Fix**: `worker-crawler/src/supabase.ts` — `reconcileLegadoProcesso`/`reconcileLegadoIncidente`
(substituem a antiga `reconcileLegado` genérica): incidentes agora escopados por
`processo_id` + `numero_depre`; quando o código real já existe, faz merge via RPC
(`merge_legado_processo`/`merge_legado_incidente`, em
`sql/2026-08-19_for143_merge_legado_rpcs.sql`) em vez de tentar renomear — reaponta
incidentes/partes pro processo real e apaga a linha LEGADO- (processos), ou descarta
partes/andamentos sintéticos da linha LEGADO- (incidentes, já que o e-SAJ real prevalece).

### C3 — Import criava `processos` LEGADO- duplicado quando já existia real [Corrigido ✅]

`inserirLinha` sempre criava um placeholder `LEGADO-{cnj}` sem checar `processosPorCnj` (que o
próprio script já calcula pro match) — todo CNJ que o crawler já tinha descoberto
organicamente, mas com um incidente novo no CSV, ganhava uma segunda linha `processos` (mesmo
`cnj_normalizado`, sem UNIQUE). Confirmado em produção: **96 duplicatas** (14 numa primeira
checagem parcial + 82 depois de paginar corretamente — `.select()` do Supabase tem limite
implícito de 1000 linhas, a primeira tentativa de limpeza só pegou os 1000 primeiros LEGADO-).

**Fix**: `import-csv-legado.ts` — `inserirLinha` agora recebe `processoRealId` (resolvido a
partir de `processosPorCnj`, separando explicitamente linhas reais de LEGADO-) e reusa o
processo real em vez de criar um novo quando ele existe. As 96 duplicatas já existentes foram
mescladas em produção via `merge_legado_processo` (script one-off, descartado depois).

### C4 — CSV com PII e `claude_legacy/` fora do `.gitignore` [Corrigido ✅]

`precatorio_sp_202608161955.csv` (11MB, CPF sem máscara + nome + data de nascimento de 29.647
pessoas) e `claude_legacy/` (39MB) estavam untracked mas sem entrada no `.gitignore` — um
`git add -A` na hora do PR commitaria os dois. Adicionado ao `.gitignore`:
`precatorio_sp_*.csv` e `claude_legacy/`.

### Deploy em produção [Completada ✅]

Diferente das fases anteriores (testadas em diretórios isolados na VPS), C1-C3 exigiam a
correção rodando de verdade no worker ativo (`pm2 precatorio-crawler`, `/opt/precatorio-worker`)
pra ter efeito — decisão explícita do usuário foi fazer o deploy imediatamente, dado o prazo
real do C1. Processo: copiados só os arquivos alterados (`supabase.ts`, `parse.ts`,
`import-csv-legado.ts`, `package.json` — **não** `reclassify-oc.ts`, que tinha um hotfix de
concorrência só no servidor, não presente no git local — checado via diff de hash antes de
copiar qualquer coisa) → `npx tsc -p tsconfig.json` (build limpo) → `pm2 restart
precatorio-crawler` → confirmado saudável (3 lotes completos pós-restart, `ok=24-25 erro=0-1`,
o único erro é timeout normal de job, mesmo padrão de antes do restart).

### R1-R9 do code review (não críticos) [Completada ✅]

Usuário pediu pra corrigir tudo nesta mesma sessão em vez de deixar como follow-up.

- **R1** (`--dry-run` era opt-out): invertido — agora exige `--apply` explícito pra gravar;
  argumento desconhecido (typo) rejeita com `process.exit(1)` em vez de ser ignorado
  silenciosamente; `--limit` inválido (`0`, não-numérico) também rejeita.
- **R3** (`partes` não idempotente): `inserirLinha` agora apaga `partes` com
  `fonte='csv_legado'` do incidente antes de reinserir — reexecução não duplica mais nos casos
  de `numero_depre` ambíguo.
- **R4** (`classify_processo` por linha, O(n²) num CNJ com N incidentes): dedupado — coleta
  `Set<processoId>` durante a escrita e chama `classifyProcesso` uma vez por processo único, em
  `runPool` separado, ao final.
- **R5** (enqueue não recuperável numa re-execução): `enfileirarBackfillPendente()` agora deriva
  o conjunto a enfileirar direto do banco (`select cnj from processos where processo_codigo like
  'LEGADO-%'`, paginado), não do resultado da rodada atual — uma falha silenciosa de RPC vira
  autocorrigível na próxima execução.
- **R6** (sem validação de valor/CNJ): `parseValorCentavos()` valida formato antes de gravar
  (rejeita vírgula decimal, não-finito); `inserirLinha` valida `cnjNorm.length === 20` antes de
  gravar qualquer coisa.
- **R9** (limpezas): JSDoc desatualizado corrigido, `nature` (lido e nunca usado) removido,
  `CNJ_COLS` renomeado pra `COLS_OBRIGATORIAS`, `coleta_runs` agora fecha em `'erro'` (não fica
  preso em `'running'`) se o processo morrer no meio via `try/catch` em volta da escrita.
- **R2** (`reconcileLegado` pesa em todo crawl, pra sempre): duas mudanças em `supabase.ts` —
  (a) `config.legadoReconcile` (env `LEGADO_RECONCILE`, default `true`) gateia a reconciliação
  inteira, desligável quando os ~12k LEGADO- forem absorvidos; (b) `buscarIncidentesLegadoDoProcesso`
  faz 1 SELECT por processo (não 1 por incidente) — importa especialmente pros processos "mega"
  com milhares de incidentes citados no `config.ts` (FOR-116).
- **R8** (índice ausente pro novo `ORDER BY` de `claim_crawler_jobs`): `sql/2026-08-19_for143_
  indice_claim_prioridade.sql` — índice parcial em `((origem='backfill'), scheduled_at) WHERE
  status='pendente'`, casando a expressão exata do `ORDER BY`.
- **R7** (`classifyEsfera` estendida não retroativa): script one-off (`_backfill_esfera.ts`,
  descartado depois) reclassificou `ente_esfera`/`flag_sp` de processos já crawleados. Rodado
  primeiro em modo relatório: **2.164 candidatos**, dos quais **100% também mudavam
  `flag_sp` false→true** (maioria DETRAN-SP, 67%). Confirmado com o usuário antes de aplicar
  (monotônico — só melhora `'Outro'` pra uma esfera real, nunca reverte uma classificação
  correta). Aplicado com sucesso (confirmado: 0 candidatos restantes numa segunda rodada em
  modo relatório, depois que a conexão SSH caiu no meio da primeira tentativa de apply e não
  deu pra confirmar pela saída do comando).

### Comentários:
- **Achado extra do `branch-master-docs-checker`** (não bloqueante, fora do escopo deste PR
  backend, registrado pra decisão futura): o produto tem um princípio documentado de
  "transparência total" sobre a fonte dos dados (`CUSTOMER_COMMUNICATION.md`), e o CSV
  importado é de um terceiro (não confirmadamente uma cópia do DEPRE oficial) — vale decidir,
  antes de expor esses registros na busca pública, se/como rotular os resultados originados do
  CSV legado de forma diferente, e esclarecer a base legal LGPD pro CPF importado em massa sem
  interação do titular. **Ainda pendente — não tratado nesta sessão.**
- O worker em produção rodava só código commitado antes do FOR-143 mais hotfixes manuais
  (`reclassify-oc.ts`) — nenhum processo de deploy automatizado (CI/CD) existe hoje pra esse
  serviço; todo deploy é manual via scp+build+pm2 restart. Vale documentar isso em algum lugar
  (fora do escopo desta issue).
- **Padrão observado nesta sessão**: a conexão SSH com a VPS caiu no meio de comandos longos
  várias vezes (rede instável, não é bug nosso) — sempre depois de confirmar via uma segunda
  checagem independente (reconectar e reconsultar o estado real no banco) antes de assumir que
  algo falhou ou teve sucesso, nunca confiar só no código de saída de um comando que sofreu
  "Operation timed out"/"Broken pipe".

## FASE 1 — Migrations de schema [Completada ✅]

Duas migrations pequenas e independentes em `sql/`, aplicadas manualmente no SQL Editor
(convenção atual pós-FOR-76).

### Estender `partes.fonte` pra aceitar `'csv_legado'` [Completada ✅]

Criado `sql/2026-08-16_for143_partes_fonte_csv_legado.sql`: `ALTER TABLE partes DROP
CONSTRAINT` do CHECK atual (`partes_fonte_check`, nome padrão do Postgres pra CHECK de coluna
sem nome explícito) + `ADD CONSTRAINT` novo incluindo `'csv_legado'` no `IN (...)`. Aplicado no
SQL Editor e testado pelo usuário — passou.

### Priorizar fila por origem em `claim_crawler_jobs` [Completada ✅]

Criado `sql/2026-08-16_for143_claim_prioriza_nao_backfill.sql`: `CREATE OR REPLACE FUNCTION
claim_crawler_jobs` com `ORDER BY CASE WHEN origem = 'backfill' THEN 1 ELSE 0 END,
scheduled_at` (hoje só `ORDER BY scheduled_at`). Aplicado no SQL Editor e testado pelo usuário
— jobs `manual` saem antes de `backfill` mesmo quando o `backfill` tem `scheduled_at` mais
antigo. Passou.

### Comentários:
- Ambas as migrations já estão no ar em produção (não é preciso reaplicar). O script de
  import (FASE 4/5) já pode contar com `fonte='csv_legado'` disponível e com a fila
  priorizando corretamente.

## FASE 2 — Estender `classifyEsfera()` [Completada ✅]

### Adicionar entidades faltantes ao regex de `classifyEsfera()` [Completada ✅]

`worker-crawler/src/parse.ts:55`. Estadual: `ESTADUAL` (bare — faltava, só `FAZENDA ESTADUAL`
casava antes), USP, UNESP, UNICAMP, IAMSPE, DETRAN, ARTESP, CEETEPS, FDE, FURP, SUCEN, ITESP,
JUCESP, DAEE, DERSA, PROCON, FUNDAÇÃO CASA, HOSPITAL DAS CLÍNICAS, FAMEMA, HCFAMEMA. Municipal:
`MUNICIPAL` (bare), SPTRANS (é municipal, não estadual — São Paulo Transporte S.A. pertence à
cidade), SP-URBANISMO/SÃO PAULO URBANISMO, e um regex à parte pra abreviação `MUN. DE
<cidade>` (institutos de previdência de outros municípios de SP, ex. TATUÍPREV).

### Validar contra os valores reais do CSV [Completada ✅]

Script `tsx` descartável (removido depois) que leu os 59 `debtor_entity` distintos do CSV
(extraídos via `csv.DictReader` do Python, pra evitar erro de parsing manual de CSV com vírgula
dentro de aspas) e aplicou `classifyEsfera()` real (import direto do `parse.ts`, não uma cópia).
Resultado: **56/59 classificadas corretamente** (Estadual/Municipal). As 3 restantes em
`'Outro'` são genuinamente ambíguas e de baixo volume (1-2 linhas cada): "Fundação Memorial da
América Latina", "FUNSERV" (nome truncado no CSV) e "Instituto de Medicina Social e
Criminologia" — aceitável por decisão prévia (fallback `'Outro'` só quando a entidade for
realmente desconhecida).

### Comentários:
- **Bug encontrado e corrigido durante a validação**: a primeira tentativa colocou `MUN\.`
  dentro do mesmo grupo `\b(...)\b` dos outros tokens — mas `\b` logo depois de um `.` nunca
  casa quando seguido de espaço (não-palavra → não-palavra, sem fronteira), então esse token
  nunca funcionava. Fix: regex separado `/\bMUN\.\s*DE\b/` fora do grupo principal. Lição pra
  quem mexer nesse regex de novo: token que termina em pontuação não combina bem com `\b` de
  fechamento do grupo — testar sempre contra dado real, não só ler o regex.
- `tsc --noEmit` limpo depois da mudança.

## FASE 3 — Reconciliação LEGADO → real em `persistTree()` [Completada ✅]

### Implementar reconciliação por `cnj_normalizado`/`numero_depre` [Completada ✅]

`worker-crawler/src/supabase.ts`: nova função `reconcileLegado(table, column, value,
processoCodigoReal)` — `UPDATE {table} SET processo_codigo = :real WHERE {column} = :value AND
processo_codigo LIKE 'LEGADO-%'`. Chamada antes do `upsertReturningId("processos", ...)` (por
`cnj_normalizado`) e antes do `upsertReturningId("incidentes", ...)` de cada incidente (por
`numero_depre`). No-op quando não há linha LEGADO- (0 linhas afetadas) — caso normal de crawl
de processo nunca importado.

### Teste manual da reconciliação [Completada ✅]

Rodado direto em produção, na VPS (`root@31.97.242.130`, deploy em `/opt/precatorio-worker`),
já que não havia credenciais de produção neste ambiente. Processo: copiado `src/` local
(com a mudança) + `package.json`/`tsconfig.json` pra um diretório isolado `/root/for143-test`
na própria VPS (símlink pro `node_modules` já instalado, cópia do `.env` real) — **sem tocar**
no deploy ativo (`/opt/precatorio-worker`, pm2 `precatorio-crawler`, já com 113 restarts,
não arriscar). Script de teste criava uma linha `LEGADO-` de teste em `processos`+`incidentes`
com CNJ/`numero_depre` fake (`9999999-99.2099...`), chamava `persistTree()` com uma árvore com
o mesmo CNJ/depre mas `processo_codigo` "real" de teste, e conferia que a linha foi reconciliada
(mesmo `id`, `processo_codigo` atualizado) em vez de duplicada.

**Resultado: ✅ PASSOU** nos dois casos (`processos` por `cnj_normalizado`, `incidentes` por
`numero_depre`). Diretório de teste e a cópia do `.env` foram apagados da VPS depois; script de
teste local (`_test_reconciliacao.ts`, descartável) também removido.

### Comentários:
- Credenciais SSH da VPS: chave `~/.ssh/mylena_vps_ed25519`, usuário `root`, IP
  `31.97.242.130`. Deploy real do worker fica em `/opt/precatorio-worker` (pm2
  `precatorio-crawler`) — **não editar direto**, sempre testar em diretório isolado como foi
  feito aqui. O deploy de verdade da mudança desta fase (e das próximas) pro
  `/opt/precatorio-worker` fica pra depois, como parte do rollout final da FOR-143 (fora do
  escopo de cada fase individual do plano — decidir com o usuário quando/como fazer o deploy
  real, provavelmente junto da FASE 6).

## FASE 4 — Script de import: leitura, filtro e match (dry-run) [Completada ✅]

### Esqueleto do script + parsing do CSV [Completada ✅]

Criado `worker-crawler/src/import-csv-legado.ts`. Sem lib de CSV nova (não havia nenhuma nas
dependências do worker-crawler) — parser RFC4180 mínimo próprio (aspas, `""` escapado, vírgula
dentro de aspas), validado antes contra o CSV real via `csv.reader` do Python (contagem de
linhas bate, formato confirmado sem quebra de linha dentro de campo). Filtro de completude:
1.255 ignoradas (bate com a investigação anterior).

### Split do CNJ raiz + validação cruzada com `incident_number` [Completada ✅]

`origin_process_number` (`"CNJ/NNNN"`) → `cnjRaiz` + `numeroIncidente`, com log (não bloqueia)
se divergir de `incident_number`.

### Match em lote contra a base (sem escrever nada ainda) [Completada ✅]

Duas queries em lote (`.in(...)`, chunks de 500): `processos` por `cnj_normalizado` →
`Map<cnjNorm, processoId>`; `incidentes` por `numero_depre` → `Map<numeroDepre, {processo_id,
numero_incidente}>`. Match = mesmo `processo_id` nos dois lados **e** `numero_incidente` bate.

### `--dry-run`: relatório sem gravar [Completada ✅]

Rodado na VPS (mesmo diretório isolado das fases anteriores) contra o CSV completo e a base de
produção real.

### Comentários:
- **Bug real encontrado e corrigido durante a validação**: `numero_incidente` vem com padding
  diferente por fonte — banco (crawler e-SAJ) usa **5 dígitos** (`"00003"`), CSV legado usa
  **4** (`"0003"`). Comparação de string exata fazia todo match falhar (0 "já existem" na
  primeira rodada, claramente errado dado que 800 processos e 8.919 incidentes já batiam
  individualmente por cnj/depre). Fix: `normIncidente()` compara pelo valor numérico
  (`parseInt`), não string. **Isso é relevante pra FASE 5 também**: ao gravar `numero_incidente`
  nos novos registros, considerar salvar no mesmo padding de 5 dígitos que o crawler usa, pra
  manter consistência (hoje o plano é gravar o valor cru do CSV — decidir/ajustar na FASE 5).
- **Números finais do dry-run contra produção**: 29.647 lidas · 1.255 ignoradas · **3.633 já
  existem** · **24.759 a inserir** (6.678 delas sem `debtor_entity`). Números bem diferentes da
  estimativa inicial (28.392 candidatas assumia 0 overlap) — bom sinal, mostra que o crawler já
  cobriu ~13% desses casos sozinho.
- Rodado no mesmo diretório isolado da VPS das fases 3/4 (copiado CSV de 11MB via scp — a
  primeira tentativa de transferência caiu no meio por instabilidade de rede, resolvido
  reenviando só o arquivo que faltava). Diretório apagado ao final.

## FASE 5 — Script de import: escrita (insert + andamentos + classify + enqueue) [Completada ✅]

### Upsert `processos` + `incidentes` [Completada ✅]

Implementado como planejado: placeholder `LEGADO-{cnjNorm}` (processos) e
`LEGADO-{cnjNorm}-{numeroIncidente com 5 dígitos}` (incidentes) — `numero_incidente` gravado
com padding de 5 dígitos (`pad5()`) pra bater com a convenção do crawler (achado na FASE 4).

### Insert `partes` (ativa + passiva) [Completada ✅]

`fonte='csv_legado'`, documento do credor normalizado (só dígitos, `null` se vazio).

### Andamentos sintéticos + `classify_processo` [Completada ✅]

Implementado como planejado. `classifyProcesso()` chamado sempre (mesmo sem andamento).

### Enqueue de backfill (dedup) [Completada ✅]

`Set<cnjRaiz>` das linhas inseridas nesta execução → `enqueueJob(cnjRaiz, "backfill")` uma vez
por CNJ único, em `runPool`.

### Concorrência + logging + `coleta_runs` [Completada ✅]

`runPool` local (cópia do padrão de `index.ts`) + `coleta_runs` (`rotina='import_csv_legado'`)
+ `--limit=N` (novo, não previsto originalmente — pra permitir smoke test em escala pequena
antes de rodar os 24.759 completos) + script `import-csv-legado` no `package.json`.

### Comentários:
- **Bug real encontrado e corrigido**: código incluía `next_crawl_at: null` no upsert de
  `incidentes`, mas essa coluna só existe em `processos` — quebrava todo insert de incidente
  (`Could not find the 'next_crawl_at' column of 'incidentes'`). Descoberto no smoke test
  (`--limit=5` contra produção), que também revelou um efeito colateral: os 5 `processos`
  LEGADO- já tinham sido criados antes do erro de `incidentes`, ficando órfãos — precisou
  limpar manualmente antes de corrigir e re-testar.
- **Investigação longa que NÃO era bug**: depois do fix acima, o smoke test rodou limpo (5
  inseridos, 0 erros), mas a verificação de `crawler_queue` pra conferir o enqueue de backfill
  vinha sempre vazia, mesmo pra CNJs inventados na hora. Depois de descartar hipóteses (função
  redefinida, overload, trigger escondido, owner divergente — todos conferidos direto no SQL
  Editor e batendo com o esperado), a causa real apareceu: o client do worker (login admin via
  anon key, "Opção B", sem `SUPABASE_SERVICE_ROLE_KEY") tem RLS bloqueando **SELECT direto**
  em `crawler_queue` — silenciosamente, sem erro, sempre retorna lista vazia. O **INSERT via
  `enqueue_crawler_job` (security definer) sempre funcionou** — confirmado rodando a mesma
  query no SQL Editor (que usa uma conexão privilegiada) e vendo a linha lá. **Lição pra quem
  for debugar essa tabela de novo**: nunca confiar num `SELECT` direto em `crawler_queue` vindo
  do worker/Opção B pra diagnóstico — sempre checar pelo SQL Editor. Isso não é um bug do FOR-143,
  é uma característica pré-existente do RLS dessa tabela (mesmo padrão documentado antes em
  `sql/2026-07-24_reset_orfaos_crawler_queue_rpc.sql`, só que lá era sobre UPDATE).
- **Estado em produção após o smoke test**: os 5 registros do `--limit=5` foram **mantidos**
  (não revertidos) — são dados reais e corretos, não lixo de teste. Os 5 jobs de backfill
  correspondentes já estão na fila (`origem='backfill', status='pendente'`), confirmados via
  SQL Editor; serão processados pelo worker de produção normalmente (capacidade ociosa, conforme
  a priorização da FASE 1), completando a reconciliação testada na FASE 3.
- Faltam **24.754** dos 24.759 registros a inserir (os 5 do smoke test já foram). A execução
  completa fica pra FASE 6.

## FASE 6 — Validação end-to-end e execução real [Completada ✅]

### Dry-run completo + revisão da amostra [Completada ✅]

Rodado contra o CSV completo antes da execução real, números re-confirmados (pequena variação
natural vs. FASE 4 — 3637→3637 já existem, crawler de produção roda em paralelo o tempo todo).

### Execução real [Completada ✅]

Rodado em background na VPS (`nohup`+`disown`, ~85min): **24.755 inseridos, 0 erros, 12.124
CNJs únicos enfileirados pra backfill**. `coleta_runs` registrado (`rotina='import_csv_legado'`,
`status='sucesso'`).

### Teste de idempotência [Completada ✅]

Rodado `--dry-run` de novo após a execução real. Resultado inicial: **25.323 já existem / 3.069
a inserir** — não deveria ter sobrado quase nada. Investigado e corrigido (ver Comentários).
Depois do fix: **28.389 já existem / 3 a inserir** (os 3 são ambiguidade real do CSV, ver
Comentários) — idempotência confirmada pra 99,99% dos casos.

### Smoke test da reconciliação + priorização de fila em produção [Completada ✅ — parcial, ver nota]

Confirmado indiretamente pela combinação dos testes já feitos nas fases anteriores (FASE 1:
priorização testada isolada no SQL Editor; FASE 3: reconciliação testada isolada contra
produção; FASE 5: enqueue confirmado com linhas reais na fila, `origem='backfill',
status='pendente'`). **Não observamos o ciclo completo acontecer ao vivo** — depois de ~2h+
monitorando, o contador de `processos` ainda com prefixo `LEGADO-` não mudeu (ainda 12.126),
porque a fila de maior prioridade (`dje_diario`/`refresh`/`manual`) nunca ficou ociosa nesse
intervalo. Decisão do usuário: aceitar isso como comportamento esperado (sem SLA, já
documentado), não ajustar `claim_crawler_jobs` pra reservar fatia garantida. A reconciliação
vai acontecer organicamente conforme a fila de produção tiver capacidade ociosa.

### Comentários:
- **Bug real encontrado e corrigido no teste de idempotência**: `numero_depre` **não é único**
  na tabela `incidentes` (schema nunca garantiu isso) — confirmado na prática: o mesmo
  `numero_depre` apareceu em 2 incidentes distintos (um nosso, um de um processo real
  não-relacionado descoberto pelo crawler). O `Map<numero_depre, valor único>` usado no match
  guardava só a última linha encontrada pra cada `numero_depre`, perdendo o match certo quando
  havia colisão — explicava os 3.069 falsos "a inserir". **Fix**: `buscarProcessosPorCnjNorm` e
  `buscarIncidentesPorDepre` agora retornam `Map<chave, array>` (todas as linhas, não só a
  última), e o match usa `.some()` pra achar qualquer combinação que bata. **Importante**: os
  dados já gravados nunca ficaram errados por causa disso — a escrita é idempotente pelo nosso
  `processo_codigo` determinístico (`LEGADO-...`), não pelo `numero_depre`; o bug era só na
  detecção de "já existe", então nenhuma limpeza de dados foi necessária, só corrigir o código
  e confirmar de novo.
- **3 registros deliberadamente fora**: casos onde o mesmo par (CNJ raiz + numero_incidente) no
  CSV aparece com **dois `numero_depre` diferentes** (achado via análise do CSV: só 8 grupos
  assim em 28.464 combinações únicas, a maioria já resolvida por acaso na ordem de
  processamento). Como só cabe 1 `numero_depre` por incidente no nosso schema, não dá pra
  decidir automaticamente qual é o certo — deixados de fora, documentados aqui pra revisão
  manual futura se algum dia importar: `0015695-63.2022.8.26.0053/0024`,
  `0007381-07.2017.8.26.0053/0010`, `0022196-67.2021.8.26.0053/0003`.
- **Starvation do backfill**: confirmado na prática (não só teórico) — com o volume real de
  produção, a fila de maior prioridade nunca esvaziou em ~2h de observação. Aceito pelo usuário
  como comportamento esperado; documentado como característica operacional (não bug) do design
  escolhido na FASE 1.
- Diretórios de trabalho temporários na VPS (`/root/for143-test`, `/root/for143-run`) e todos os
  scripts de diagnóstico locais (`_verificar_smoke.ts`, `_diag_duplicado.ts`,
  `_check_legado_count.ts`, etc.) foram removidos ao final de cada fase — nada residual.
- **Nada foi commitado no git ainda** — todas as mudanças (script novo, `supabase.ts`,
  `parse.ts`, `package.json`, migrations em `sql/`) estão só no working tree local.
