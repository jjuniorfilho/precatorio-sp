# Context: Captura de precatórios federais via DJEN — caderno completo (TRF1-6)

**Issue:** FOR-145 (projeto Linear "Precatório Federal")
**Branch:** `jjuniorfilho/for-145-captura-precatorios-federais-djen`

## Contexto (por quê)

O produto (Portal de Consulta de Precatórios) está validado para SP (estado + municípios) e agora expande para o âmbito federal — mesmo playbook de captura DJEN + classificação + persistência já usado no fluxo estadual (FOR-68/70/72), mas com uma vantagem estrutural: a classe processual do CNJ é padronizada nacionalmente (diferente de nome de parte, que varia por ente), permitindo uma classificação mais confiável desde o início.

Esta entrega é **100% infraestrutura de dados** (captura + classificação) — não expõe nada no produto público ainda; é pré-requisito de dados para uma futura busca federal.

## Objetivo (meta)

Capturar o caderno DJEN completo dos 6 Tribunais Regionais Federais (TRF1-6), classificar cada publicação (conhecimento / cumprimento de sentença / precatório-RPV) e persistir de forma estruturada, reaproveitando o schema existente (`processos`→`cumprimentos`→`incidentes`, `djen_depre`, `djen_dias`, `coleta_config`, `classificacao_regras`).

## Estratégia (direcional)

- **Novo arquivo dedicado** `worker-crawler/src/ingest-djen-federal.ts` (não refatora `ingest-djen.ts` — evita risco de regressão no job diário do TJSP já em produção). Reaproveita conceitos (fetch paginado via API Comunica, idempotência via `djen_dias`/`coleta_runs`), mas sem os pontos específicos de TJSP que não se aplicam (`PARTES_ALVO_DEFAULT`, `isDepre()` por sufixo `.8.26.0500`, `esfera()`/`sistemaFromLink()` restritos a TJSP).
- **Sem filtro de `nomeParte` no servidor** — aceita o volume maior (15k+/dia medido no TRF3) por não existir lista curada de entes públicos federais ainda.
- **Classificação híbrida**: `codigoClasse`/`nomeClasse` do payload DJEN como sinal primário (classe 1265 = Precatório, 1266 = RPV confirmadas; classe de "cumprimento de sentença" **ainda não confirmada** — precisa de amostra real antes de codar a regra definitiva) + `classificacao_regras` (ILIKE/regex sobre teor) como refinamento, mesmo mecanismo do FOR-72 `classify_processo`.
- **Schema**: reaproveita `processos`/`cumprimentos`/`incidentes`/`andamentos`, adicionando colunas `tribunal` e `sistema` + valor `'Federal'` em `ente_esfera` — sem tabelas paralelas. **Correção:** `djen_depre` NÃO é reaproveitado — esse table serve o conceito de requisitório `.0500` com número próprio (TJSP), que não existe no federal (confirmado: só processo principal + cumprimento de sentença).
- **Sem crawler de origem** → sem hierarquia real descoberta. Usa o padrão de placeholder já existente no projeto (incidente `Indefinido` do FOR-71, `LEGADO-` do FOR-143): cada `cumprimentos` federal pendura num `processos` placeholder; uma `incidentes` "vaso" 1:1 (não é registro jurídico separado, `numero_depre` sempre NULL) hospeda a classificação de `classify_processo()`/`classificacao_regras`, reaproveitados intocados. O teor da publicação DJEN vira uma linha em `andamentos`.
- **`coleta_config`**: uma linha por TRF (6 linhas), liga/desliga independente por tribunal — encaixa no rollout faseado.
- **Detecção de sistema sem roteamento**: grava se o link aponta pra PJe (`pje1g.trfN.jus.br`) ou eproc (`eproc*.jf*.jus.br` / `eproc1g.trf6.jus.br`) — confirmado ao vivo, split limpo 3×3. Não enfileira/crawleia o processo em si (fora de escopo).
- **Rollout faseado por sistema**:
  - Fase A — PJe (TRF1, TRF3, TRF5): backfill 3-5 dias, valida classificação, liga captura diária.
  - Fase B — eproc (TRF2, TRF4, TRF6): só após Fase A estável.
- **Concorrência/rate-limit**: início conservador (concorrência menor / delay maior que os defaults do estadual `concurrency=3`/`delayMs=400`) — nunca rodamos 3 tribunais em paralelo antes, e o volume por TRF já é maior que o do TJSP filtrado por nomeParte. Ajustar pra cima depois de confirmar que a API aguenta.
- **Cron/processo separado** do job diário do TJSP — evita contenção de concorrência/rate-limit com a captura estadual já em produção.

## APIs/ferramentas envolvidas

- API Comunica (`comunicaapi.pje.jus.br/api/v1/comunicacao`) — mesma API já usada no estadual, parametrizada por `siglaTribunal` (TRF1..TRF6). Testada ao vivo nesta sessão: não filtra por `codigoClasse` no servidor (só client-side); volume real >15k/dia só no TRF3 (amostra 2026-09-01).

## Validação

- Backfill de 3-5 dias por TRF da Fase A, revisão manual de amostra de classificação (meta: >90% de acerto precatório/RPV vs revisão humana) antes de ligar captura diária contínua.
- N dias consecutivos de captura sem erro antes de considerar a fase "pronta".

## Dependências

- Confirmar código(s) de classe CNJ de "cumprimento de sentença" com amostra real de 1-2 TRFs antes de codar a regra definitiva (pendência já registrada na issue e no brainstorm).
- Migração de schema: coluna `tribunal`/`esfera='Federal'` nas tabelas reaproveitadas + 6 linhas novas em `coleta_config`.
- Worker-crawler roda na VPS (mesma infra do pipeline estadual, `pm2 precatorio-crawler`) — precisa de config de cron/processo separado.

## Limitações / fora de escopo

- Sem crawler de dados do processo em si (tipo Playwright/e-SAJ) para o federal — só captura + classificação da publicação DJEN.
- Sem roteamento ativo pro sistema de origem (PJe/eproc) — só detecção/gravação do sistema.
- Campo novo além do schema atual: não implementar direto, trazer para discussão antes.

## Referências

- `worker-crawler/src/ingest-djen.ts` — pipeline TJSP atual (ponto de partida conceitual).
- `docs/business-context/brainstorm/precatorio-federal-classificacao-djen-2026-09-05.md` — decisão de classificação híbrida.
- Issue [FOR-145](https://linear.app/forjuris/issue/FOR-145/captura-de-precatorios-federais-via-djen-caderno-completo-trf1-6) — PRD completo (WHY/WHAT/HOW/ROLLOUT/RISCOS/MÉTRICAS).
