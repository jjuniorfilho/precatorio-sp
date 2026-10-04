# Context: FOR-198 — Categorizar erros de consulta (captcha/timeout/bloqueio/rate limit)

> Modo autônomo (fleet-orchestration). As 3 decisões de arquitetura abaixo já foram
> tomadas pelo humano (comentário de 2026-10-04 na issue) — este documento não reabre
> Gate 1, só registra o entendimento para a implementação.

## Motivação

Hoje não existe NENHUMA categoria estruturada de erro na coleta. O que existe:

- `pagamentos-tjsp.ts`: campo `etapa` (`Etapa`, union já existente em `pagamentos-passos.ts`)
  + mensagem de erro em texto livre. "Captcha não resolvido" só aparece dentro do texto.
- `index.ts`/`esaj.ts`: só distingue "sessão morta" (regex `/HTTP (429|5\d\d)/`) do resto.
  429/5xx já tem retry/backoff/circuit-breaker — só não é EXIBIDO como categoria própria.
- Bloqueio de IP não tem detecção nenhuma. Comentário em `crawl.ts` admite: "indistinguível
  entre página de manutenção do TJSP, bloqueio, e CNJ que nunca foi e-SAJ" — os três cenários
  respondem 200 OK sem o conteúdo esperado.

## Decisões já tomadas (não é Gate 1 de novo)

1. **Classificar NO WORKER, na hora do erro** (não regex em leitura posterior). Mensagens já
   truncam em 2000 chars antes de persistir — classificar depois é classificar em dado
   degradado. `pareceSessaoMorta()` em `index.ts` já é precedente desse padrão.
2. **"Bloqueio/manutenção suspeito" é exposto, sempre com aviso de incerteza** — nunca
   escondido, nunca apresentado como certeza.
3. **Persiste, não é só função em memória**:
   - `coleta_runs.detalhe` já é jsonb — sem migration necessária para este escopo (não usado
     nesta issue; capacidade só confirmada).
   - `crawler_queue` precisa de migration pequena: coluna `erro_categoria text` nullable +
     estender `fail_crawler_job` para aceitar `p_categoria`.
   - Categoria como `text` simples validado por union TypeScript (mesmo padrão de `Etapa`),
     não enum nativo do Postgres.

## Escopo desta sessão (decisão mecânica, não nova arquitetura)

A decisão #3 cita explicitamente só `crawler_queue`. `pagamentos-tjsp.ts` também está na lista
de arquivos relevantes da issue e alimenta o 2º painel do protótipo ("Consultas ao TJSP" /
`pagamentos_consultas_log`). Aplicando o MESMO princípio (#3) e o MESMO padrão de migration
(coluna nullable + parâmetro novo em RPC existente, sem mudar estrutura nenhuma nova) também a
`pagamentos_consultas_log`/`registrar_consulta_pagamento` — é extensão mecânica da decisão já
tomada, não uma decisão nova. Reportado explicitamente ao humano no handback para confirmação/
reversão fácil (é um arquivo de migration isolado, não aplicado em produção por este agente).

## O que NÃO está no escopo

- UI do `/admin/coleta` (tooltips, exibição por categoria) — issue separada FOR-197.
- Enum nativo do Postgres — decidido contra (#3).
- Mudar o comportamento de retry/circuit-breaker existente (429/5xx) — só passa a ficar
  rotulado como categoria, sem mudar a lógica de backoff/sessão/circuit breaker.
- RPC de LEITURA (dashboard/contagens por categoria) — fora do escopo (FOR-197).

## Arquivos relevantes (confirmados por leitura real)

- `worker-crawler/src/pagamentos-passos.ts` — `Etapa` (padrão a espelhar), `PassosCollector`,
  `ConsultaPagamentoErro` (ganha campo `categoria`).
- `worker-crawler/src/pagamentos-tjsp.ts` — `consultarInterno` tem UM catch-all no fim que
  envolve qualquer erro não-`ConsultaPagamentoErro` numa `ConsultaPagamentoErro` — ponto único
  de classificação para captcha/bloqueio/timeout/outro nesse fluxo. `consultarEPersistirPagamentos`
  é quem chama `deps.registrar` (→ `registrarConsultaPagamento`) — persiste a categoria ali.
- `worker-crawler/src/index.ts` — `processBatch` tem o catch do loop principal (crawler e-SAJ);
  já tem `pareceSessaoMorta` (regex 429/5xx) e `buscaNuncaSaiuDoSeed` (sinal de "provavelmente
  eproc", disparado só na ÚLTIMA tentativa) — ambos informam a classificação sem duplicar lógica.
- `worker-crawler/src/esaj.ts` — `fetchHtml` já lança `Error("HTTP ${status}")` em 429/5xx
  (mensagem chega ao catch de `index.ts` já com o código embutido).
- `worker-crawler/src/crawl.ts` — comentário admite ambiguidade bloqueio/manutenção/CNJ-ausente
  em `crawlSeed`/`crawlRequisitorio` quando a busca nunca sai do seed.
- `worker-crawler/src/supabase.ts` — `failJob()` (RPC `fail_crawler_job`) e
  `registrarConsultaPagamento()` (RPC `registrar_consulta_pagamento`) são os 2 pontos de escrita
  que precisam do novo parâmetro.
- `sql/2026-09-25_for171_1_tabela_pagamentos_consultas_log.sql` /
  `sql/2026-09-25_for171_2_rpc_registrar_consulta_pagamento.sql` — schema/RPC de pagamentos.
- `supabase/migrations/20260627195519_for73_fila_crons_monitor.sql` — schema/RPC originais de
  `crawler_queue`/`fail_crawler_job`.

## Achado de código real: não existe sinal confiável de "CNJ não encontrado" distinto de
"bloqueio suspeito" no fluxo cpopg

`crawlSeed`/`crawlRequisitorio` só têm UM sinal quando a busca nunca sai do seed — o próprio
código já documenta a ambiguidade. A única aproximação real e já existente no código é
`buscaNuncaSaiuDoSeed` + ÚLTIMA tentativa (`job.tentativas + 1 >= MAX_TENTATIVAS_FILA`), que é
exatamente a condição que hoje reclassifica o job como `eproc_pendentes` (`parkAsEproc`) — ou
seja, o próprio pipeline já trata "ambíguo + esgotou tentativas" como evidência suficiente de
"provavelmente nunca existiu no e-SAJ". Reuso dessa condição exata para a categoria
`cnj_nao_encontrado`; em qualquer tentativa anterior à última, o mesmo sinal classifica como
`bloqueio_suspeito` (incerto, conforme decisão #2). Não finjo um sinal que não existe.
