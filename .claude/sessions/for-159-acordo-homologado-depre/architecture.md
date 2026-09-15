# Architecture: FOR-159 — Persistir "acordo homologado" (.0500)

## Visão de alto nível

**Antes:** `djen_depre.andamentos` (jsonb) já guarda, desde o commit `2f36e91`, os
itens da tabela "Petições diversas" do e-SAJ (incluindo "Comunicado de Acordo de
Requisitório"), mas misturados com os da tabela "Movimentação" — sem nenhum campo
estruturado que diga, direto, "este `.0500` teve acordo homologado". Qualquer
consumidor (grid admin, e-mail) precisaria varrer o jsonb toda vez.

**Depois:** `djen_depre` ganha `acordo_homologado boolean NULL`, calculado uma vez
em `persistRequisitorio()` (mesmo momento em que `andamentos` é montado) e
persistido junto no upsert. Consumidores fazem `select acordo_homologado from
djen_depre where cnj_normalizado = ...` (ou JOIN por `numero_depre`), sem parsear
jsonb.

```mermaid
flowchart LR
    A[e-SAJ .0500\nfichas HTML] -->|extractAndamentos +\nextractPeticoesDiversas| B[andamentos: Andamento[]\ncrawl.ts:crawlRequisitorio]
    B --> C[persistRequisitorio\nsupabase.ts]
    C -->|computa a partir de andamentos| D[(djen_depre\n+ acordo_homologado)]
    D -->|JOIN numero_depre| E[FOR-160: grid admin]
    D -->|JOIN numero_depre| F[FOR-161: e-mail / site público]
```

## Componentes impactados

| Componente | Mudança |
|---|---|
| `sql/2026-09-13_for159_acordo_homologado_coluna.sql` (novo) | `ALTER TABLE djen_depre ADD COLUMN acordo_homologado boolean;` + backfill imediato via `UPDATE` a partir do jsonb já existente (só afeta `.0500` cujo `andamentos` já reflete o parser novo — ver "Limitações"). |
| `worker-crawler/src/supabase.ts` | `persistRequisitorio()` passa a computar `acordo_homologado` (boolean) a partir de `andamentos` e incluir no `row` do upsert. |
| `worker-crawler/src/supabase.ts` (teste) | `parse.test.ts` ou teste dedicado cobrindo o cálculo do flag a partir de um array de `andamentos` de exemplo (com e sem o item "Comunicado de Acordo de Requisitório"). |
| `sql/2026-09-13_for159_enfileira_backfill_restante.sql` (novo) | Enfileira, com `origem='backfill'`, os `.0500` de `djen_depre` cujo `acordo_homologado` ainda é `null` (i.e., ainda não foram re-crawleados com o parser novo). |

Nenhum componente é removido. `extractPeticoesDiversas()`/`extractAndamentos()`
(já existentes) não mudam — só o consumidor em `supabase.ts` muda.

## Convenções mantidas

- Scripts SQL avulsos e datados em `sql/`, aplicados manualmente no SQL Editor —
  convenção real do projeto desde FOR-102 (~jul/2026); `supabase/migrations/` está
  parado desde FOR-76 (jun/2026) e não será revivido aqui (decisão confirmada com o
  usuário).
- `origem='backfill'` pra trabalho de fila que não deve competir com prioridade —
  padrão já estabelecido em `sql/2026-08-16_for143_claim_prioriza_nao_backfill.sql`
  e reforçado hoje mesmo em `sql/2026-09-13_corrige_prioridade_recrawl_0500.sql`
  (depois de um incidente real de fila entupida nesta própria sessão).
- Nome de coluna/estilo (`snake_case`, boolean nullable pra "ainda não verificado")
  segue o mesmo espírito de `incidentes.cessao_credito` (FOR-143), mas SEM replicar
  a arquitetura de classificador (`classificacao_regras` + `classify_processo`)
  porque a fonte do dado (`andamentos` de UM `.0500`) já está disponível inteira no
  momento do upsert — não precisa de um segundo passo de classificação em lote.

## Interdependências externas

Nenhuma nova. Reusa infraestrutura existente: Supabase (`djen_depre`,
`crawler_queue`), RPCs `enqueue_crawler_job_forcado`/`claim_crawler_jobs`, e-SAJ
(via `esaj.ts`, sem mudança).

## Limitações e premissas

- **Cobertura do backfill imediato:** o `UPDATE` inicial só consegue popular
  `acordo_homologado` (`true`/`false`, não `null`) para `.0500` cujo `andamentos`
  já foi persistido por um crawl feito DEPOIS do deploy de hoje (commit `2f36e91`,
  2026-09-13) — isto é, os ~1670 do lote de deals já re-crawleados. Os ~55 mil
  restantes ficam `null` até serem re-crawleados (enfileirados como `backfill`
  nesta mesma issue, mas o *processamento* da fila é assíncrono e pode levar dias).
- **Sem acesso direto ao banco de produção nesta sessão** — migration e backfill
  são entregues como scripts `.sql`; a aplicação real depende do usuário rodar no
  SQL Editor (mesmo padrão de toda a sessão anterior a esta issue).
- **Um `.0500` pode não ter petição alguma** (nem "Comunicado de Acordo", nem
  qualquer outra) — nesse caso, depois de re-crawleado, o flag deve ficar `false`
  (não `null`) porque FOI verificado e não achou. A distinção correta é "andamentos
  contém itens da tabela Petições diversas" (mesmo que zero relevantes) → `false`,
  vs. "andamentos ainda não passou pelo parser novo" → `null`. Isso é decidido pela
  DATA do último crawl (`ficha_crawled_at >= '2026-09-13'`), não pela presença de
  `andamentos`.

## Trade-offs e alternativas consideradas

| Alternativa | Por que não |
|---|---|
| Coluna espelhada em `incidentes` (como `cessao_credito`) | Exigiria lógica de propagação pra todos os incidentes que compartilham o mesmo `numero_depre` (potencialmente vários credores por `.0500`), e um passo de sincronização toda vez que o vínculo `numero_depre` mudar (forward ou reverso, FOR-156). O dado nasce e mora no `.0500`; duplicar cria uma segunda fonte de verdade sem necessidade — FOR-160/161 já vão fazer JOIN por `numero_depre` de qualquer forma pra pegar outros campos de `djen_depre` (saldo, status). |
| `boolean NOT NULL DEFAULT false` | Mais simples de implementar, mas reintroduz exatamente a ambiguidade que motivou o incidente de hoje (query sempre `false` mesmo com dado real) — impede diferenciar "verificado, sem acordo" de "não verificado ainda", o que FOR-160 precisa pra não mostrar falso-negativo pra ~55 mil `.0500` durante o backfill. |
| View computada em vez de coluna persistida | Evitaria escrever a lógica em dois lugares (TS + SQL), mas o filtro usa `jsonb_array_elements` + `ilike` num array por linha — mais caro de indexar/filtrar em um grid com paginação (mesma lição de `sql/2026-07-XX` sobre SECURITY DEFINER bloquear inlining: filtros sobre expressão calculada tendem a não usar índice). Coluna simples permite índice parcial se necessário no futuro. |

## Consequências adversas

- Enquanto o backfill dos ~55 mil não terminar, `acordo_homologado` fica `null`
  pra maioria da base — aceitável (é o estado transitório esperado), mas FOR-160
  não deve subir o filtro público até esse backfill avançar o suficiente (ver nota
  em FOR-160).
- Mais um campo de tempo (`ficha_crawled_at`) vira crítico pra decidir se um `null`
  é "não verificado" ou "processo sem depre real" — já existe hoje, sem mudança de
  contrato, mas passa a ter mais um consumidor lógico.

## Principais arquivos a modificar/criar

- `sql/2026-09-13_for159_acordo_homologado_coluna.sql` (novo)
- `sql/2026-09-13_for159_enfileira_backfill_restante.sql` (novo)
- `worker-crawler/src/supabase.ts` (editar `persistRequisitorio`)
- `worker-crawler/src/parse.test.ts` ou novo arquivo de teste (cobrir o cálculo do flag)

---

## ✅ Verificação de Consistência

**Data**: 2026-09-13
**Status**: ✅ APROVADO

### Checklist
- [x] context.md e architecture.md consistentes (mesma decisão de schema: boolean
      nullable; mesma convenção de migration: `sql/` avulso; mesmas limitações de
      acesso ao banco)
- [x] Conforme especificação de negócio — não há spec de negócio formal pra esta
      issue além do card Linear FOR-159, que está refletido integralmente
- [x] Conforme padrões/convenções do projeto — `origem='backfill'`, scripts `sql/`
      datados, e ausência de propagação pra `incidentes` (ao contrário de
      `cessao_credito`) todos justificados contra convenções já documentadas
- [x] Valores e regras de negócio conferidos (filtro `ilike 'Comunicado de Acordo de
      Requisit%'`, mesmo já validado em `sql/2026-09-13_diag_acordo_depre.sql`)

### Correções Aplicadas
Nenhuma — primeira versão já consistente.

### Notas
As duas decisões de arquitetura (schema nullable, convenção de migration) foram
tomadas explicitamente com o usuário durante esta fase (`/engineer:start`), não
inferidas unilateralmente.
