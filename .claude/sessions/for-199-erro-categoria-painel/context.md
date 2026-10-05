# Context: FOR-199 — Expor categorização de erros na tela (RPC + painéis)

> Modo autônomo (fleet-orchestration). Issue bem-escopada (follow-up mecânico de FOR-198 +
> FOR-197, sem decisão de arquitetura nova): sem gate humano bloqueante — este documento
> registra o entendimento antes de implementar, e a verificação adversarial do lead substitui
> a aprovação.

## Motivação

FOR-198 (mergeado, PR cortex-v1 #39) classifica erros do worker (`captcha | timeout |
rate_limit | site_indisponivel | bloqueio_suspeito | cnj_nao_encontrado | outro`) e persiste em
`crawler_queue.erro_categoria` e `pagamentos_consultas_log.erro_categoria` — mas só no backend.
Zero RPC de leitura, zero UI. FOR-197 (mergeado, PR frontend #83) redesenhou `/admin/coleta`
(tooltips, glossário, saúde geral) mas foi instruído a não tocar nessa parte. Buraco de escopo
entre as duas issues.

## Meta

1. RPC(s) nova(s) em cortex-v1 agregando `erro_categoria` das 2 tabelas.
2. 2 painéis em `admin.coleta.tsx`:
   - Extensão de "Fila do crawler e-SAJ" (já existe, FOR-108/FOR-197): breakdown dos erros
     atuais da fila por categoria (barra + lista, mesmo padrão visual de `FilaBarraProporcional`).
   - Card novo "Consultas de pagamento (TJSP)": total/sucesso/falhas (últimas 24h) + breakdown
     de falhas por categoria.
3. Tooltip de explicação da categorização (texto do protótipo, aviso de incerteza de
   "Bloqueio/manutenção suspeito").
4. Adicionar os termos ao glossário do FOR-197.

## Protótipo (lido via Artifact, `project/Main.dc.html` do canvas 8PPH95e6pLSGeqWL3WKSPG)

Textos e estrutura confirmados por leitura real do artboard (não é suposição):

- Painel "Fila do crawler e-SAJ": barra de progresso dos 5 status existente (inalterada) +
  seção nova abaixo ("Os N erros, por categoria") com uma barra fininha por categoria
  (label + `n · pct%`), só para as linhas com `n > 0`, ordenadas por `n` desc. Sem filtro de
  tempo (mesma semântica do breakdown de status: estado ATUAL da fila, não janela).
- Tooltip da fila: *"Bloqueio/manutenção suspeito" é a categoria mais incerta: o e-SAJ
  respondeu 200 OK, mas sem o conteúdo esperado — hoje o código não consegue distinguir entre
  manutenção do TJSP, bloqueio de IP e um CNJ que nunca existiu no e-SAJ (os três voltam
  parecidos). "Rate limit" é 429/5xx explícito — esse sim o worker já detecta e trata (renova
  sessão, espera com backoff).*
- Card "Consultas de pagamento (TJSP)": header com badge "Últimas 24h", 2 KPIs (Total de
  consultas, Sucesso + %), e abaixo "Falhas por categoria (N no total)" com a mesma barra por
  categoria.
- Tooltip do card de pagamentos: *Consulta ao vivo do portal "Pagamentos Precatórios" do TJSP
  (Playwright, resolve captcha sozinho) — pipeline separado do crawler e-SAJ acima. A falha é
  classificada pela ETAPA em que parou: Site indisponível = não conseguiu nem abrir o portal;
  Captcha não resolvido = o portal abriu mas o captcha foi rejeitado em todas as tentativas;
  Timeout = alguma etapa não respondeu a tempo; Outro = o resto (ex.: formato de resposta
  inesperado).*
- Termos de glossário do protótipo a incorporar: "Captcha (consulta de pagamento)" e "Rate
  limit vs. bloqueio".

**Divergência consciente do protótipo**: o mock só lista 5 categorias no card da fila (sem
`captcha`/`site_indisponivel`, que no mock são exclusivas do card de pagamentos) e 5 no card de
pagamentos (sem `rate_limit`/`cnj_nao_encontrado`). Mas o CHECK constraint do FOR-198 permite as
7 categorias em AMBAS as tabelas — o worker pode, na prática, gravar qualquer uma nas duas. A
UI real vai renderizar dinamicamente só as categorias com `n > 0` retornadas pela RPC (não uma
lista fixa de 5), então nenhuma categoria fica escondida se aparecer. Reportado como nota, não
como pergunta — é extensão mecânica do mesmo padrão "só mostra o que tem", já usado em
`FilaBarraProporcional`.

## Resultado esperado

- RPC `crawler_queue_erro_categoria_counts()`: breakdown dos erros ATUAIS da fila
  (`status = 'erro'`) por `erro_categoria` (inclui `NULL` → "Não classificado", erros
  anteriores ao FOR-198).
- RPC `pagamentos_consultas_resumo()`: total/sucesso/falhas das últimas 24h (`iniciada_em`) +
  breakdown de falhas por categoria, de `pagamentos_consultas_log`.
- `admin.coleta.tsx` consome as 2 novas RPCs via `lib/api/coleta.ts`, sem quebrar nada do
  redesign do FOR-197 (glossário, tooltips, saúde geral já existentes).

## Estratégia (direcional)

- RPCs `SECURITY DEFINER`, mesmo padrão de `crawler_queue_status_counts` /
  `listar_consultas_pagamento` (admin roda anônimo, RLS/GRANT bloqueiam SELECT direto —
  memória `admin-anon-rpc`).
- `crawler_queue_erro_categoria_counts`: `language sql stable`, mesma forma de
  `crawler_queue_status_counts` (group by simples, sem filtro de tempo) — nenhuma mudança de
  schema necessária (coluna/CHECK já existem desde FOR-198).
- `pagamentos_consultas_resumo`: `language plpgsql stable` retornando `jsonb` (mesmo padrão de
  `listar_consultas_pagamento`), janela fixa de 24h hardcoded no SQL (mesmo padrão de
  `crawler_ritmo_processamento`, que também não parametriza a janela).
- Sem migration de schema (coluna/CHECK já aplicados em produção pelo FOR-198) — só funções
  novas, `CREATE OR REPLACE` (nomes novos, não precisa DROP).
- Validar em sandbox local (`sql/sandbox/for199_validate_local.sh`, padrão de
  `for198_validate_local.sh`) antes de considerar pronto.
- Frontend: estende `getQueueStats`-adjacent em `lib/api/coleta.ts` com 2 funções novas +
  tipos; estende `admin.coleta.tsx` na seção "Fila do crawler" existente (FOR-108) e adiciona
  card novo "Consultas de pagamento (TJSP)"; reusa `Collapsible`/padrão de tooltip já
  estabelecido pelo FOR-197 (não reinventa um componente de tooltip novo).

## Pré-requisito / freio de mão

As 2 migrations do FOR-198 (`sql/2026-10-04_for198_1_*.sql`, `..._2_*.sql`) **já estão
aplicadas em produção** (confirmado pela própria issue: "FOR-198 Done, backend only" e dado
real sendo gravado). Esta migration (FOR-199) só ADICIONA funções de leitura — não altera
schema nem funções de escrita existentes. **Não será aplicada em produção por este agente**:
fica pronta no PR para aplicação manual (ação irreversível/produção = freio de mão do modo
autônomo).

## Validação

- Sandbox Postgres local (`sql/sandbox/for199_validate_local.sh`): schema mínimo pós-FOR-198 +
  as 2 RPCs novas + casos (fila com e sem erros categorizados/não-categorizados, pagamentos com
  sucesso/falha dentro e fora da janela de 24h) + grants.
- UI: dev server da própria worktree do frontend, Playwright real, confirmando os 2 painéis
  renderizando com dado real (ou estado vazio/zero, se não houver erro real em produção no
  momento do teste) — nunca dado inventado.

## Arquivos relevantes (confirmados por leitura real)

- `sql/2026-10-04_for198_1_erro_categoria_crawler_queue.sql` / `..._2_...log.sql` — schema já
  aplicado (coluna + CHECK + `fail_crawler_job`/`registrar_consulta_pagamento` com
  `p_categoria`).
- `sql/2026-07-24_for108_observabilidade_coleta_rpcs.sql` — padrão de RPC de leitura admin-anon
  a espelhar (`crawler_queue_status_counts`, `crawler_ritmo_processamento`).
- `sql/2026-09-25_for171_1_tabela_pagamentos_consultas_log.sql` /
  `..._3_rpc_listar_consultas_pagamento.sql` — schema de `pagamentos_consultas_log` (RLS
  ligado, sem GRANT de tabela; só via RPC) e padrão de retorno `jsonb`.
- `frontend/src/lib/api/coleta.ts` — `getQueueStats`/`getRitmoProcessamento` (padrão de
  wrapper RPC a seguir para as 2 funções novas).
- `frontend/src/routes/admin.coleta.tsx` — seção "Fila do crawler" (`FilaBarraProporcional`) e
  onde entra o card novo "Consultas de pagamento (TJSP)"; precisa também do que o FOR-197
  adicionou (tooltips `info-btn`/`info-panel`, glossário) — ler a versão real do arquivo na
  worktree do frontend antes de editar (branch base `jjuniorfilho/precatorio-sp`, commit
  `9c7b454`), não a cópia do checkout principal (que estava desatualizada, sem o FOR-197).
