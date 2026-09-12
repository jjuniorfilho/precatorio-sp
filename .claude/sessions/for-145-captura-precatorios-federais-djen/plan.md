# Captura de precatórios federais via DJEN — PJe (TRF1, TRF3, TRF5) — FOR-145

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

Sem integração frontend (esta entrega é 100% infraestrutura de dados — não expõe nada no produto público).

**Split de escopo (2026-09-12):** esta issue cobria originalmente TRF1-6. A Fase B (eproc: TRF2, TRF4, TRF6) virou issue própria — [FOR-156](https://linear.app/forjuris/issue/FOR-156/captura-de-precatorios-federais-via-djen-eproc-trf2-trf4-trf6). FOR-145 fecha só com a Fase A (PJe) estável em produção contínua.

## FASE 1 — Schema (migration SQL) [Completada ✅]

Base de dados pronta pra receber dados federais, sem quebrar nada do fluxo estadual em produção.

### Migration `sql/2026-09-06_for145_schema_federal.sql` [Completada ✅]

- `ALTER TABLE processos ADD COLUMN tribunal TEXT, ADD COLUMN sistema TEXT CHECK (sistema IN ('pje','eproc','outro'))`
- Mesmas colunas em `cumprimentos` (denormalizado, mesmo padrão de conveniência já usado em `incidentes.processo_id`)
- `ALTER TABLE processos DROP CONSTRAINT ... , ADD CONSTRAINT ... CHECK (ente_esfera IN ('Estadual','Municipal','Outro','Federal'))`
- `djen_dias`: adicionar coluna `tribunal TEXT NOT NULL DEFAULT 'TJSP'`, trocar PK de `(data)` para `(data, tribunal)` — cuidado: precisa dropar e recriar a PK preservando as linhas existentes (que ficam implicitamente `TJSP`).
- `coleta_config`: `ALTER ... DROP CONSTRAINT` do CHECK de `rotina` e recriar incluindo `caderno_djen_trf1`..`caderno_djen_trf6`.
- Seed das 6 linhas em `coleta_config` (rotina `caderno_djen_trfN`), `params` com `classes_relevantes` (mesma lista já usada em `caderno_dje`) + `itens_por_pagina`. `enabled=false` para todas inicialmente — liga-se manualmente por tribunal conforme a Fase 5/6 avançar.

### Validação [Completada ✅]

- [x] Migration rodada no SQL Editor pelo usuário em 2026-09-06, sem erros.
- [ ] Confirmar que o job `caderno_dje` estadual continua rodando sem erro após a mudança de PK do `djen_dias` (checar `coleta_runs` do dia seguinte) — checagem de regressão fica pendente pro próximo ciclo do cron diário (não bloqueia a Fase 2).

### Comentários
- Não temos acesso direto ao banco a partir deste ambiente (sem `SUPABASE_URL`/service_role preenchidos no `.env` local) — a validação de schema (colunas/constraints/seed) e a checagem de regressão do job estadual dependem do usuário confirmar via SQL Editor / `coleta_runs`.

## FASE 2 — Fetch + observabilidade (sem classificação/persistência) [Completada ✅]

Valida a mecânica de captura contra a API real antes de acoplar lógica de negócio.

### `worker-crawler/src/ingest-djen-federal.ts` — esqueleto [Completada ✅]

- CLI: `tsx src/ingest-djen-federal.ts --tribunal=TRF3 --date=2026-09-01` (mesma interface de `--date`/`--from`/`--to`/`--backfill` do `ingest-djen.ts`).
- Fetch paginado (mesma API Comunica, `siglaTribunal` parametrizado), sem filtro `nomeParte`.
- Detecção de `sistema` via domínio do `link` (`pje1g.` → pje; `eproc` → eproc; senão outro) — função pura, testável isoladamente.
- Grava só `djen_dias` (contadores: total, por sistema) + `coleta_runs` — **sem** tocar `processos`/`cumprimentos`/`incidentes` ainda.
- Delay entre páginas conservador (maior que o `DELAY_MS` do estadual) — valor inicial a definir em código, ajustável via env, sem endurecer no fonte.

### Validação [Completada ✅]

- [x] Rodado manualmente 1 dia (2026-09-01) × TRF3 (pje) e × TRF2 (eproc) pelo usuário — sem erro 429/504, `djen_dias`/`coleta_runs` populados corretamente nos dois.

### Comentários
- Volume real e comportamento da API (sem filtro server-side por classe, custo de paginação) já foram medidos ao vivo na sessão de `/engineer:start` — ver `architecture.md` e o doc de brainstorm.
- Ambiente de desenvolvimento local (sandbox do Claude Code) não tem credenciais reais do Supabase (`.env` com placeholders) — toda validação contra API/banco real precisa ser rodada pelo usuário (local com `.env` preenchido, ou na VPS).
- Lembrete pra quem pegar a Fase 3: as 6 linhas de `coleta_config` (`caderno_djen_trf1..6`) ficaram com `enabled=false` no seed da Fase 1 — foram habilitadas manualmente e só pra TRF2/TRF3 durante este teste pontual. Reavaliar se devem voltar a `false` até a Fase 5 (rollout formal) ou ficar ligadas.

## FASE 3 — Classificação [Completada ✅]

### Matching por `nomeClasse` (texto) [Completada ✅]

- Reaproveita a lógica de `classes_relevantes` (normalização + substring match) já existente em `ingest-djen.ts` — extrair pra uma função pura compartilhável (sem tocar no arquivo estadual, só extrair o que já existe pra um módulo comum, ex: `worker-crawler/src/djen-classes.ts`) OU duplicar a função pura (decisão de plan-time, baixo risco por ser função sem estado).
- Determina o balde: conhecimento / cumprimento de sentença / precatório-RPV, a partir da lista seedada em `coleta_config.caderno_djen_trfN.params.classes_relevantes`.
- Teste unitário (padrão `parse.test.ts`/`import-csv-legado.test.ts` já existentes no projeto) cobrindo pelo menos os 5 nomes de classe da lista + 1 caso "não bate" (conhecimento).

### Refinamento por teor (`classificacao_regras`) [Completada ✅ — nada a fazer]

- Confirmado: nenhum código novo necessário. `classificacao_regras`/`classify_processo()` já existem e operam sobre `andamentos.descricao` — só entram em uso quando a Fase 4 persistir a publicação como `andamentos`. Nada a reaproveitar/adaptar antes disso.

### Validação [Completada ✅]

- Ambiente sem credenciais de banco (ver comentário da Fase 2) — validação feita com um script descartável (fora do repo) que busca ~1000 publicações reais do TRF3 (2026-09-01) direto da API e roda `classificaPorNomeClasse`/`deveCapturar` localmente, sem persistir nada.
- Resultado real: 92/1000 (9,2%) capturadas, 100% `CUMPRIMENTO DE SENTENÇA CONTRA A FAZENDA PÚBLICA` — sem falso-positivo (variantes "de Ações Coletivas" corretamente excluídas).
- Nenhuma publicação de classe `Precatório`/`Requisição de Pequeno Valor`/`Procedimento do Juizado Especial da Fazenda Pública` apareceu nessa amostra específica de 1000 — só valida o balde `cumprimento_sentenca` por ora; os outros 3 baldes ficam sem confirmação empírica ainda (aceitável, a lógica é a mesma função pura testada unitariamente pros 6 casos).

### Comentários

- **Achado crítico corrigido**: o match bidirecional (`alvo.includes(c) || c.includes(alvo)`, copiado do padrão de `classes_relevantes` do estadual) deixava "CUMPRIMENTO DE SENTENÇA" genérico (privado, entre particulares) bater contra a classe pública configurada, porque o nome curto observado é prefixo do nome longo configurado. Corrigido pra match numa direção só (`alvo.includes(c)`). **O mesmo bug provavelmente existe em `ingest-djen.ts` (estadual, em produção)** — não mexido (fora de escopo/risco de regressão), mas vale abrir uma issue própria pra investigar.
- **Achado que mudou o modelo**: a checagem de parte passiva federal (`destinatarios.polo==='P'`) que a Fase 3 originalmente ia usar como filtro obrigatório **não funciona pros dados federais** — confirmado em amostra real (1000 publicações do TRF3): a classe bateu 288x, a parte só bateu 2x, porque `destinatarios` no payload federal só lista quem é intimado (normalmente o autor/credor), não o réu. A classe processual virou o filtro único e suficiente (ela já restringe a casos contra Fazenda Pública por definição da Tabela Processual Unificada do CNJ); a checagem de parte (`enteFederalPublico`/`detectaEnteFederal`) virou um fallback best-effort e informativo (destinatarios → teor), não um gate.
- Lembrete pra Fase 4: `detectaEnteFederal()` existe e pode popular `processos.ente_nome` quando achar algo — mas retorna `null` com frequência (a amostra só achou via teor, nunca via destinatarios) — tratar como opcional, não obrigatório.

## FASE 4 — Persistência (árvore + placeholder) [Completada ✅]

### Upsert `processos` (placeholder) → `cumprimentos` → `incidentes` (vaso) → `andamentos` [Completada ✅]

- [x] Implementado em `planoPersistencia()` (puro) + `persistFederal()` (I/O, reaproveita `upsertReturningId`/`classifyProcesso` de supabase.ts).
- [x] Balde `conhecimento` → só `processos` real (pelo próprio CNJ).
- [x] Demais baldes → `processos` placeholder (`FEDPLACEHOLDER-<cnj_normalizado>`) + `cumprimentos` (o CNJ real) + `incidentes` "vaso" 1:1 (`${cnj}-VASO`, `numero_depre` sempre NULL, `tipo_previsto` = Precatorio/RPV/Indefinido conforme balde) + `andamentos` (teor, hash de dedupe padrão).
- [x] `classify_processo()` chamado após persistir (intocado).
- [x] Falha em 1 publicação não derruba o dia inteiro — captura o erro, conta em `itens_erro`/`erros`, segue pras próximas (status vira `erro_parcial` se houver alguma falha).
- [x] `ingestDayFederal()` conectado: classifica + persiste dentro do loop de fetch; `djen_dias`/`coleta_runs` ganham `capturados`/`porBalde`/`erros`.

### Validação [Completada ✅]

- [x] Rodado pelo usuário na VPS de produção (`/opt/precatorio-worker`, deploy via scp — VPS não é repo git) pra 1 dia × TRF3 (2026-09-01) — sem erro, dados aparecem certos no `/admin/processos` (`tribunal='TRF3'`, hierarquia placeholder→cumprimento→incidente, `macrofase`/`fase` preenchidos).

### Comentários
- Ambiente sem credenciais de banco neste sandbox (mesma limitação das Fases 1-3) — código e testes puros validados aqui; a escrita real e o deploy na VPS foram feitos e confirmados pelo usuário.
- **Lembrete de deploy pra quem mexer nisso depois**: a VPS de produção (`/opt/precatorio-worker`) não é um clone git — deploy é `scp` dos arquivos de `worker-crawler/src/` + `npm run build` + (se for religar o loop) `pm2 restart`. `ingest-djen-federal.ts` já foi copiado manualmente pra lá durante esta sessão de validação, ANTES do merge/PR — não esquecer de reconciliar isso quando a branch for mergeada (evitar sobrescrever com uma versão desatualizada, ou vice-versa).

## FASE 5 — Rollout Fase A (PJe: TRF1, TRF3, TRF5) [Em andamento ⏳]

### Backfill de validação (3-5 dias por TRF) [Completada ✅ 2026-09-08]

- Rodado nos 3 tribunais para 2026-09-01 a 09-04 (09-05 sempre veio vazio nos 3 — provável defasagem de publicação, não é erro). `coleta_config` já estava com `enabled=true` pros 3 (`caderno_djen_trf1/3/5`) antes desta sessão.
- **Achado crítico:** `DAY_TIMEOUT_MS` (default 20 min, `config.ts`) é curto demais pro volume real federal (25-65k publicações/dia por tribunal — bem acima do estimado no PRD). Quase todos os dias bateram no timeout na primeira rodada. Subido pra `DAY_TIMEOUT_MS=10800000` (3h) no `.env` da VPS — resolveu a maioria, mas não todos (ver abaixo).
- **Achado 2 — contenção entre processos:** quando um dia estoura o timeout, a promise órfã continua rodando em segundo plano (comportamento documentado em `ingest-djen-federal.ts`), mas se outro processo (outro dia/tribunal) começa a rodar em paralelo, os dois competem pelo mesmo rate-limit do Comunica e travam quase por completo (~1 página/hora em vez de ~1 página/5s). Um processo órfão não identificado (`PPID=1`, origem desconhecida) ficou 4h43min preso em só 5 páginas por causa disso — matado manualmente. **Regra daqui pra frente: nunca rodar mais de 1 backfill de dia por vez contra o Comunica**, mesmo entre tribunais diferentes.
- Resultado final — todos os 15 dia-tribunal (TRF1/3/5 × 01-05) com `status='ok'`:
  - TRF1: 01=12.550, 02=20.170, 03=15.758, 04=7.916 capturados (total 56.394)
  - TRF3: 01=5.470, 02=6.214, 03=5.167, 04=4.388 capturados (total 21.239)
  - TRF5: 01=2.454, 02=2.819, 03=3.102, 04=1.945 capturados (total 10.320)
- **Observação a investigar na revisão manual:** 100% dos ~88 mil itens capturados caíram no balde `cumprimento_sentenca` — zero em `precatorio`, `rpv` ou `conhecimento` nos 3 tribunais/4 dias. Pode ser o perfil real do caderno no período, ou sinal de que a classificação não está pegando as outras classes — confirmar/descartar na próxima etapa.

### Revisão manual de amostra [Aceita ✅ 2026-09-12 — decisão do usuário]

- **Decisão (2026-09-12):** validação leve + os achados/correções abaixo aceitos como suficientes pra fechar esta etapa. A amostra completa de 20-30/tribunal do PRD **não vai ser feita** — escopo encerrado aqui por decisão explícita do usuário ("pode fechar a Fase 5 e paramos aqui").
- Revisão leve feita (não os 20-30/tribunal completos do PRD): 3 registros do TRF3 conferidos manualmente pelo usuário — classe/executado/teor batem, sem falso-positivo.
- **Achados da investigação de `oficio_expedido`/`macrofase`:**
  - RLS faltante em `classificacao_regras` (mesma causa raiz do `coleta_config`, ver `sql/2026-09-06_fix_coleta_config_rls.sql`) — corrigida (`sql/2026-09-12_fix_classificacao_regras_rls.sql`).
  - Terminologia federal real de expedição de ofício diverge do padrão estadual copiado (`%ofício requisitório%expedido%`). Frase real encontrada em amostra (TRF1): **"...registros necessários junto ao Tribunal Regional Federal..."**. Regra nova adicionada em `classificacao_regras`.
  - Reclassificação em massa (35.101 processos federais distintos) via `select classify_processo(...)` direto no SQL Editor **deu timeout/erro de servidor** duas vezes — resolvido rodando via script Node (paginado + `runPool` concorrência 15) direto do worker, ~10min, 0 erros.
  - **Resultado:** `oficio_expedido=true` subiu de 684 → **9.133** (13x) com a nova regra. `macrofase` continua 100% `direito_creditorio` (0 em `precatorio_efetivo`/`rpv_efetivo`) — **gap estrutural conhecido, não relacionado a terminologia**: `macrofase` só avança quando `tipo_previsto` também é `'Precatorio'`/`'RPV'`, e isso só é setado quando a própria classe CNJ da publicação é literalmente "Precatório"/"RPV" (nunca visto nos 4 dias capturados, só "Cumprimento de Sentença"). Decisão de produto em aberto: promover `tipo_previsto` a partir do teor (mesmo sem a classe CNJ mudar formalmente) ou aceitar que só migra quando uma publicação futura do mesmo CNJ vier com a classe certa (upsert no mesmo incidente "vaso" já suporta isso automaticamente).
### Cron/processo separado na VPS [Não Iniciada ⏳ — pendente, sessão pausada aqui em 2026-09-12]

- Configurar cron/pm2 dedicado pro federal (separado do job diário do TJSP) — mesma infra (`pm2 precatorio-crawler`), processo/schedule próprio.
- **Único item que falta pra captura contínua em produção estar de fato ligada.** A validação (backfill + revisão) já foi fechada — isso aqui é só configuração/deploy, sem decisão de produto pendente.
- **Atenção ao achado de contenção acima:** o cron diário roda 1 dia por tribunal (não 5), volume bem menor — mas nunca sobrepor a janela dos 3 tribunais entre si nem com backfills manuais futuros.

### Comentários
- Esta fase é o gate real de "produção" — só avança pra Fase 6 se N dias consecutivos rodarem sem erro (métrica do PRD).
- `DAY_TIMEOUT_MS=10800000` já está setado permanentemente no `.env` da VPS (`/opt/precatorio-worker/.env`) — não é preciso reconfigurar em runs futuros.
- **2026-09-12 — sessão pausada por decisão do usuário:** backfill + revisão de amostra fechados (ver acima). Cron fica pendente pra próxima sessão — é o único bloqueador restante antes de FOR-145 poder ser considerada "Done".

## FASE 6 — Rollout Fase B (eproc: TRF2, TRF4, TRF6) [Movida para FOR-156]

Split de escopo 2026-09-12 — ver [FOR-156](https://linear.app/forjuris/issue/FOR-156/captura-de-precatorios-federais-via-djen-eproc-trf2-trf4-trf6). Continua dependendo da Fase 5 deste documento estar estável (rollout sequencial, decisão original do PRD: eproc só depois de PJe estável).

---

## Sequenciamento

- Fases 1→2→3→4 são **estritamente sequenciais** (cada uma depende do artefato da anterior).
- Fase 5 é o gate de fechamento deste documento (FOR-145/PJe) — as validações **dentro** dela (backfill de TRF1/TRF3/TRF5) podem rodar em paralelo entre si já que são tribunais independentes, desde que a concorrência/delay global continue conservador (risco de rate-limit é por IP/origem, não por tribunal isolado, mas ver achado de contenção acima: nunca mais de 1 dia por vez contra o Comunica).
- Migration da Fase 1 é bloqueante pra tudo — nada de código roda sem ela.
- Fase 6 (eproc) segue em [FOR-156](https://linear.app/forjuris/issue/FOR-156/captura-de-precatorios-federais-via-djen-eproc-trf2-trf4-trf6), só depois desta Fase 5 estar estável.
