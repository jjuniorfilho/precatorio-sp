# Context: FOR-173 — Banco + worker do lead avulso (progresso incremental da consulta de valor pago)

> Sub-issue 1 de 2 do FOR-172 (épico "Lead avulso por número DEPRE"). A parte 2 (FOR-174, frontend) é bloqueada por esta.

## ⚠️ Regras Críticas do Projeto (resumo de `docs/technical-context/briefing/critical-rules.md`)
- Tabelas `leads`, `tokens`, `funnel_events` são privadas (admin only, RLS). `precatorios` é pública.
- Valores monetários sempre em centavos (integer). Nunca float.
- Busca tolerante a formato (normalizar antes de buscar).
- Lead só é completo após validar e-mail E WhatsApp (regra 4) → **FOR-172 abre exceção explícita** para `origem='avulso'` (sempre fora do funil público).
- NUNCA expor CPF completo (regra 1) → **FOR-172 abre segunda exceção**: só o admin autenticado, só via server function (FOR-174). Esta issue não move CPF nenhum.
- Convenção SQL do repo: `sql/AAAA-MM-DD_forNNN_N_descricao.sql`, re-executável, aplicado à mão no SQL Editor; RPC `SECURITY DEFINER` com `search_path` fixo; RLS ligado e sem GRANT de tabela para anon/authenticated (a /admin é anônima).

## Motivação
O operador do admin vai cadastrar um lead só com o número DEPRE (`.0500`) e ver o valor pago, com barra de progresso. A consulta ao portal TJSP leva 40s–2min e falha por captcha em parte das vezes. Hoje o worker só grava os passos no **fim** da consulta (`registrar_consulta_pagamento`, FOR-171), então o front não tem como mostrar a etapa real durante a execução. Além disso, o modelo de `leads` assume que todo lead vem do site (nome/e-mail/telefone/relação obrigatórios) e as views do grid não distinguem origem.

## Meta (resultado esperado desta issue)
1. `leads` passa a aceitar o lead avulso: `origem='avulso'` (a coluna `origem` **já existe** e é livre), `criado_por` e `documento` (CPF/CNPJ pesquisado) novos, `email` e `relacao` opcionais — sem quebrar o fluxo do site nem os triggers/constraints.
2. A view `leads_processos` passa a expor `origem` (o grid do FOR-174 precisa do selo/filtro); `leads_com_progresso` já expõe. Sem DROP VIEW.
3. Tabela `pagamentos_consultas_progresso` + RPC de escrita (worker) + RPC de leitura (front, via server function).
4. Worker grava o progresso de forma incremental (na_fila → em_andamento → concluida/falha; etapa; tentativa N/4) sem alterar o contrato da resposta nem o log do FOR-171.
5. Master docs atualizados com as duas exceções e o novo modelo de `leads`.

## Estratégia (direcional)
Migration em SQLs pequenos (diag feito → `leads` → `leads_processos` → tabela → RPCs) + um módulo novo no worker (`pagamentos-progresso.ts`) plugado via observador do `PassosCollector` e via `DepsPersistencia`. Tudo best-effort: falha ao gravar progresso nunca derruba a consulta.

## Repos / base
- `cortex-v1` (worker-crawler + `sql/` + docs): este PR. Base `origin/main` (`c168f31`, já contém o FOR-171). A branch local `jjuniorfilho/oab-cpopg-credores-conjuntos` NÃO tem o código do FOR-171 — não usar.
- `frontend` (`supabase/migrations/`): espelho da migration. Ver decisão do Gate 1 (architecture.md, seção Clarificações).

## Validação
- Unit tests (`npm test` no worker, `tsx --test`): observador do coletor, reporter de progresso (ordem, best-effort, falha do upsert), `consultarEPersistirPagamentos` com deps fake (contrato inalterado), mapeamento estado/etapa.
- SQL: testes de migration no estilo do frontend (`leads-etapas-migration.for170.test.ts`: valida o texto do SQL) + checklist de aplicação manual no SQL Editor.
- **NÃO consultar o portal TJSP em nenhum teste** (site de terceiro, captcha; ver memória "segurança de terceiros"). Qualquer teste real exige autorização explícita do humano.

## Dependências / limitações
- DDL real de `leads` (diag rodado em 2026-09-28, ver architecture.md seção 0): só `email` e `relacao` eram NOT NULL; `origem` e `cnj` já existem; sem UNIQUE; triggers só `leads_updated_at` e `trg_leads_enfileira_crawler`. O `backend-conventions.md` está desatualizado nesse ponto (atualizar nesta issue).
- Confirmar que o `SUPABASE_URL` do worker na VPS é o mesmo projeto do frontend (nota do FOR-171; memória de 26/09 diz que sim).
- Worker tem fila de concorrência 1 (1 vCPU): consultas do operador competem com busca pública e crawler.
- Só o humano aplica SQL (SQL Editor) e reinicia o pm2 na VPS.

## Fora de escopo
Qualquer código do frontend (FOR-174), autenticar a edge function `disparar-valor-pago`, busca por CNJ.
