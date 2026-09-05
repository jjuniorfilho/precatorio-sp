# Context: FOR-143 — Importar precatórios de dump CSV legado

> Linear: https://linear.app/forjuris/issue/FOR-143

## ⚠️ Regras Críticas do Projeto (Project Briefing)

> Nota: `docs/technical-context/project-briefing.md` e `briefing/backend-conventions.md` estão
> desatualizados (descrevem o schema pré-FOR-68: tabela `precatorios` simples, sem
> `processos`/`incidentes`/`partes`). A fonte de verdade real do schema é
> `supabase/migrations/*.sql` e `sql/*.sql`. As regras abaixo (`critical-rules.md`) continuam
> válidas e foram checadas contra o schema atual.

- **NUNCA** expor CPF completo — sempre mascarar (`123.***.***-00`) nas respostas públicas.
  Não se aplica diretamente aqui (script grava direto no banco, não expõe nada), mas o CPF
  gravado em `partes.documento` deve ser **sem máscara, só dígitos** (convenção já usada
  pelo crawler).
- **SEMPRE** normalizar input antes de comparar: CNJ/CPF/CNPJ sem `.`/`-`/`/`/espaços.
- **SEMPRE** armazenar valores monetários em **centavos** (`BIGINT`), nunca `float`.
- Tabelas `processos`/`incidentes`/`partes` são RLS **admin-only** (`authenticated`) — sem
  policy `anon`. O script roda com `service_role` (bypassa RLS), igual ao `worker-crawler`.

## Contexto Específico da Feature

### Motivação (por quê)
Temos um CSV de terceiro (`precatorio_sp_202608161955.csv`, 29.647 linhas) com precatórios de
SP. Uma parte relevante desses casos provavelmente ainda não foi descoberta pelo nosso crawler
e-SAJ (que depende de descoberta via DJE diário/backfill, processo por processo). Esse dump
permite preencher lacunas na base sem depender do ritmo do crawler.

### Meta (resultado esperado)
Script one-off (`worker-crawler/src/import-csv-legado.ts`, roda uma vez via `tsx`, descartável
depois) que:
1. Lê o CSV.
2. Pra cada linha **completa** (tem `origin_process_number` + `incident_number` +
   `depre_number` — 28.392 de 29.647 linhas; as outras 1.255 são ignoradas por falta de dado),
   verifica se já existe na base via match **AND**:
   - CNJ raiz (de `origin_process_number`, formato `CNJ/NNNN`) + `numero_incidente` batem
     contra `processos.cnj_normalizado` + `incidentes.numero_incidente`, **E**
   - `depre_number` bate contra `incidentes.numero_depre`
   Só é "já temos" (pulado) se AMBAS baterem.
3. Insere os registros ausentes direto em `processos` → `incidentes` → `partes` →
   1 `andamento` sintético → chama `classify_processo()`.
4. Gera log final: inseridos vs. já existentes, com amostra.

### Decisões de escopo (histórico de perguntas já respondidas)
- **Match**: AND entre as duas chaves (CNJ+incidente E numero_depre). Qualquer divergência =
  registro novo.
- **Linhas só-DEPRE** (sem `origin_process_number`/`incident_number`): **fora de escopo**,
  não importar (mesmo existindo `djen_depre` como destino natural pra esse padrão — decisão
  explícita do usuário foi manter o escopo restrito a processo+incidente+depre completos).
- **Linhas completas mas sem `debtor_entity`** (7.281 de 28.392, ≈26%): **importar mesmo
  assim** — `ente_nome`/`ente_esfera` ficam `NULL` (schema permite), `flag_sp` continua
  `true` (o requisitório `.0500` já garante TJSP/SP independente do devedor ser conhecido).
- **Elegibilidade**: quando há evidência de ofício expedido (`depre_number`/`oc_number`
  presentes), marcar `termo_declaracao=true` junto — termo sempre precede o ofício no fluxo
  TJSP, então essa inferência é segura e evita `elegivel=false` incorreto.
- **`ente_esfera`**: reusar `classifyEsfera()` (`worker-crawler/src/parse.ts:55`), **estendendo**
  seu regex pra cobrir entidades que hoje caem em `'Outro'` mas aparecem no CSV: USP, UNESP,
  UNICAMP, IPREM, DAEE, DERSA, SPTRANS, IAMSPE, DETRAN, PROCON, FUNDAÇÃO CASA, ARTESP,
  autarquias hospitalares municipais, CEETEPS, FDE, HCFAMEMA, FURP, SUCEN, JUCESP, TATUÍPREV
  (e outras institutos de previdência municipal — sufixo `PREV` fora de SP capital). Estender
  o arquivo compartilhado beneficia o crawler também, não só esse script.
- **`tipo_previsto`**: fica `'Indefinido'` — CSV não tem coluna 1:1 (Precatorio vs RPV).
- **`partes.fonte`**: precisa de migration adicionando `'csv_legado'` ao `CHECK` constraint
  (hoje só aceita `'esaj'`/`'djen'`).
- **`processo_codigo` placeholder**: reusar o padrão de `upsertReturningId(..., onConflict:
  "processo_codigo")` já existente em `worker-crawler/src/supabase.ts:84`. Placeholder
  determinístico: `LEGADO-{cnj_normalizado}` (processos) e
  `LEGADO-{cnj_normalizado}-{numero_incidente}` (incidentes) — nunca colide com código real
  do e-SAJ (que é numérico) e torna o script idempotente numa re-execução (upsert, não
  insert puro).
- **Classificação sem crawler real**: inserir 1 `andamento` sintético (ex.: "Ofício
  requisitório expedido", `data = decision_date`) quando houver evidência de ofício, casando
  com os padrões já em `classificacao_regras`, e então chamar a RPC `classify_processo()` —
  reusa a lógica de derivação existente em vez de duplicá-la.
- **Refresh automático**: registros com `processo_codigo` placeholder **não podem** entrar no
  ciclo `enqueue_stale_processos` (o worker tentaria abrir um código falso no e-SAJ e
  falharia). Inserir com `next_crawl_at = NULL`.
- **`nature`**: sem coluna 1:1 no schema — só referência no log, não grava em lugar nenhum.

### Estratégia (direcional)
- Script em `worker-crawler/src/import-csv-legado.ts` (Node/TS via `tsx`, mesmo padrão de
  `reclassify-oc.ts`/`ingest-djen.ts`), usando `@supabase/supabase-js` com `service_role`.
- Migration nova em `sql/` (convenção atual pós-FOR-76, aplicada manualmente no SQL Editor)
  estendendo o `CHECK` de `partes.fonte`.
- Suporte a `--dry-run` (só relatório, sem grava nada) — obrigatório dado o volume (28k linhas
  na base de produção).
- Concorrência limitada no batch de escrita (mesmo padrão de pool usado na reclassificação em
  massa do FOR-107→112) — aqui não há chamada de rede por linha, é só volume de inserts.

### Validação
- Rodar primeiro em `--dry-run` e conferir a contagem (inseridos vs. já existentes) contra
  expectativa manual de uma amostra.
- Conferir alguns registros inseridos direto no banco (RLS admin/`service_role`) — CNJ
  normalizado bate, valores em centavos corretos, `elegivel`/`fase`/`macrofase` derivados
  como esperado via `classify_processo()`.
- Conferir que uma segunda execução do script (idempotência) não duplica nada.

### Dependências
- `worker-crawler/src/parse.ts` → `classifyEsfera()` (a estender)
- `worker-crawler/src/supabase.ts` → padrão `upsertReturningId`, `classifyProcesso()`
- `supabase/migrations/20260627192837_for69_schema_base_propria.sql` (schema base)
- `supabase/migrations/20260627202859_for72_classificacao.sql` (`classify_processo`,
  `classificacao_regras`)
- Migration nova: extensão do CHECK de `partes.fonte`

### Complemento via disparo único pro crawler (decisão adicional)
Pra não deixar os dados importados incompletos (sem advogado/andamentos reais) permanentemente,
o script também enfileira, **uma única vez**, o CNJ real de cada caso recém-importado
(`origem='backfill'`) — o worker resolve sozinho via `searchByCnj` (a fila aceita CNJ cru, não
só código interno do e-SAJ, o worker detecta via `isCnj()`).

Dois problemas resolvidos pra viabilizar isso:
1. **Duplicata processos/incidentes**: hoje `persistTree()` faz upsert por `processo_codigo`.
   O crawl real grava com o código real do e-SAJ (≠ nosso placeholder `LEGADO-...`), criando
   uma segunda linha em vez de completar a existente. Fix: `persistTree()` passa a
   **reconciliar** — antes do upsert, se já existir uma linha com o mesmo `cnj_normalizado`
   (processos) ou `numero_depre` (incidentes) com `processo_codigo LIKE 'LEGADO-%'`, atualiza
   o `processo_codigo` dessa linha existente pro código real antes de seguir o fluxo normal —
   aí o upsert por `processo_codigo` (agora igual) atualiza a mesma linha em vez de criar outra.
   `partes` já é substituído por completo a cada crawl (delete+insert), então os dados
   sintéticos/CSV somem sozinhos quando o real chega. `andamentos` sintéticos convivem com os
   reais (upsert por hash, sem conflito) — inofensivo, os textos sintéticos continuam batendo
   nos padrões de `classificacao_regras`.
2. **Não atrapalhar processamento diário**: em vez de espaçar os ~28k jobs no tempo (frágil,
   depende de estimar throughput), muda-se `claim_crawler_jobs` pra sempre priorizar
   `dje_diario`/`manual`/`refresh` sobre `backfill` na ordenação de retirada da fila — o
   backfill só consome capacidade ociosa, nunca atrasa descoberta diária nem ações
   interativas do usuário (ex.: consulta OAB ad-hoc). Mudança pequena e reusável por qualquer
   backfill futuro, não só esse.

### Limitações conhecidas
- ~26% dos registros importados terão `ente_nome`/`ente_esfera` nulos até o crawl real
  complementar (devedor desconhecido no CSV).
- `tipo_previsto` fica `'Indefinido'` até o crawl real complementar.
- Sem SLA pro complemento — depende de quando o worker consegue consumir a fila de backfill
  (capacidade ociosa entre jobs diários/refresh/manuais).

## Branch
`jjuniorfilho/for-143-importar-precatorios-csv-legado` (criada a partir de
`jjuniorfilho/for-118-...`, que já tem todo o schema FOR-68 consolidado — `origin/main` está
desatualizado e não contém as migrations do épico).
