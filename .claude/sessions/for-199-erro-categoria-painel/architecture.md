# Architecture: FOR-199 — Expor categorização de erros na tela

## Visão de alto nível

```mermaid
flowchart LR
    subgraph DB[Postgres · cortex-v1]
      CQ[(crawler_queue.erro_categoria)]
      PCL[(pagamentos_consultas_log.erro_categoria)]
      RPC1[/crawler_queue_erro_categoria_counts/]
      RPC2[/pagamentos_consultas_resumo/]
      CQ --> RPC1
      PCL --> RPC2
    end
    subgraph FE[frontend · admin.coleta.tsx]
      API[lib/api/coleta.ts]
      FILA[Card "Fila do crawler e-SAJ"<br/>+ breakdown por categoria]
      PAG[Card novo "Consultas de pagamento (TJSP)"]
      GLOSS[Glossário — FOR-197]
    end
    RPC1 -->|anon, authenticated| API
    RPC2 -->|anon, authenticated, service_role| API
    API --> FILA
    API --> PAG
    API --> GLOSS
```

Estado anterior: `erro_categoria` gravado pelo worker (FOR-198), zero leitura. Estado
posterior: 2 RPCs novas + 2 pontos de UI consumindo-as, sem tocar no que o FOR-197 já fez
(saúde geral, KPIs com tooltip, glossário, `InfoButton`/`InfoPanel`).

## Componentes impactados

### cortex-v1 (backend/SQL)

- **Novo arquivo** `sql/2026-10-04_for199_rpc_erro_categoria.sql`:
  - `crawler_queue_erro_categoria_counts()` — `language sql stable security definer`,
    espelha exatamente `crawler_queue_status_counts()` (mesmo arquivo FOR-108): agrega
    `crawler_queue` filtrando `status = 'erro'`, `group by erro_categoria` (inclui `NULL`
    para erros anteriores ao FOR-198, sem categoria). `grant ... to anon, authenticated`
    (mesmo grant do sibling).
  - `pagamentos_consultas_resumo()` — `language plpgsql stable security definer` retornando
    `jsonb` (mesmo padrão de `listar_consultas_pagamento`, FOR-171), janela fixa de 24h sobre
    `iniciada_em` (mesmo campo/semântica que `listar_consultas_pagamento` ordena, mesma
    "hardcoded 24h" de `crawler_ritmo_processamento` — não parametriza a janela).
    Retorna `{ total, sucesso, falhas, falhas_por_categoria: [{erro_categoria, n}, ...] }`.
    `sucesso` = `resultado <> 'falha'` (RESULTADO_LABEL já trata `encontrado`/`nao_consta`
    como consulta bem-sucedida tecnicamente — só `falha` é falha técnica, ver
    `frontend/src/lib/consultas-pagamento.ts`). `grant ... to anon, authenticated,
    service_role` (mesmo grant de `listar_consultas_pagamento`).
  - **Sem mudança de schema** — coluna/CHECK já existem em produção desde FOR-198. Nenhum
    `DROP FUNCTION`/`ALTER TABLE` necessário: são 2 funções NOVAS (nomes nunca usados antes),
    `CREATE OR REPLACE` direto, idempotente/re-executável.
  - `NOTIFY pgrst, 'reload schema';` ao final (padrão do repo).
- **Novo arquivo** `sql/sandbox/for199_validate_local.sh` — Postgres efêmero local, schema
  mínimo PÓS-FOR-198 (coluna + CHECK já presentes, como as 2 tabelas chegariam em produção),
  valida as 2 RPCs novas (contagens corretas, `NULL` vira "sem categoria" na saída, janela de
  24h exclui consulta antiga, grants corretos) ANTES de pedir aplicação manual.

### frontend

- **`src/lib/api/coleta.ts`** (estende, não quebra nada existente):
  - `export type ErroCategoria = "captcha" | "timeout" | "rate_limit" | "site_indisponivel" | "bloqueio_suspeito" | "cnj_nao_encontrado" | "outro";`
  - `export interface CategoriaCount { erro_categoria: ErroCategoria | null; n: number; }`
  - `export interface PagamentosResumo { total: number; sucesso: number; falhas: number; falhasPorCategoria: CategoriaCount[]; }`
  - `export async function getCrawlerErroCategoriaBreakdown(): Promise<CategoriaCount[]>` —
    chama `crawler_queue_erro_categoria_counts`, mesmo padrão try/catch-log-default de
    `getQueueStats`.
  - `export async function getPagamentosConsultasResumo(): Promise<PagamentosResumo>` — chama
    `pagamentos_consultas_resumo` (retorna jsonb), default seguro `{total:0,sucesso:0,falhas:0,falhasPorCategoria:[]}`
    em erro (mesmo padrão).
  - `export const ERRO_CATEGORIA_LABEL: Record<ErroCategoria, string>` — mesmo padrão de
    `ROTINA_LABEL`/`RESULTADO_LABEL`:
    - `captcha`: "Captcha não resolvido"
    - `timeout`: "Timeout"
    - `rate_limit`: "Rate limit (429/5xx)"
    - `site_indisponivel`: "Site indisponível"
    - `bloqueio_suspeito`: "Bloqueio/manutenção suspeito"
    - `cnj_nao_encontrado`: "CNJ não encontrado no e-SAJ"
    - `outro`: "Outro"
- **`src/routes/admin.coleta.tsx`** (estende dentro das seções existentes, reaproveita
  `InfoButton`/`InfoPanel`/`openPanels` do FOR-197 — não cria mecanismo de tooltip novo):
  - 2 `useQuery` novos: `erroCrawler` (`getCrawlerErroCategoriaBreakdown`) e `pagamentosResumo`
    (`getPagamentosConsultasResumo`).
  - Componente `CategoriaBreakdown({ items, total })` (novo, local ao arquivo, mesmo nível de
    `FilaBarraProporcional`) — barra fininha + label + `n · pct%` por categoria, cor via mapa
    local `ERRO_CATEGORIA_COLOR` (presentation-only, fica no arquivo da rota, mesmo lugar de
    `QUEUE_COLORS`/`QUEUE_LABEL`, não em `coleta.ts`). Reusado nos 2 painéis (DRY — o protótipo
    desenha os 2 separados, mas é a mesma forma visual com os mesmos 7 rótulos possíveis).
    Paleta (só 5 tokens semânticos existem no design system — `success/warning/warning-dark/
    error/info` — 7 categorias precisam de 2 cores extra; reaproveita `bg-purple-500`, já usado
    em `admin.advogados.$advKey.tsx` para o mesmo propósito de categórica extra, e
    `bg-muted-foreground/NN` em duas opacidades para as 2 categorias "menos urgentes"):
    - `captcha` → `bg-warning`
    - `timeout` → `bg-info`
    - `rate_limit` → `bg-warning-dark`
    - `site_indisponivel` → `bg-error`
    - `bloqueio_suspeito` → `bg-purple-500` (categoria mais incerta — cor distinta de
      erro/warning para não sugerir certeza)
    - `cnj_nao_encontrado` → `bg-muted-foreground/70`
    - `outro` → `bg-muted-foreground/40`
    - `null` ("Não classificado") → `bg-muted-foreground/20`
  - Seção "Fila do crawler e-SAJ": dentro do card existente, abaixo de
    `<FilaBarraProporcional>`, só quando `q.erro > 0` — label "Os N erro(s), por categoria" +
    `InfoButton` com o texto exato do protótipo (bloqueio/manutenção suspeito vs. rate limit) +
    `<CategoriaBreakdown items={erroCrawler.data} total={q.erro} />`.
  - Novo card "Consultas de pagamento (TJSP)" — inserido entre "Circuit breaker" e "Refresh de
    ativos" (mesma ordem do protótipo): header com `InfoButton` (texto exato do protótipo sobre
    a classificação por etapa) + badge "Últimas 24h"; 2 KPIs (Total, Sucesso + %); abaixo,
    `<CategoriaBreakdown>` das falhas só se `falhas > 0`; estado vazio explícito ("Nenhuma
    consulta registrada nas últimas 24h.") quando `total === 0` — NUNCA mostra zeros/skeleton
    fantasma.
  - `GLOSSARIO`: +2 entradas (texto exato do protótipo) — "Captcha (consulta de pagamento)" e
    "Rate limit vs. bloqueio".

## Convenções mantidas

- Admin roda anônimo → leitura só via RPC `SECURITY DEFINER` (memória `admin-anon-rpc`),
  grants espelhando a RPC irmã de cada tabela.
- `TEXT` validado por CHECK no banco + union TypeScript no frontend (não enum nativo) — já
  decidido no FOR-198, só consumido aqui.
- `lib/api/coleta.ts`: toda função engole erro (`console.error` + default seguro), nunca deixa
  `useQuery(...).isError` virar `true` — convenção já estabelecida no arquivo, mantida (não é
  lacuna desta issue, ver nota do FOR-197 no mesmo arquivo).
- `InfoButton`/`InfoPanel`/`openPanels` (FOR-197) reaproveitados tal qual — nenhum componente
  de tooltip novo.
- Só renderiza o que tem dado (`n > 0`) — mesmo princípio de `FilaBarraProporcional`
  (`if (total === 0) return null`).

## Interdependências externas

Nenhuma nova. Mesmas tabelas/RPCs já existentes (`crawler_queue`, `pagamentos_consultas_log`),
mesmo cliente Supabase solto (`db.rpc`) já usado em todo `coleta.ts`.

## Limitações e premissas

- **Sem índice novo em `pagamentos_consultas_log`**: a tabela só tem índice em
  `(processo_depre, iniciada_em DESC)` (FOR-171) — a agregação de 24h faz full scan. Retenção é
  20 linhas por `processo_depre` (poda em `registrar_consulta_pagamento`), então o tamanho total
  é limitado pelo nº de processos distintos já consultados, não cresce sem limite por linha —
  aceito sem índice novo para esta issue (tela de admin, não hot path; adicionar índice é
  decisão de performance separada se o volume real justificar, não antecipada aqui).
- **Categorias do protótipo vs. CHECK real**: o protótipo mostra só 5 categorias por painel
  (um subconjunto diferente em cada um); o CHECK do FOR-198 permite as 7 em ambas as tabelas.
  A UI real é dinâmica (renderiza só `n > 0`, qualquer categoria), não trava nas 5 do mock —
  documentado em `context.md`, não é uma pergunta em aberto.
- **Erros pré-FOR-198** (`erro_categoria IS NULL`) aparecem como "Não classificado" — não são
  escondidos nem contados como "outro" (que é uma categoria classificada, distinta de "nunca
  foi classificado" — mesma distinção que a migration FOR-198 já documenta no comentário da
  coluna).

## Trade-offs e alternativas consideradas

- **1 RPC combinada (fila + pagamentos) vs. 2 separadas**: 2 separadas — tabelas/escopos
  diferentes, mesmo padrão do repo inteiro (uma RPC por tabela/preocupação, nunca uma RPC
  "deus"). Rejeitado combinar.
- **`jsonb` vs. `table(...)` para `pagamentos_consultas_resumo`**: `jsonb` — precisa devolver
  escalares (total/sucesso/falhas) + um array (breakdown) na mesma chamada; `table(...)`
  obrigaria denormalizar os escalares em cada linha do breakdown (lixo) ou 2 RPCs HTTP
  separadas (2 round-trips pra uma seção só). `jsonb` já é precedente no mesmo arquivo de
  origem (`listar_consultas_pagamento`).
- **Período fixo 24h vs. parâmetro**: fixo, sem parâmetro — mesmo padrão de
  `crawler_ritmo_processamento` (também 24h hardcoded); a issue não pede período configurável,
  e o protótipo mostra um badge estático "Últimas 24h".

## Consequências adversas

Nenhuma identificada: são 2 RPCs de leitura puras, sem efeito colateral, sem mudança de
contrato em função existente, sem migration de schema.

## Principais arquivos a modificar/criar

- `cortex-v1/sql/2026-10-04_for199_rpc_erro_categoria.sql` (novo)
- `cortex-v1/sql/sandbox/for199_validate_local.sh` (novo)
- `frontend/src/lib/api/coleta.ts` (editado)
- `frontend/src/routes/admin.coleta.tsx` (editado)

---

## ✅ Verificação de Consistência

**Data**: 2026-10-04
**Status**: ✅ APROVADO

### Checklist
- [x] context.md e architecture.md consistentes (mesmos 2 RPCs, mesmos nomes, mesma janela de
      24h só no painel de pagamentos, mesmos textos de tooltip extraídos do protótipo real)
- [x] Conforme especificação de negócio (issue FOR-199 + protótipo lido via Artifact,
      `project/Main.dc.html` real, não suposição)
- [x] Conforme padrões/convenções do projeto (RPC security definer admin-anon, `jsonb` para
      retorno composto, `InfoButton`/`InfoPanel`/`GLOSSARIO` do FOR-197 reaproveitados,
      `lib/api/coleta.ts` engole erro com default seguro)
- [x] Valores e regras de negócio conferidos (7 categorias do CHECK FOR-198, `sucesso` =
      resultado ≠ falha, janela 24h sobre `iniciada_em`)

### Correções Aplicadas
Nenhuma — primeira passada já consistente (modo autônomo, sem Gate 1 humano; verificação feita
pelo próprio lead antes de prosseguir, conforme autonomous-mode.md).

### Notas
Decisão de cor extra (`bg-purple-500` + 2 opacidades de `bg-muted-foreground`) é mecânica, não
arquitetural — o design system só tem 5 tokens semânticos para 7+1 categorias; resolvido
reaproveitando um padrão já existente no repo (`admin.advogados.$advKey.tsx`), não criando
token novo. Não escalado como freio de mão.
