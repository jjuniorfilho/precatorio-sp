# FOR-173 — Banco + worker do lead avulso (progresso incremental da consulta de valor pago)

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

- **Repo/worktree:** `cortex-v1`, `.claude/worktrees/for-173-banco-worker-lead-avulso`, branch `jjuniorfilho/for-173-banco-worker-lead-avulso`, base `origin/main` (`c168f31`, com o código do FOR-171).
- **Contexto e decisões:** `context.md` e `architecture.md` desta pasta (seções 0 e 13 têm os achados do diagnóstico e o escopo ampliado).
- **Issues:** FOR-173 (esta) → bloqueia FOR-174 (frontend). Pai: FOR-172. Bug relacionado: FOR-175.
- **Regras de trabalho:** commit por fase (`feat|docs|test(FOR-173): ...` + linha `Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>`); worker: `cd worker-crawler && npm test` e `npm run typecheck`; **nunca consultar o portal TJSP** em teste (site de terceiro); só o humano aplica SQL no SQL Editor e reinicia o pm2 na VPS.

## Mapa de dependências (o que roda em paralelo)

```
FASE 0 (humano) ──────────────────────────────────────────────┐ (paralela a tudo; bloqueia só a FASE 7)
FASE 1 (SQL leads + view) ─┐
FASE 2 (SQL progresso)    ─┼─► FASE 6 (espelho no frontend, PR separado) ─┐
FASE 3 (worker: núcleo) ───┴─► FASE 4 (worker: integração) ───────────────┼─► FASE 7 (verificação + rollout)
FASE 5 (docs) ── paralela às fases 1-4 (README do worker só depois da 4) ─┘
```

- **Paralelas entre si:** 1, 2, 3 e 5 (as fases 3 depende só do **contrato** das RPCs, fixado abaixo, não do SQL aplicado).
- **Sequenciais:** 3 → 4; (1 e 2) → 6; tudo → 7.
- **Contrato das RPCs (fixado aqui para desacoplar 2 e 3):**
  - `registrar_progresso_consulta_pagamento(p_processo_depre text, p_estado text, p_etapa text, p_tentativa integer, p_max_tentativas integer, p_detalhe text, p_resultado text, p_etapa_falha text, p_origem text, p_nova boolean DEFAULT false) RETURNS void` — `p_nova=true` faz o upsert **renovar `iniciada_em`** (nova consulta); os demais calls só atualizam.
  - `obter_progresso_consulta_pagamento(p_processo_depre text) RETURNS jsonb` — `null` se não há linha; senão `{estado, etapa, tentativa, max_tentativas, detalhe, resultado, etapa_falha, origem, iniciada_em, atualizado_em}`.
  - Etapas válidas: `na_fila, iniciando, abrir_portal, obter_link, abrir_pesquisa, busca, resultado_carregou, ler_resultado, extrair_pagamentos, persistir, desconhecida` (a RPC troca qualquer outra por `desconhecida`).
  - **Semântica de `etapa`:** a etapa **em andamento** (os passos do coletor são registrados *depois* de concluídos, então o reporter mapeia "concluí X" → "agora está em PROXIMA[X]"; `tentativa(n)` marca `busca` em andamento com a tentativa N).

## FASE 0 — Pré-requisitos e desbloqueios [Em Progresso ⏰]  (humano; paralela; só bloqueia a Fase 7)

### 0.1 Diagnóstico do DDL de `leads` [Completada ✅]
Rodado em 2026-09-28; resultado incorporado em `architecture.md` seção 0. Confirmado também que `capturar-lead-publico` nunca gravou lead (FOR-175 aberta).

### 0.2 Confirmar o banco da VPS [Não Iniciada ⏳]
Humano: `grep SUPABASE_URL /opt/precatorio-worker/.env | cut -c1-40` deve começar com `nxkvfc…` (o log de consultas do FOR-171 já sugere que sim). Dependência antes de aplicar o SQL da Fase 7.

### 0.3 Worktree do frontend para o espelho [Não Iniciada ⏳]
Antes da Fase 6: `git fetch` no repo `frontend` e criar worktree a partir de `jjuniorfilho/precatorio-sp` (o Lovable altera essa branch em paralelo). `npm install`, não `npm ci`.

## FASE 1 — SQL: `leads` avulso + view [Não Iniciada ⏳]  (~1,5h; paralela às fases 2, 3, 5)

### 1.1 `sql/2026-09-28_for173_1_leads_avulso.sql` [Não Iniciada ⏳]
Re-executável, sem `DO $$` (DDL conhecido): `ADD COLUMN IF NOT EXISTS criado_por uuid` e `documento text`; `ALTER COLUMN email DROP NOT NULL`, `ALTER COLUMN relacao DROP NOT NULL`; `COMMENT` em `origem` (valores) / `criado_por` / `documento`; `CHECK` opcional de `documento` (`NULL` ou 11/14 dígitos) via `DO`/`IF NOT EXISTS` em `pg_constraint`; `CREATE UNIQUE INDEX IF NOT EXISTS uq_leads_avulso_processo_depre ON leads (processo_depre) WHERE origem = 'avulso'`; `NOTIFY pgrst, 'reload schema'`. Cabeçalho com ordem de aplicação, pré-requisito (mesmo projeto Supabase) e o aviso: **`DROP NOT NULL` em `relacao` destrava o `capturar-lead-publico` (FOR-175)**.

### 1.2 `sql/2026-09-28_for173_2_view_leads_processos_origem.sql` [Não Iniciada ⏳]
`CREATE OR REPLACE VIEW public.leads_processos WITH (security_invoker = true)` com a definição **viva** colada do diagnóstico (`lp.id … inc.cessao_credito`) + `lp.origem` como **última** coluna. Reafirma `REVOKE ALL … FROM PUBLIC, anon, authenticated` e `GRANT ALL … TO service_role`. Sem `DROP VIEW`. `leads_com_progresso` não é tocada.

### 1.3 Teste de texto do SQL [Não Iniciada ⏳]
`worker-crawler/src/leads-avulso-sql.for173.test.ts` (node:test, `readFileSync` de `../../sql/...`): 1.1 tem `IF NOT EXISTS`, os dois `DROP NOT NULL`, índice parcial e **não** tem `DROP`/`CREATE TABLE`; 1.2 é `CREATE OR REPLACE` (sem `DROP VIEW`), `lp.origem` vem depois de `inc.cessao_credito`/última coluna do SELECT, mantém `security_invoker` e o REVOKE/GRANT.

### Comentários:
- Não criar `origem` nem CHECK nela: a coluna já existe e é livre (achado 1 do diag).

## FASE 2 — SQL: tabela e RPCs de progresso [Não Iniciada ⏳]  (~1,5h; paralela às fases 1, 3, 5)

### 2.1 `sql/2026-09-28_for173_3_tabela_progresso.sql` [Não Iniciada ⏳]
`pagamentos_consultas_progresso` como em `architecture.md` 3.1 (PK `processo_depre`, `estado` CHECK, `resultado`/`origem` CHECK, `tentativa`/`max_tentativas`, `detalhe`, `etapa_falha`, `iniciada_em`/`atualizado_em`), `ENABLE ROW LEVEL SECURITY`, `REVOKE ALL … FROM anon, authenticated`, `NOTIFY pgrst`. Re-executável.

### 2.2 `sql/2026-09-28_for173_4_rpcs_progresso.sql` [Não Iniciada ⏳]
- `registrar_progresso_consulta_pagamento` (contrato acima): `plpgsql SECURITY DEFINER SET search_path = public`; valida `processo_depre ~ '\.8\.26\.0500$'`; `estado` inválido → exceção; etapa fora da lista → `desconhecida`; `left(p_detalhe, 200)`, `left(p_etapa_falha, 40)`, `tentativa` limitada 0–100; `INSERT … ON CONFLICT (processo_depre) DO UPDATE` (com `p_nova` renovando `iniciada_em`); **limpeza preguiçosa**: `DELETE` de linhas `concluida|falha` com `atualizado_em < now() - interval '7 days'`. `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated, service_role`.
- `obter_progresso_consulta_pagamento`: `STABLE SECURITY DEFINER`; devolve o `jsonb` acima ou `null`. `REVOKE ALL … FROM PUBLIC, anon, authenticated; GRANT EXECUTE … TO service_role`.

### 2.3 Teste de texto do SQL [Não Iniciada ⏳]
`worker-crawler/src/progresso-sql.for173.test.ts`: SECURITY DEFINER + `search_path` fixo nas duas RPCs; GRANTs exatos (leitura **só** `service_role`); tabela com RLS e sem GRANT a anon/authenticated; assinatura das RPCs bate com o contrato deste plano.

## FASE 3 — Worker: núcleo do progresso [Não Iniciada ⏳]  (~2h; paralela às fases 1, 2, 5)

### 3.1 `PassosCollector`: observador, `iniciar()`, `tentativa(n)` [Não Iniciada ⏳]
`worker-crawler/src/pagamentos-passos.ts`: `observar(cb)` (vários observadores, exceção de um observador **nunca** propaga); `passo()` notifica **depois** de acrescentar; `iniciar()` notifica "vez chegou" (não vira passo); `tentativa(n)` atribui `tentativas = n` e notifica **sem** acrescentar passo (o log do FOR-171 fica idêntico). Testes em `pagamentos-tjsp.test.ts` ou arquivo novo `pagamentos-passos.test.ts`.

### 3.2 `pagamentos-progresso.ts` (reporter) [Não Iniciada ⏳]
`worker-crawler/src/pagamentos-progresso.ts`: `criarReporter({ processoDepre, origem, maxTentativas, registrar })` com `naFila()`, `ligar(passos)` (observa o coletor), `concluir(resultado)`, `falhar(etapaFalha)`, `drenar(timeoutMs = 3000)`.
- **Cadeia serial de promises** (`ultima = ultima.then(upsert).catch(log)`): upserts saem em ordem, nunca em paralelo, nunca lançam.
- `PROXIMA` mapeia "concluí X" → etapa em andamento; `tentativa(n)` → `busca` em andamento com `tentativa=n`; `iniciar()` → `iniciando`; `detalhe` só de texto já sanitizado (nunca mensagem crua de erro do banco).
- `drenar` espera a cadeia esvaziar (teto 3s) para o estado final não ser sobrescrito por um passo atrasado.
- Testes (`pagamentos-progresso.test.ts`, `registrar` fake): ordem dos estados `na_fila → iniciando → … → concluida`; `falhar` grava `etapa_falha`; upsert que lança **não** derruba nem atrasa o chamador; `drenar` respeita o teto; `p_nova=true` só no `naFila()`.

### 3.3 `supabase.ts: registrarProgressoPagamento` [Não Iniciada ⏳]
Wrapper de `supabase.rpc("registrar_progresso_consulta_pagamento", { p_… })` no estilo de `registrarConsultaPagamento` (lança `Error` com a mensagem; o reporter é quem engole). Tipo `RegistroProgressoPagamento`.

### Comentários:
- Decisão do plano: o reporter só é ligado quando `origem === 'manual'` (Fase 4.1). O crawler e a busca pública não precisam de progresso e gerariam escritas inúteis na tabela (o `CHECK` de `origem` continua aceitando as três, para não travar uso futuro).

## FASE 4 — Worker: integração [Não Iniciada ⏳]  (~2h; depende da Fase 3)

### 4.1 Ligar o reporter em `pagamentos-tjsp.ts` [Não Iniciada ⏳]
- `DepsPersistencia` ganha `progresso` (fábrica injetável do reporter; padrão = real com `registrarProgressoPagamento`).
- Em `consultarEPersistirPagamentos`: se `origem === 'manual'`, cria o reporter e chama `naFila()` **antes** de `deps.consultar`; `ligar(passos)`; no fim, `concluir(resultado)` ou `falhar(etapaFalha)` **antes** do `deps.registrar` do log; `await reporter.drenar()`; falha de progresso nunca impede o log nem altera o retorno/erro.
- Em `consultarPagamentos`: dentro do callback de `comFilaPlaywright`, `passos.iniciar()` antes de `consultarInterno` (é o momento em que a vez na fila chegou).
- Em `consultarInterno`: `passos.tentativa(tentativa)` no início de cada iteração do loop de captcha, antes de `tentarBusca`.
- **Não mudar** a assinatura de `consultarPagamentos`, o contrato de resposta do `http-server.ts` nem o conteúdo de `passos` gravado no log FOR-171.

### 4.2 Testes de integração (deps fake, sem portal) [Não Iniciada ⏳]
Em `pagamentos-tjsp.test.ts`: (a) contrato inalterado — `resultado`, `passos` e chamada de `registrar` com a mesma forma de antes; (b) sequência de progresso `na_fila → iniciando → busca(t=1) → busca(t=2) → … → concluida`; (c) caminho de falha grava `falha` + `etapa_falha`; (d) `registrarProgresso` que lança **não** derruba a consulta; (e) `origem !== 'manual'` não chama progresso.

### 4.3 Gates programáticos do worker [Não Iniciada ⏳]
`cd worker-crawler && npm install && npm run typecheck && npm test` verdes (o `npm test` roda com `SUPABASE_URL` fake; nenhum teste toca a rede).

### Comentários:
- Não criar linha de progresso em `http-server.ts`: `consultarEPersistirPagamentos` já é o único caminho do endpoint, e é ali que `na_fila` nasce, **antes** da fila (a issue original falava em `handleValorPago`; o efeito é o mesmo com um só ponto de instrumentação).

## FASE 5 — Master docs e README [Não Iniciada ⏳]  (~1h; 5.1 paralela às fases 1-4; 5.2 depois da Fase 4)

### 5.1 `critical-rules.md` e `backend-conventions.md` [Não Iniciada ⏳]
`docs/technical-context/briefing/`: registrar as duas exceções aprovadas (lead avulso sem 2 canais validados; admin autenticado vê CPF completo no painel do avulso); modelo atual de `leads` (valores de `origem`: `busca_em_formacao|monitorar|antecipacao|avulso`; `email` e `relacao` opcionais; `criado_por`, `documento`; `lgpd_consent=false` no avulso e **nenhuma comunicação automática parte dele**); tabelas novas (`pagamentos_consultas_log` do FOR-171 e `pagamentos_consultas_progresso`); corrigir o schema de `leads` desatualizado do `backend-conventions.md`.

### 5.2 `worker-crawler/README.md` [Não Iniciada ⏳]
Seção "Progresso da consulta de valor pago (FOR-173)": estados, RPCs, que só `origem='manual'` grava, limpeza de 7 dias, ordem de deploy (SQL → worker) e como inspecionar (`select * from pagamentos_consultas_progresso order by atualizado_em desc`).

## FASE 6 — Espelho da migration no repo `frontend` (PR separado) [Não Iniciada ⏳]  (~1h; depois das fases 1 e 2; usa a worktree da 0.3)

### 6.1 Copiar os 4 SQLs para `frontend/supabase/migrations/` [Não Iniciada ⏳]
Mesmo conteúdo de `sql/2026-09-28_for173_{1..4}_*.sql`, com timestamps `2026092810NNNN_for173_*.sql` (depois de `20260926100000_for171_...`). Sem o SQL de diagnóstico. Cabeçalho "espelho de cortex-v1/sql/…; aplicar manualmente no SQL Editor".

### 6.2 Teste de migration e PR [Não Iniciada ⏳]
Teste no padrão `leads-etapas-migration.for170.test.ts` (leitura do texto) para os SQLs espelhados; PR pequeno contra `jjuniorfilho/precatorio-sp` (após novo `git fetch`; se o Lovable mexeu na branch, rebasear). **Não** publicar nada no Lovable antes de o humano aplicar o SQL.

## FASE 7 — Verificação, revisão e rollout [Não Iniciada ⏳]  (~1,5h; depois de todas)

### 7.1 Garantias do fleet [Não Iniciada ⏳]
`fleet-gate.sh` (lint/typecheck/test), `test-engineer` + `code-reviewer`, `adr-compliance-checker` STRICT; depois `/engineer:pre-pr` (agentes branch-*) e `/engineer:pr`. Cobrir explicitamente: PII (nada de CPF/documento em log), GRANTs das RPCs, `SECURITY DEFINER` com `search_path`, e a nota sobre o efeito no FOR-175.

### 7.2 Aplicação e rollout (humano) [Não Iniciada ⏳]
Ordem: (1) `_1_leads_avulso.sql` → (2) `_2_view_leads_processos_origem.sql` → (3) `_3_tabela_progresso.sql` → (4) `_4_rpcs_progresso.sql`; conferir com `information_schema` que `email`/`relacao` viraram nullable e que `leads_processos` expõe `origem`; (5) deploy do worker na VPS (`git pull`, `npm install`, `pm2 restart` do processo do worker; confirmar o nome, hoje `precatorio-crawler`); (6) só então liberar o FOR-174.

### 7.3 Smoke test [Não Iniciada ⏳]
Humano dispara **uma** consulta manual no admin (`/admin/processos/:id`, botão de valor pago) e acompanha `select * from pagamentos_consultas_progresso where processo_depre = '0145616-63.2020.8.26.0500'`: deve passar por `na_fila → iniciando → busca (tentativa N) → … → concluida (nao_consta)`. Confirmar que o log do FOR-171 continua igual e que uma busca pública **não** cria linha de progresso.

## Riscos e pontos de atenção
- **FOR-175:** o `DROP NOT NULL` em `relacao` passa a gravar leads do `capturar-lead-publico` (hoje perdidos). Comportamento novo em produção; constar no PR e conferir o grid depois.
- **Fila do worker:** consulta do operador espera busca pública/crawler na frente; `na_fila` existe para isso.
- **Linha órfã** (worker morto): fica `em_andamento`; o FOR-174 trata `atualizado_em` parado > 150s como timeout. Sem job de limpeza nesta issue.
- **Compatibilidade:** worker novo com front antigo só grava progresso a mais; front novo sem worker novo lê `null` e mostra progresso genérico (FOR-174 deve tolerar).

## Como retomar esta sessão
1. `cd .claude/worktrees/for-173-banco-worker-lead-avulso && git log --oneline -10 && git status`.
2. Ler este `plan.md` (status por fase) e `architecture.md`.
3. Próxima fase = a primeira com `[Em Progresso ⏰]` ou `[Não Iniciada ⏳]` respeitando o mapa de dependências; atualizar as marcações ao concluir cada tarefa e commitar.
