# FOR-171 — Valor pago: "não consta" vs falha + log de consultas TJSP

Se você está trabalhando nesta feature, atualize este plan.md conforme progride.
Repos: cortex-v1 (worktree for-171-crawler-pagamentos-log, base origin/main) e frontend (worktree for-171-ui-log-consultas-tjsp, base jjuniorfilho/precatorio-sp).

## FASE 0 — Pré-requisitos e desbloqueios [Não Iniciada ⏳]  (paralela às Fases 1-2)

### 0.1 Validar detecção no portal real [Completada ✅]
Humano rodou a sonda na VPS (solver de produção) e trouxe os HTMLs. Fixtures: worker-crawler/src/__fixtures__/pagamentos/resultado-sem-pagamento.html e resultado-com-pagamento.html. Achados em architecture.md.

(histórico: antes o solver local foi barrado pelo classificador) Humano decide: (a) fornecer HTML salvo da página de resultado de 0145616-63.2020.8.26.0500 (sem pagamento) e 0150268-84.2024.8.26.0500 (com 3 pagamentos) para virarem fixtures; (b) autorizar explicitamente o solver local; ou (c) rodar `consultarPagamentos` (sem persistir) pela VPS. Saída: fixtures em `worker-crawler/src/__fixtures__/pagamentos/` e seletor de visibilidade confirmado.

### 0.2 Confirmar banco da VPS [Não Iniciada ⏳]
Humano compara SUPABASE_URL da VPS com nxkvfcrnocdxysqsuozj. Dependência antes do apply do SQL (Fase 3). Ramo A (mesmo banco) = principal; Ramo B (diferente) = GET /consultas no worker + edge lê dele (Fase 6B).

## FASE 1 — Crawler: classificador tri-estado + coletor de passos [Não Iniciada ⏳]  (cortex-v1, ~2h)

### 1.1 `pagamentos-passos.ts` (coletor) [Não Iniciada ⏳]
`PassosCollector` com `passo(etapa,status,detalhe?)`, `at` ISO, `toJSON()`. Testes unitários.

### 1.2 `classificarResultado` em `pagamentos-tjsp.ts` [Não Iniciada ⏳]
Regra final: encontrado = existe `span[id^=span_PRP_SITUACAO_ANDAMENTO_]`; nao_consta = URL de resultado E `span#TXTNENHUM` VISÍVEL E grade vazia E rodapé "Data da Consulta" presente; senão falha. Duas camadas: (a) função pura `classificarHtml(html,url)` com cheerio (já dep do repo) usando o estado GeneXus `TXTNENHUM_Visible` ("1"/"0") + grade + rodapé; (b) no fluxo ao vivo, confirmação por `locator('#TXTNENHUM').isVisible()` (computed). Sinais divergentes (server-side x computed) => falha. Rodapé NÃO discrimina (aparece nos 2 casos), só prova que a busca terminou. Extrair data do rodapé.

**Testes (node:test, `npm test`, arquivo `pagamentos-tjsp.test.ts`):** classificarHtml sobre os 2 fixtures (sem-pagamento => nao_consta; com-pagamento => encontrado, situacao "Pendente de Pagamento"); falha: HTML sem rodapé; URL fora de pesquisainternetnumanoep.aspx; TXTNENHUM_Visible=1 mas sem rodapé; TXTNENHUM_Visible=0 sem linha na grade (página inesperada); sinais divergentes. Opcional: teste `page.setContent` do fixture p/ isVisible (Chromium já instalado; pular se ausente).

### 1.3 Instrumentar `consultarInterno` [Não Iniciada ⏳]
Passos: abrir menu, link, pesquisa, cada tentativa (captcha ok/rejeitado/timeout), resultado, leitura, PDF, persistência. Em falha, último passo `erro` com etapa; contador de tentativas. `ConsultaPagamento` ganha `resultado`, `tentativas`, `passos`, `dataConsultaPortal`; mantém `encontrado` (compat edge/buscar-precatorio).

## FASE 2 — Crawler: persistência, log e HTTP [Não Iniciada ⏳]  (depende de 1; ~2h)

### 2.1 `consultarEPersistirPagamentos(processoDepre, {origem, maxTentativas})` [Não Iniciada ⏳]
Marca consultado em encontrado e nao_consta; nunca em falha. Log no `finally`, best-effort (erro de log só console.error). Erro relança com etapa.

### 2.2 `supabase.ts: registrarConsultaPagamento` (RPC) [Não Iniciada ⏳]
### 2.3 `http-server.ts` [Não Iniciada ⏳]
Aceita `origem` (manual|busca_publica|crawler, default manual, valida enum); resposta com `resultado`, `consultado_em`; 502 com `{resultado:'falha', etapa, error}`.

## FASE 3 — SQL (cortex-v1/sql + espelho migration frontend) [Não Iniciada ⏳]  (paralela a 1-2; APPLY depende de 0.2)

### 3.1 `sql/2026-09-25_for171_pagamentos_consultas_log.sql` [Não Iniciada ⏳]
Tabela `pagamentos_consultas_log` (RLS sem policy, índice processo_depre+iniciada_em desc, checks de origem/resultado), RPC `registrar_consulta_pagamento` (grant authenticated/service_role, poda 20/processo), RPC `listar_consultas_pagamento` (plpgsql, grant anon/authenticated/service_role). Re-executável.
### 3.2 Espelho em `frontend/supabase/migrations/*for171*.sql` [Não Iniciada ⏳]

## FASE 4 — Frontend: API + estados da consulta manual [Não Iniciada ⏳]  (frontend, ~2h; após 3.1 e contrato da Fase 2)
### 4.1 `processos.ts`: tipos `resultado`, `consultarPagamentoManual` 3 estados, `fetchConsultasPagamento` via `db.rpc` [Não Iniciada ⏳]
### 4.2 `ConsultarPagamentoManual` [Não Iniciada ⏳]
nao_consta: "Consultado no TJSP em dd/mm/aaaa hh:mm: o processo não consta na lista de pagamentos" (sem afirmar "nenhum pagamento feito"); falha: mensagem com etapa + "tente novamente".
### 4.3 Edge `disparar-valor-pago`: propagar `resultado`/`etapa` no erro [Não Iniciada ⏳]

## FASE 5 — Frontend: log recolhível + rótulo FOR-169 [Não Iniciada ⏳]  (após 4)
### 5.1 `ConsultasTjspLog` (Collapsible) em `RequisitorioDepre` abaixo dos andamentos, e no ramo `depre.length===0`; recarrega após consulta manual [Não Iniciada ⏳]
### 5.2 `src/lib/leads.ts`: "Não (consultado em dd/mm)" quando consultado_em e valor zero (verificar o que FOR-169 já faz) [Não Iniciada ⏳]
### 5.3 Testes (vitest) dos rótulos/estados [Não Iniciada ⏳]

## FASE 6 — Ramo condicional B (só se bancos diferentes) [Não Iniciada ⏳]
6B: worker `GET /consultas?processo_depre=` (secret) + edge lê dele; SQL fica só no banco da VPS.

## FASE 7 — Deploy e validação [Não Iniciada ⏳]
Ordem manual: (1) confirmar banco (0.2); (2) aplicar SQL 3.1 no SQL Editor do banco correto; (3) deploy worker na VPS (/opt/precatorio-worker: git pull, build, `pm2 restart precatorio-crawler`; tolera RPC ausente); (4) merge PR frontend na precatorio-sp + redeploy edge se alterada; (5) smoke: reconsultar 0145616-63.2020.8.26.0500 no admin e ver log e "não consta"; conferir FOR-169.

## Sequência / paralelismo
Sequencial: 1 -> 2 -> (contrato) -> 4 -> 5 -> 7. Paralelo: 0.x e 3.x com 1-2. Frontend PR só abre após contrato do worker estável.

## Riscos
- Detecção validada em 2 casos reais; risco residual: mudança futura no layout GeneXus (TXTNENHUM). Default seguro = falha.
- Bancos possivelmente diferentes (0.2).
- Lovable pode alterar a branch frontend em paralelo: git fetch antes do PR.
- Log via RPC anon: sem PII, aceitável.

### Comentários:
- Gate 1 aprovado: 2 PRs, tabela, retenção 20, origens manual|busca_publica|crawler.
- Validação no portal concluída (2 casos reais, fixtures salvos).

### Atualização (pós autorização b)
- 0.1 CONCLUÍDA ✅: sonda rodada pelo humano na VPS; fixtures salvos; regra final de classificarResultado registrada.


## STATUS DE EXECUÇÃO (FOR-171)
- Fases 1, 2, 3 (cortex-v1) e 4, 5 (frontend) implementadas; testes: crawler 66/66 (`npm test`, tsc limpo), frontend 139/139 (`bun test`, `tsc --noEmit` limpo). Fase 6 (ramo B) NÃO implementada (só documentada). Fase 7 (deploy) manual, depende de confirmar o banco da VPS.
- Achados do code-review tratados: PDF ausente => falha (não marca consultado); RPC de escrita com now()/limites de tamanho e poda por criado_em; mensagem crua do banco fora do log; falha 200 no admin; fuso do log; edge buscar-precatorio manda origem=busca_publica.
- Ressalva conhecida: GRANT de registrar_consulta_pagamento a `authenticated` (o worker autentica assim); log é auxiliar.
