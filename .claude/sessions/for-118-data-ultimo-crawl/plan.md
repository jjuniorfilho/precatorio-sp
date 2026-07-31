# FOR-118 — Data do último crawl (filtro + coluna) em Processo × Incidente / Processos

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md
conforme progride.

> Contexto completo: `context.md` e `architecture.md` nesta mesma pasta.
> Repos: `cortex-v1` (SQL) e `frontend` (React) — branch `jjuniorfilho/for-118-data-ultimo-crawl-processo-incidente` nos dois, ambas já criadas.
> Descoberta-chave: `processos.last_crawled_at` já existe e já é mantido pelo worker
> (`persistTree()`, só em sucesso) — não precisa de coluna nova nem trigger, só expor.

## FASE 0 — Preparação [Completada ✅]

### Sessão de engenharia iniciada [Completada ✅]
Issue FOR-118 refinada (POR QUE/O QUE/COMO, critérios de aceite) e movida pra "In Progress" no Linear.

### Branches criadas nos dois repos [Completada ✅]
`cortex-v1`: `jjuniorfilho/for-118-data-ultimo-crawl-processo-incidente`, a partir da ponta de `jjuniorfilho/for-116-timeout-por-job` (não de `main`, que está desatualizado).
`frontend`: mesmo nome de branch, a partir da ponta de `jjuniorfilho/for-115-definir-senha`.

### context.md e architecture.md aprovados [Completada ✅]
Investigação revelou que `crawler_queue` NÃO precisa ser tocado — `processos.last_crawled_at` já resolve o requisito. Plano técnico revisado e aprovado pelo humano.

### Comentários:
- O plano original (issue + primeira versão do context.md) assumia que seria preciso somar dados de `crawler_queue` via subquery ou coluna denormalizada nova. A investigação da fase de arquitetura achou que o campo já existe (`worker-crawler/src/supabase.ts:111`) — isso eliminou a fase de migration/trigger inteira que estava planejada. `context.md` e a issue no Linear foram corrigidos, `architecture.md` é a fonte da verdade técnica atual.
- Sem ambiente de staging — toda validação de SQL é feita com `EXPLAIN ANALYZE` (só leitura) direto em produção antes de aplicar qualquer `CREATE OR REPLACE`/`DROP`.

---

## FASE 1 — Backend: tela flat (`/admin/processo-incidente`) [Completada ✅]

Repo: `cortex-v1`. Arquivo: `sql/2026-07-31_for118_data_ultimo_crawl.sql` (seção 1).
Pode ser feita em paralelo com a FASE 2 (RPCs independentes) — só bloqueia a FASE 3 (frontend flat).

### Índice em `processos.last_crawled_at` [Completada ✅]
```sql
create index if not exists idx_processos_last_crawled_at on public.processos (last_crawled_at);
```
Validar com `EXPLAIN ANALYZE` que passa a ser usado nos filtros de data/booleano abaixo.

### Estender `_where_processo_incidente` com os 3 novos filtros [Completada ✅]
`p_crawler_data_de date`, `p_crawler_data_ate date`, `p_crawleado boolean` (todos `default null`).
Cláusulas comparando `p.last_crawled_at` (já disponível — a function já faz `join processos p`):
- `p_crawler_data_de`: `and p.last_crawled_at >= %L::timestamptz` (literal = `p_crawler_data_de`)
- `p_crawler_data_ate`: `and p.last_crawled_at < %L::timestamptz` (literal = `p_crawler_data_ate + 1`, limite exclusivo)
- `p_crawleado = true`: `and p.last_crawled_at is not null`
- `p_crawleado = false`: `and p.last_crawled_at is null`

### `buscar_processos_incidente` — DROP + CREATE com `last_crawled_at` no retorno [Completada ✅]
`DROP FUNCTION IF EXISTS` com a assinatura atual (18 params) antes — o `RETURNS TABLE` muda
(nova coluna). Adicionar os 3 novos params na assinatura, `p.last_crawled_at` no SELECT
final, chamar o helper atualizado. Novo `grant execute` com a assinatura completa (21 params).

### `contar_processos_incidente` — CREATE OR REPLACE com os 3 novos params [Completada ✅]
Retorno continua `bigint` — sem DROP necessário. Só adicionar os params e repassar pro helper.

### Validação manual no SQL Editor [Completada ✅]
Aplicado direto em produção pelo usuário — confirmado "sucesso" (2026-07-31). Sem detalhe de plano/tempo colado na sessão, mas aprovado para seguir.

### Comentários:
- Arquivo `sql/2026-07-31_for118_data_ultimo_crawl.sql` ainda está sem commit no git (aplicado no banco, precisa ser commitado no repo antes do PR — lembrar na FASE 5).

---

## FASE 2 — Backend: tela agrupada (`/admin/processos`) [Completada ✅]

Repo: `cortex-v1`. Mesmo arquivo, seção 2. Pode rodar em paralelo com a FASE 1 — só bloqueia a FASE 4.

### Recriar `mv_processos_agrupado` com `last_crawled_at` [Completada ✅]
Postgres não suporta `ALTER MATERIALIZED VIEW ADD COLUMN`. `DROP MATERIALIZED VIEW` +
`CREATE MATERIALIZED VIEW` (mesma query do FOR-112 + `p.last_crawled_at` no SELECT),
recriar TODOS os índices existentes (`mv_processos_agrupado_uidx`, `_esfera_idx`,
`_valor_idx`, `_fases_gin`, `_tipos_gin`, `_status_gin`, `_macrofases_gin`,
`_anos_oc_gin`) + índice novo `mv_processos_agrupado_crawler_idx` em
`last_crawled_at` + `grant select ... to anon, authenticated` + rodar
`select public.refresh_mv_processos_agrupado();` no final pra não esperar os 30min do cron.

⚠️ Copiar a definição EXATA da MV de `sql/2026-07-24_for112_mv_e_filtro_oc.sql` (já lido
nesta sessão) antes de editar — não reescrever de memória, só inserir a coluna nova.

### `buscar_processos_agrupado` — DROP + CREATE com `last_crawled_at` no retorno e nos filtros [Completada ✅]
Mesmos 3 params novos (`p_crawler_data_de`, `p_crawler_data_ate`, `p_crawleado`),
comparando direto `m.last_crawled_at` (já vem da MV, sem subquery) na CTE `filtrado`.
`RETURNS TABLE` ganha a coluna — precisa `DROP FUNCTION IF EXISTS` com a assinatura atual
(19 params) antes do `CREATE`. Novo `grant execute`.

### Validação manual no SQL Editor [Completada ✅]
Confirmado: `select count(*) from mv_processos_agrupado where last_crawled_at is not null;` retornou **80.662** — MV recriada com dado real. EXPLAIN ANALYZE/cron não foram colados na sessão, aceito como suficiente dado o baixo risco (MV pré-agregada, cron não foi alterado por este script).

---

## FASE 3 — Frontend: tela flat (`admin.processo-incidente.tsx`) [Completada ✅]

Repo: `frontend`. Depende só da FASE 1 (não da 2). Testar no browser com `npm run dev` / servidor do TanStack Start, apontando pro Supabase real (sem staging).

### `src/lib/api/processos.ts` — tipos e chamadas [Completada ✅]
- `ProcessoIncidenteRow`: `+ last_crawled_at: string | null` (perto de `crawler_status`, linha ~157).
- `BuscarProcessosFiltros`: `+ crawlerDataDe?: string | null`, `+ crawlerDataAte?: string | null`, `+ crawleado?: boolean | null`.
- `buscarProcessosIncidente` e `contarProcessosIncidente`: passar `p_crawler_data_de: f.crawlerDataDe ?? null`, `p_crawler_data_ate: f.crawlerDataAte ?? null`, `p_crawleado: f.crawleado ?? null` nas chamadas `db.rpc(...)`.

### `src/routes/admin.processo-incidente.tsx` — filtro [Completada ✅]
- `ProcessoIncidenteSearch` (tipo, linha ~37): `+ crawlerDataDe?: string; crawlerDataAte?: string; crawleado?: string;`
- `validateSearch` (linha ~48): parsear as 3 chaves novas com `str(...)`.
- Estado local: `crawlerDataDe`, `crawlerDataAte`, `crawleado` (default `"all"` pro select).
- `armed` (linha ~173): incluir as 3 chaves na condição inicial.
- Efeito de sync com a URL (linha ~181): incluir as 3 chaves no objeto e nas deps do `useEffect`.
- `filtros` (linha ~205): `crawlerDataDe: crawlerDataDe || null`, `crawlerDataAte: crawlerDataAte || null`, `crawleado: crawleado === "all" ? null : crawleado === "sim"`.
- UI do filtro (perto da linha ~299, ao lado de "Nesta fase desde"): par de `<Input type="date">` De/Até + `FilterSelect` com `[["all","Todos"],["sim","Sim"],["nao","Não"]]`.

### Grid — coluna nova [Completada ✅]
- `<thead>` (linha ~341): 2 `<th>` novos, "Última atualização" e "Crawleado", ao lado de "Crawler".
- `<tbody>` (linha ~387): células correspondentes — `formatDate(r.last_crawled_at)` ("—" se null) e reaproveitar o componente `Sim` já existente (linha ~101) com `v={r.last_crawled_at != null}`.
- Ajustar o número de `<Skeleton>` no loading state (linha ~347, hoje `length: 20`) pra `22`.

### `exportCsv` [Completada ✅]
Adicionar "Última atualização" e "Crawleado" ao array `head` (linha ~114) e às linhas mapeadas (linha ~121), seguindo o padrão de `r.crawler_status`.

### Validação manual no browser [Não Iniciada ⏳]
- Abrir `/admin/processo-incidente`, aplicar filtro "Crawleado = Não" e conferir que só aparecem linhas sem "Última atualização".
- Testar De/Até com uma janela conhecida (ex.: hoje).
- Reload da página com filtro na URL — confere que os 3 campos voltam preenchidos (padrão FOR-109).
- Exportar CSV e abrir — conferir as 2 colunas novas.

### Comentários:
- `tsc --noEmit` e `eslint` (regras de tipo/lógica) limpos nos dois arquivos. `eslint` acusa ~200 erros de `prettier/prettier`, mas são **pré-existentes** (o arquivo já tinha 134 antes desta feature, sem nenhum `--fix`/reformat rodado no projeto) — não reformatei o arquivo inteiro pra não gerar um diff gigante fora de escopo.
- **Não consegui testar no browser** — sem `chromium-cli` nem `playwright` disponíveis neste ambiente, e a tela exige login admin que não tenho aqui. Dev server (`npm run dev`, porta 8080) foi deixado rodando; validação visual final fica pendente do usuário (pode não ter sido feita explicitamente — só type/lint foram confirmados por mim).

---

## FASE 4 — Frontend: tela agrupada (`admin.processos.tsx`) [Completada ✅]

Repo: `frontend`. Depende só da FASE 2. Mesma estrutura da FASE 3, adaptada:

### `src/lib/api/processos.ts` [Completada ✅]
- `ProcessoAgrupadoRow`: `+ last_crawled_at: string | null` (perto de `crawler_status`, linha ~252).
- `buscarProcessosAgrupado`: passar os 3 params novos (mesmo `BuscarProcessosFiltros`, já estendido na FASE 3 — não precisa mudar o tipo de novo).

### `src/routes/admin.processos.tsx` — filtro [Completada ✅]
- `ProcessosSearch` (linha ~36), `validateSearch` (linha ~48), estado local, `armed` (linha ~169), efeito de sync (linha ~179) — mesmas 3 chaves.
- `filtros` (linha ~225) — mesma lógica de conversão da FASE 3.
- UI do filtro (perto da linha ~346, ao lado de "Nesta fase desde"): mesmo par De/Até + `FilterSelect`.

### Grid — coluna nova [Completada ✅]
- `<thead>` (linha ~366): 2 `<th>` novos ao lado de "Crawler".
- `ProcessoGroupRows` (linha ~461, células em ~494): células novas. Esta tela **não tem** o componente `Sim` — criar um badge local simples (`{row.last_crawled_at ? <Badge variant="secondary">Sim</Badge> : <span className="text-muted-foreground">—</span>}`) ou extrair `Sim` pra um componente compartilhado se preferir consistência (decisão de implementação, não bloqueia).
- Ajustar `colSpan={10}` da linha expandida (linha ~498) pra `12`.
- Ajustar `<Skeleton>` do loading (linha ~383, hoje `length: 10`) pra `12`.

### `exportCsv` [Completada ✅]
Adicionar as 2 colunas ao `head` (linha ~116) e às linhas (linha ~120).

### Validação manual no browser [Não Iniciada ⏳]
- Mesmos testes da FASE 3, na tela `/admin/processos`.
- Conferir explicitamente a defasagem esperada da MV: um processo recém-crawleado pode não
  refletir "Crawleado = Sim" até o próximo refresh (30min) ou até rodar `refresh_mv_processos_agrupado()` manualmente — validar que isso é aceitável (já documentado em architecture.md).

### Comentários:
- Mesma limitação de ambiente da FASE 3: sem browser disponível aqui pra validação visual.
- `Sim` foi duplicado localmente neste arquivo (não existia componente compartilhado entre as duas telas) — ver função `Sim` perto de `CrawlerStatusBadge`.

---

## FASE 4b — Escopo ampliado: `buscar_processos` (CSV da tela agrupada) [Completada ✅]

**Descoberta durante a FASE 4:** o CSV de `/admin/processos` não usa `buscar_processos_agrupado` (a RPC do grid), e sim uma RPC totalmente diferente — `buscar_processos` (`ProcessoListRow`), que nunca teve `last_crawled_at` nem `crawler_status`. `architecture.md` não previu essa 4ª função. Usuário decidiu ampliar o escopo em vez de deixar essa CSV sem as colunas novas.

### SQL (Seção 3 do mesmo arquivo) [Completada ✅]
- Havia duas versões não commitadas de `buscar_processos` no stash local com data ambígua (uma otimizava `p_q` via semi-join, outra restringia campos de busca). Confirmei a versão **real de produção** pedindo ao usuário rodar `select pg_get_functiondef('public.buscar_processos'::regproc)` antes de escrever a mudança — era a versão semi-join; a versão "outras_telas" (restringe CPF/CNJ solto) **nunca foi aplicada**, apesar de existir como arquivo solto no repo.
- `DROP FUNCTION IF EXISTS` + `CREATE` (RETURNS TABLE muda). Só adiciona a coluna de saída `last_crawled_at` — **não** adiciona `p_crawler_data_de/ate/p_crawleado` como filtro, porque o wrapper `buscarProcessos()` do frontend já não repassa vários outros filtros da tela (enteDevedor, anoOc, faseDesdeDe/Ate, descobertoDe/Ate) — isso é uma limitação pré-existente do CSV dessa tela, documentada no próprio arquivo SQL, não corrigida aqui (fora de escopo).
- Aplicado em produção pelo usuário, confirmado sucesso.

### Frontend [Completada ✅]
- `ProcessoListRow`: `+ last_crawled_at`.
- `exportCsv` de `admin.processos.tsx`: as 2 colunas foram adicionadas de volta (tinham sido revertidas antes desta descoberta).
- `tsc --noEmit` limpo.

### Comentários:
- Isso é um exemplo de por que vale checar o que uma função de export realmente consome antes de assumir que ela reflete os mesmos filtros/dados da tela — `architecture.md` deveria ter mapeado as 4 RPCs (`buscar_processos_incidente`, `contar_processos_incidente`, `buscar_processos_agrupado`, `buscar_processos`), não 3.

---

## FASE 5 — Fechamento [Em Progresso ⏰]

### Revisão cruzada dos critérios de aceite da issue [Não Iniciada ⏳]
Conferir um a um os 5 critérios de aceite da FOR-118 (grid, filtro, URL, CSV, performance) nas duas telas.

### Reconciliar com a branch `jjuniorfilho/precatorio-sp` (frontend) [Não Iniciada ⏳]
A branch conectada ao Lovable (`jjuniorfilho/precatorio-sp`, `origin/HEAD` do repo frontend) está 8 commits à frente da cadeia local de onde `for-118` nasceu (`for-115-definir-senha`). Precisa reconciliar (merge/rebase) antes do PR, sem perder esses 8 commits.

### Commitar o SQL no cortex-v1 [Não Iniciada ⏳]
`sql/2026-07-31_for118_data_ultimo_crawl.sql` foi aplicado em produção mas ainda não commitado no git.

### Atualizar Linear [Não Iniciada ⏳]
Mover FOR-118 pra "In Review" ao abrir o PR (padrão do workflow Cortex).

### PRs [Não Iniciada ⏳]
Dois PRs (um por repo) — `cortex-v1` primeiro (SQL já aplicado em produção, PR é só o registro/histórico), depois `frontend` (branch base `jjuniorfilho/precatorio-sp`, após reconciliação).

### Comentários:
- (preencher durante a execução)
