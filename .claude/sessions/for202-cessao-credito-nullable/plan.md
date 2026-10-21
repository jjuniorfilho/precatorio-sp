# FOR-202 — cessao_credito nullable

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

## FASE 1 — Schema + fix em classify_processo/classify_incidentes [Não Iniciada ⏳]

Escrever e validar localmente a migration que torna `incidentes.cessao_credito`
nullable e corrige o `COALESCE` que apagava o `NULL` genuíno.

### Escrever `sql/2026-10-21_for202_cessao_credito_nullable.sql` [Não Iniciada ⏳]

- `ALTER TABLE incidentes ALTER COLUMN cessao_credito DROP NOT NULL, ALTER COLUMN
  cessao_credito DROP DEFAULT;` — precedido de `SET lock_timeout = '3s';
  SET statement_timeout = '5s';` (recomendação do revisor especialista, evita
  enfileirar atrás de um `classify_processo` em andamento e bloquear o crawler).
- `CREATE OR REPLACE FUNCTION classify_processo(...)` e `classify_incidentes(...)`:
  mesma assinatura de produção (capturada via `pg_get_functiondef` nesta sessão, ver
  context.md), só o bloco de `cessao_credito` muda:
  - Adicionar `bool_or(ta.incidente_id IS NOT NULL) AS tem_andamento` ao CTE `match`.
  - `cessao_credito = CASE WHEN m.tem_andamento THEN COALESCE(m.f_cessao, false)
    ELSE NULL END` no UPDATE final (era `COALESCE(m.f_cessao, false)` sem condição).
  - Os outros 7 flags (`calculo_homologado` etc.) e o resto da lógica (`fase`,
    `macrofase`, `elegivel`, `ano_oc`, `next_crawl_at`) ficam **byte-a-byte iguais**
    ao que está em produção hoje — zero mudança além do `cessao_credito`.

### Escrever `sql/sandbox/for202_validate_local.sh` [Não Iniciada ⏳]

Molde: `sql/sandbox/for201_validate_local.sh`. Cenários mínimos:
1. Incidente sem nenhum andamento em nenhuma fonte → `cessao_credito IS NULL`.
2. Incidente com andamento (qualquer fonte) que bate a regra de cessão →
   `cessao_credito = true`.
3. Incidente com andamento (qualquer fonte) que NÃO bate nenhuma regra →
   `cessao_credito = false` (não `NULL` — já foi verificado).
4. Mesmos 3 cenários via `classify_incidentes` (caminho batch), não só
   `classify_processo`.
5. Regressão: um incidente com `oficio_expedido` batendo via andamento próprio
   continua funcionando igual (os outros flags não mudaram).

### Rodar a validação local [Não Iniciada ⏳]

`sql/sandbox/for202_validate_local.sh` — todas as asserções precisam passar antes de
avançar pra Fase 2.

### Comentários:
-

## FASE 2 — Backfill de correção [Não Iniciada ⏳]

Corrigir os ~200.800 incidentes que hoje são `false` mas nunca foram verificados.

### Escrever `sql/2026-10-21_for202_backfill_cessao_credito.sql` [Não Iniciada ⏳]

- Cursor por `id` (não `OFFSET` — recomendação do especialista, evita pular/duplicar
  linhas sob escrita concorrente do crawler).
- Lotes de 2.000-5.000 linhas por iteração (`DO` block em loop, ou script chamado
  repetidamente — decidir no momento, documentar escolha no cabeçalho do arquivo).
- Cada `UPDATE` do lote recalcula "sem andamento em nenhuma fonte" **ao vivo**, dentro
  do próprio statement — nunca contra uma lista pré-materializada (evita sobrescrever
  com `NULL` um incidente que o crawler classificou de verdade entre a medição e a
  escrita).
- Guard: só atualiza linhas onde `cessao_credito = false` (nunca toca em `true`, nem
  reprocessa linhas já `NULL`).
- Pequena pausa entre lotes (`pg_sleep` ou nova invocação) pra não competir I/O com o
  crawler de produção — mesmo cuidado que a medição por amostra desta sessão já exigiu.

### Medir antes de rodar em produção [Não Iniciada ⏳]

Reconfirmar o tamanho real (a estimativa de ~200.800 foi por amostra — medir o valor
exato é inviável em 1 query, ver nota em context.md; considerar medir por fatias/cursor
em vez de 1 contagem global).

### Comentários:
-

## FASE 3 — RPCs com filtro em 3 estados [Não Iniciada ⏳]

### Escrever `sql/2026-10-21_for202_rpcs_cessao_credito_enum.sql` [Não Iniciada ⏳]

Base: captura ao vivo de produção (via `pg_get_functiondef`, não o arquivo mais
recente do repo — já documentado drift entre os dois, ver context.md).

- `DROP FUNCTION` explícito nas 3 (mudança de tipo de parâmetro = assinatura
  diferente — mesma cautela do FOR-160/FOR-189).
- `_where_processo_incidente`: trocar `p_cessao_credito boolean` por
  `p_cessao_credito text`, adicionar bloco (hoje ausente — bug achado nesta sessão):
  ```sql
  if p_cessao_credito = 'sim' then
    v_where := v_where || ' and i.cessao_credito = true';
  elsif p_cessao_credito = 'nao' then
    v_where := v_where || ' and i.cessao_credito = false';
  elsif p_cessao_credito = 'nao_verificado' then
    v_where := v_where || ' and i.cessao_credito is null';
  end if;
  ```
  Mais simples que o padrão do `acordo_homologado` (que precisa de `EXISTS` contra
  `djen_depre` via `numero_depre`) — `cessao_credito` é coluna própria de `incidentes`.
- `buscar_processos_incidente`/`contar_processos_incidente`: só muda o tipo do
  parâmetro na assinatura e no repasse pra `_where_processo_incidente`. O `SELECT`
  de `buscar_processos_incidente` já devolve `pg.cessao_credito` como está — não
  precisa mudar (boolean nullable já é compatível com `RETURNS TABLE(...,
  cessao_credito boolean, ...)`).
- `GRANT EXECUTE` pras 3, pra `anon, authenticated` (mesmo padrão do FOR-160).

### Validar localmente [Não Iniciada ⏳]

Adicionar cenários de `p_cessao_credito='sim'/'nao'/'nao_verificado'` no mesmo
`for202_validate_local.sh` da Fase 1 — confirmar que o filtro de fato restringe
(cobre o bug do no-op achado nesta sessão).

### Comentários:
-

## FASE 4 — Aplicar em produção (handoff humano) [Não Iniciada ⏳]

O agente não tem permissão pra aplicar DDL/funções em produção diretamente (achado
no FOR-201, harness bloqueia como "Production Deploy") — esta fase é SQL Editor,
executado pelo humano, na ordem:

1. `sql/2026-10-21_for202_cessao_credito_nullable.sql` (schema + fix na função).
2. Confirmar com 1 `classify_processo(id)` manual que não dá erro.
3. `sql/2026-10-21_for202_backfill_cessao_credito.sql` (rodar, acompanhar progresso).
4. `sql/2026-10-21_for202_rpcs_cessao_credito_enum.sql` (RPCs).

### Comentários:
-

## FASE 5 — Frontend [Não Iniciada ⏳]

### `frontend/src/lib/api/processos.ts` [Não Iniciada ⏳]

- `cessaoCredito?: boolean | null` → `cessaoCredito?: "sim" | "nao" | "nao_verificado"
  | null`.
- `cessao_credito: boolean` (tipo da linha de resultado) → `boolean | null`.
- `p_cessao_credito: f.cessaoCredito ?? null` — sem mudança na expressão, só no tipo.

### `frontend/src/routes/admin.processo-incidente.tsx` [Não Iniciada ⏳]

- `CESSAO_CREDITO_OPTIONS`: adicionar `["nao_verificado", "Não verificado"]` (igual
  `ACORDO_HOMOLOGADO_OPTIONS`).
- `validateSearch`: `oneOf(search.cessaoCredito, ["sim", "nao", "nao_verificado"] as
  const)`.
- Estado local + conversão pro filtro: hoje `cessaoCredito === "all" ? null :
  cessaoCredito === "sim"` (vira boolean) — trocar por `cessaoCredito === "all" ? null
  : (cessaoCredito as "sim"|"nao"|"nao_verificado")` (mesmo padrão já usado pra
  `acordoHomologado` logo abaixo).
- Novo componente `CessaoCreditoBadge` (mirror exato de `AcordoHomologadoBadge`),
  substituindo o uso de `<Sim v={r.cessao_credito} />` na coluna da grid.
- CSV export: `r.cessao_credito ? "Sim" : "Não"` →
  `r.cessao_credito == null ? "Não verificado" : r.cessao_credito ? "Sim" : "Não"`
  (mesmo padrão da linha de `acordo_homologado` logo abaixo, já existente).

### Testes [Não Iniciada ⏳]

- `admin.processo-incidente.for160.test.ts`, `admin.processo-incidente.oneof.for160.test.ts`,
  `processos.for160.test.ts`: atualizar asserções que assumem `cessao_credito`
  2-estado.
- Rodar suíte completa do frontend antes de abrir PR.

### Comentários:
-

## FASE 6 — Fechamento [Não Iniciada ⏳]

### Confirmar em produção [Não Iniciada ⏳]

Query de smoke test: contagem de `cessao_credito is null` vs `true` vs `false` —
confere com o esperado (backfill completo, nenhum `false` sem andamento).

### Issue de follow-up [Não Iniciada ⏳]

Criar no Linear: mesma ambiguidade nos outros 6 flags + propagação pra
`fase`/`macrofase`/`elegivel` + duplicação de código entre `classify_processo`/
`classify_incidentes` (achados do revisor especialista, registrados em
architecture.md). Não implementar agora — só registrar.

### PR + merge [Não Iniciada ⏳]

`/engineer:pre-pr` → `/engineer:pr` → Gate 3 (merge manual).

### Comentários:
-
