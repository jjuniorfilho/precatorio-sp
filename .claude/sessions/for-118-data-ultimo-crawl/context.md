# Context: FOR-118 — Data do último crawl (filtro + coluna) em Processo × Incidente / Processos

> Issue: https://linear.app/forjuris/issue/FOR-118

## ⚠️ Regras Críticas do Projeto (Project Briefing)

- **NUNCA** expor CPF completo — sempre mascarar (`123.***.***-00`). N/A nesta feature (não toca em dado pessoal novo).
- **SEMPRE** usar RLS no Supabase para proteger tabelas sensíveis. `crawler_queue` já tem RLS (admin-only, `authenticated`) — reaproveitada, sem policy nova.
- **SEMPRE** normalizar input antes de buscar. N/A (filtro é data/boolean, não texto livre).
- **SEMPRE** armazenar valores monetários em centavos. N/A (sem valor monetário nesta feature).
- **Performance**: base grande (incidentes ~305k linhas), índices corretos são obrigatórios antes de subir função nova pra produção.
- Nomenclatura: snake_case em tabelas/colunas/funções Supabase.

## ⚠️ Correção pós-architecture.md (2026-07-31)

O "Como" abaixo (subquery correlacionada em `crawler_queue`) ficou **obsoleto** assim que
a fase de Estruturação Arquitetural descobriu que `processos.last_crawled_at` já existe e
já é mantido pelo worker (`worker-crawler/src/supabase.ts:111`, só em sucesso). Plano
técnico atual e definitivo: **`architecture.md`** nesta mesma pasta. O "Por que" e "O que"
abaixo continuam válidos — só a implementação SQL mudou (mais simples: sem trigger, sem
coluna nova, sem subquery em `crawler_queue`).

## Contexto Específico da Feature

### Por que
Admin não sabe quando um incidente foi crawleado com sucesso pela última vez, nem consegue filtrar por isso — precisa pra priorizar recrawl de dados velhos. Coluna "Crawler" hoje só mostra status da tentativa mais recente (ok/erro/pendente/processando), não uma data.

### O que
Dois campos novos — **Data último crawler** (timestamp do último job `status='ok')` e **Crawleado** (booleano derivado: existe algum `ok` histórico) — expostos como filtro (De/Até + Sim/Não/Todos) e coluna de grid, em **duas telas**:

1. `/admin/processo-incidente` (`frontend/src/routes/admin.processo-incidente.tsx`) — grid flat, RPC `buscar_processos_incidente` + `contar_processos_incidente`.
2. `/admin/processos` (`frontend/src/routes/admin.processos.tsx`) — grid agrupado por processo raiz, RPC `buscar_processos_agrupado`.

Escopo ampliado pra cobrir as duas telas foi decidido nesta sessão (aprovado pelo usuário) porque a subquery de `crawler_status` já existe idêntica nas duas RPCs — fazer só uma teria deixado a UI inconsistente.

Definição confirmada com o usuário: "último sucesso, ignorando falhas recentes" — se a tentativa mais recente falhou mas uma anterior teve sucesso, a data/booleano refletem o último `ok`, não a tentativa mais recente (isso é o que já existe como `crawler_status`, que não muda).

CSV export de ambas as telas ganha as duas colunas novas também.

### Como (visão geral — detalhe completo na issue e em architecture.md)

- Nova subquery correlacionada em `crawler_queue` (mesmo `processo_codigo` = `pg.processo_cnj` já usado por `crawler_status`), filtrando `status='ok'`, pegando `max(updated_at)`.
- Novos parâmetros `p_crawler_data_de`, `p_crawler_data_ate`, `p_crawleado` nas 3 RPCs.
- Risco de performance conhecido: índice atual não cobre `status='ok'` — pode precisar de índice parcial. Mesma classe de problema já visto em FOR-108/111/116 (ver `patterns/security-definer-bloqueia-inlining.md` na memória).

### Validação
- **Sem staging** — só produção. Validar com `EXPLAIN ANALYZE` (somente leitura) antes de criar índice/função definitivos.
- Depois de aplicado, testar manualmente as duas telas no browser (dev server do frontend apontando pro Supabase real).

### Repos e branches desta sessão
- `cortex-v1` (SQL/RPC): branch `jjuniorfilho/for-118-data-ultimo-crawl-processo-incidente`, criada a partir da ponta da cadeia `jjuniorfilho/for-116-timeout-por-job` (⚠️ `main` está desatualizado, sem nenhum SQL de FOR-68+ — nunca branchear direto dele neste repo).
- `frontend` (React): branch `jjuniorfilho/for-118-data-ultimo-crawl-processo-incidente`, criada a partir da ponta `jjuniorfilho/for-115-definir-senha`.

### Rollout
Aplicar SQL no Supabase SQL Editor primeiro (padrão do projeto — sem CI de migration), depois deploy do frontend. Sem feature flag, sem RLS novo.
