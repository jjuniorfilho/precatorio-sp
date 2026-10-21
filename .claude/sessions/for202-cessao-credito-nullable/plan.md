# FOR-202 — cessao_credito nullable

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

## FASE 1 — Schema + fix em classify_processo/classify_incidentes [Completada ✅]

Escrever e validar localmente a migration que torna `incidentes.cessao_credito`
nullable e corrige o `COALESCE` que apagava o `NULL` genuíno.

### Escrever `sql/2026-10-21_for202_cessao_credito_nullable.sql` [Completada ✅]

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

### Escrever `sql/sandbox/for202_validate_local.sh` [Completada ✅]

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

### Rodar a validação local [Completada ✅]

`sql/sandbox/for202_validate_local.sh` — 14 asserções, todas passaram.

### Comentários:
- Caso sutil validado explicitamente (cenário I3): incidente com andamento real que não
  bate NENHUMA regra de `classificacao_regras` precisa virar `false` (verificado,
  negativo), não `NULL`. A lógica `tem_andamento = bool_or(ta.incidente_id IS NOT NULL)`
  cobre isso corretamente porque conta a PRESENÇA do andamento na origem (`ta`), não se
  ele bateu alguma regra (`r`).
- Caso I4 (andamento só no nível do PROCESSO raiz, não no cumprimento nem no incidente)
  também confirmado: conta como verificado. Reforça que o fix do FOR-201 (3 fontes) e o
  fix do FOR-202 (nullable) são complementares — um sem o outro deixaria falso-negativo
  ou falso "nunca verificado" dependendo da combinação.
- Definição base das funções confirmada idêntica à de produção via `pg_get_functiondef`
  antes de escrever a migration (não confiar no arquivo mais recente do repo — hábito já
  estabelecido desde o achado do drift de `ano_oc`/`calcular_oc` no FOR-201).

## FASE 2 — Backfill de correção [Completada ✅]

Corrigir os ~200.800 incidentes que hoje são `false` mas nunca foram verificados.

### Escrever `sql/2026-10-21_for202_backfill_cessao_credito.sql` [Completada ✅]

Desenho final: função "tick" (`for202_backfill_cessao_credito_tick()`) chamada a cada
minuto via `pg_cron` — mesmo padrão já em produção pro backfill de `numero_depre`
(jobid 17, `backfill_numero_depre_tick`), não um `DO` block em loop único nem um script
chamado manualmente. Motivo: resumível, observável (`coleta_runs` + tabela de estado),
pausável sem derrubar nada, e já é o padrão mental de quem for operar depois.

- Cursor por `id` via tabela de estado `for202_backfill_cessao_credito_estado`.
- Lotes de 3.000 (`LIMIT 3000`).
- `NOT EXISTS` nas 3 fontes dentro do próprio `UPDATE` — recálculo ao vivo, não lista
  pré-materializada.
- Guard `cessao_credito = false` — nunca toca em `true` nem `NULL` já setado.
- `ativo = (tamanho_lote = 3000)` — autodesliga quando o lote vem incompleto (acabou).
- Pacing: o próprio intervalo do cron (1/min) já serve de pausa — sem `pg_sleep`
  adicional necessário.
- Controle manual: `UPDATE for202_backfill_cessao_credito_estado SET ativo = false/true`.

### Medir antes de rodar em produção [Completada ✅ — já feito antes desta sub-sessão de fleet]

Estimativa por amostra (`TABLESAMPLE SYSTEM(5)`) já registrada em context.md: ~200.800
de 871.127. Medir o valor exato continua inviável numa query só (mesmo achado de I/O);
o progresso real vai ser observável incrementalmente via
`for202_backfill_cessao_credito_estado.total_corrigidos` conforme o cron roda — não
precisa de uma contagem global prévia mais precisa que a amostra.

### Comentários:
- Validação local (10 asserções, `sql/sandbox/for202_backfill_validate_local.sh`) usa um
  shim de `cron.schedule` (função stub no schema `cron`) em vez de editar o arquivo real
  — garante que o arquivo aplicado em produção é EXATAMENTE o testado, sem cópia
  mutilada por `sed`.
- Testado explicitamente: nunca toca em `cessao_credito = true` nem em linhas já `NULL`
  (simulando um `classify_processo` concorrente que já classificou antes do tick rodar).
- Segurança de concorrência quanto ao crawler escrevendo em paralelo: por construção, o
  `NOT EXISTS` roda DENTRO do mesmo `UPDATE` (não é um `SELECT` separado seguido de
  `UPDATE` por lista fixa) — o mecanismo de `EvalPlanQual` do Postgres sob READ COMMITTED
  já impede o backfill de sobrescrever uma linha que outra transação concorrente acabou
  de comitar com um valor diferente pro guard (`cessao_credito = false`). Não simulei
  concorrência real (2 processos psql simultâneos) no sandbox — a garantia é por
  construção da query, não por teste empírico de corrida; se algum dia isso virar
  suspeito de bug, vale um teste de concorrência real antes de mexer na lógica.

## FASE 3 — RPCs com filtro em 3 estados [Completada ✅]

### Escrever `sql/2026-10-21_for202_rpcs_cessao_credito_enum.sql` [Completada ✅]

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

### Validar localmente [Completada ✅]

Script próprio (`sql/sandbox/for202_rpcs_validate_local.sh`, não o mesmo do Fase 1 —
precisa de um schema mais amplo: `partes`, `djen_depre`, `precatorios`,
`precatorios_pagamentos`, `crawler_queue`, todas referenciadas nas subqueries de
`buscar_processos_incidente`). 6 asserções, todas passaram.

### Comentários:
- Prova direta do bug achado em produção: a fixture (1 incidente `true`, 1 `false`, 1
  `NULL`) confirma que `p_cessao_credito := 'sim'` filtra corretamente pro 1 `true` —
  com a função ANTIGA (sem o bloco de filtro), isso teria retornado os 3.
- Confirmado também que valor fora do enum (`'lixo'`) é no-op silencioso, mesmo espírito
  defensivo do resto da função (não dá erro, só não filtra) — igual o `acordo_homologado`
  já se comporta.
- `buscar_processos_incidente` ganhou uma coluna (`processo_cnj`) depois do FOR-160
  original (trabalho do FOR-195) — preservada na reescrita, confirmada contra a captura
  ao vivo de produção antes de escrever o arquivo.

## FASE 4 — Aplicar em produção (handoff humano) [Completada ✅]

O agente não tem permissão pra aplicar DDL/funções em produção diretamente (achado
no FOR-201, harness bloqueia como "Production Deploy") — usuário aplicou via Lovable
(SQL Editor), na ordem: schema+fix, backfill, RPCs.

### Comentários:
- Verificado em produção após aplicação: `incidentes.cessao_credito` nullable (`YES`),
  `classify_processo` com `tem_andamento` presente, cron `backfill-cessao-credito`
  criado (jobid 18, ativo).
- Confirmado só 1 overload de `buscar_processos_incidente`/`contar_processos_incidente`
  (sem risco de PGRST203) — `_where_processo_incidente` tem 3 overloads históricos
  (16/18/21 params, de migrations anteriores ao FOR-160), mas não é exposta via
  PostgREST, então não ambiguiza nada pra fora.
- Smoke test do bug corrigido: `contar_processos_incidente('sim')` +
  `('nao')` + `('nao_verificado')` = 718.285 + 15.920 + 2.640 = 736.845, bate exatamente
  com o baseline (`count(*) where flag_sp`) — todo incidente cai em exatamente 1 balde,
  confirma que o filtro deixou de ser no-op.
- Backfill rodando sozinho via cron desde a aplicação: 4 lotes, 2.918 corrigidos nos
  primeiros minutos, `ativo=true` (continua).

## FASE 5 — Frontend [Completada ✅]

### `frontend/src/lib/api/processos.ts` [Completada ✅]

- `cessaoCredito?: boolean | null` → `cessaoCredito?: "sim" | "nao" | "nao_verificado"
  | null`.
- `cessao_credito: boolean` (tipo da linha de resultado) → `boolean | null`.
- `p_cessao_credito: f.cessaoCredito ?? null` — sem mudança na expressão, só no tipo.

### `frontend/src/routes/admin.processo-incidente.tsx` [Completada ✅]

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

### Testes [Completada ✅]

- `admin.processo-incidente.for160.test.ts`, `admin.processo-incidente.oneof.for160.test.ts`,
  `processos.for160.test.ts`: asserções atualizadas pro novo enum, + describe novo pra
  `CessaoCreditoBadge` (mirror de `AcordoHomologadoBadge`).
- Suíte completa: 364/364 passam. Typecheck limpo (`tsc --noEmit`).

### Comentários:
- Branch criada em `origin/jjuniorfilho/precatorio-sp` (base correta do repo frontend,
  não a branch que estava checked out na hora — `content/for-acordo-prazo-atualizado`,
  trabalho de outra pessoa/sessão, não tocado).
- `resultado-fase.tsx`/`admin.leads.tsx`/`novo-lead-avulso-dialog.tsx` não precisaram de
  mudança — já tratavam `cessao_credito` como tri-state desde o FOR-161 (decisão
  deliberada de code review anterior, só "adiantada" porque a coluna nunca mandava
  `null` de verdade até agora).
- Commit + push feitos; branch `feat/for202-cessao-credito-nullable` no remoto de
  `sp-precat-rios-simples` (repo frontend).

## FASE 6 — Fechamento [Em Progresso ⏰]

### Confirmar em produção [Completada ✅ — feito na Fase 4]

Smoke test (soma sim/nao/nao_verificado = baseline) e estado do backfill já conferidos
e documentados na Fase 4. Backfill ainda não terminou (roda sozinho via cron, sem
necessidade de acompanhamento ativo).

### Pre-PR: 2 achados críticos do code-reviewer, corrigidos [Completada ✅]

Rodei os 4 agentes de pre-PR (`branch-master-docs-checker`, `code-reviewer`,
`documentation-writer`, `test-planner-branch`) em paralelo sobre a branch. 2 achados
reais, já em produção, corrigidos nesta sessão antes de abrir o PR:

1. **Exposição de privilégios ativa**: `for202_backfill_cessao_credito_estado` e a
   função tick foram criadas sem REVOKE/RLS — desvio da convenção já estabelecida no
   repo (for171/for174b/for200). `anon`/`authenticated` tinham acesso total.
2. **Condição de corrida real, reproduzida empiricamente pelo revisor**: o `NOT EXISTS`
   do UPDATE original rodava no mesmo statement que o guard `cessao_credito=false` — sob
   conflito de lock (EvalPlanQual), o guard via dado fresco mas o `NOT EXISTS` continuava
   no snapshot velho. Uma linha já verificada como `false` podia virar `NULL` por engano
   se o crawler inserisse um andamento bem na janela do tick.

Fix: `sql/2026-10-21_for202_fix_backfill_revoke_e_corrida.sql` — REVOKE/RLS +
`FOR UPDATE SKIP LOCKED` em 2 statements separados (linha disputada pelo crawler é
pulada, não corrompida). Bug de implementação achado ao validar (`max(uuid)` não existe
no Postgres) corrigido no processo.

Validado com 2 scripts novos: `for202_fix_regressao_validate_local.sh` (12 asserções —
fix não quebra nada do comportamento já validado) e `for202_fix_race_validate_local.sh`
(2 sessões psql concorrentes DE VERDADE, não só lógica sequencial — reproduz o bug no
padrão antigo, confirma o fechamento no padrão novo).

**Ainda precisa aplicar em produção** (handoff humano, mesma restrição de sempre) —
URGENTE pela parte 1 (exposição ativa).

`branch-master-docs-checker`: nada bloqueante (projeto não tem ADR formal pra citar).
`documentation-writer`: formalizou as 3 convenções técnicas usadas (migration
numerada+captura ao vivo, backfill tick+cron, nullable tri-state) em
`docs/technical-context/briefing/backend-conventions.md`.
`test-planner-branch`: achou 2 gaps reais de cobertura nos scripts da Fase 1/2 (fontes
de andamento nunca testadas em combinação, paginação multi-tick nunca exercitada) —
corrigidos, 30→44 asserções nos scripts originais.

### Issue de follow-up [Completada ✅]

FOR-203 criada: mesma ambiguidade nos outros 6 flags + propagação pra
`fase`/`macrofase`/`elegivel` + duplicação de código entre `classify_processo`/
`classify_incidentes`. Não implementado — só registrado pra decisão futura.

### PR + merge [Não Iniciada ⏳]

`/engineer:pre-pr` → `/engineer:pr` → Gate 3 (merge manual).

### Comentários:
-
