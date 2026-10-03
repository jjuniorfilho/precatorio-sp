# FOR-195 — processo principal real acima do cumprimento (legado)

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

Decisões de arquitetura aprovadas pelo humano em `architecture.md` (seção "Decisões confirmadas").
Modo autônomo — sem gates humanos de plano/implementação; para no PR aberto, sem merge, sem
disparar os ~24k jobs reais.

## FASE 1 — RPC SQL [ ]

### Migration `sql/2026-10-02_for195_merge_legado_cumprimento_para_principal.sql`
RPC `merge_legado_cumprimento_para_principal(p_processo_atual_id, p_processo_principal_id)`:
move `cumprimentos`/`incidentes`/`partes` do processo atual (que hoje faz de raiz errada) pro
principal real, insere uma linha `cumprimentos` representando o antigo "processo" (ele é, de
fato, um cumprimento), apaga a linha `processos` antiga. REVOKE PUBLIC/anon + GRANT
service_role/authenticated. Idempotente.

### Sandbox `sql/sandbox/for195_validate_local.sh`
Postgres 15 local descartável (schema FOR-69 mínimo). Reproduz o caso real (DEPRE
0436868-90.2025.8.26.0500 → cumprimento 0018028-13.2022.8.26.0562 → principal
1000594-91.2022.8.26.0562): estado pré (processos=cumprimento com filhos) → chama a RPC →
confere pós (processos=principal; cumprimentos tem 2 linhas — a original + a nova representando
o antigo "processo"; incidentes/partes todos sob o principal). Idempotência (2ª chamada no-op).
Guarda (principal inexistente → exceção).

## FASE 2 — Worker [ ]

### `fetchProcessoPrincipal` em `crawl.ts`
Busca a página do processo indicado (`showByCodigo`), extrai `processoPrincLink`; se achou,
busca a página do principal (2ª chamada) e roda `extractCapa`/`extractPartes` nela. Retorna
`null` quando a própria página já é raiz (sem link) — mesma regra da FOR-196 (nada a fazer:
já está correto).

### `reconcilePrincipalReal` em `supabase.ts`
Upsert do `processos` row do principal via `upsertReturningId(..., "processo_codigo")` (mesmo
padrão de `persistTree`) + chamada à RPC nova quando o id do principal ≠ id do processo atual.
Exporta `cnjNorm` (já existe, só precisa do `export`).

### Script `backfill-legado-cumprimento-principal.ts`
Mirror de `import-csv-legado.ts`: `--apply` (obrigatório pra gravar; sem ele, modo relatório),
`--limit=N` (smoke test), loop **serial** (sem `runPool`, concorrência=1 — aprovado pelo humano).
Consulta os candidatos (incidentes legado já reconciliados ao cumprimento), chama
`fetchProcessoPrincipal` + `reconcilePrincipalReal` por candidato, registra em `coleta_runs`.
Nunca dispara sozinho — só roda sob comando explícito do operador na VPS, e só com `--apply`
depois que o humano autorizar ("pode disparar").

### Testes
- `parse.test.ts`: cobertura nova de `processoPrincLink`/`codigoForoFromHref` (gap existente,
  zero cobertura antes desta issue).
- `supabase-merge-legado-principal.test.ts`: orquestração de `reconcilePrincipalReal` com banco
  fake em memória (mesmo padrão de `supabase-persist-tree-legado.test.ts`).
- `crawl-processo-principal.test.ts`: `fetchProcessoPrincipal` via `mock.module` (padrão novo do
  FOR-196, `--experimental-test-module-mocks`) — casos "achou link" e "não achou (já é raiz)".

## FASE 3 — pre-pr / PR [ ]
Review (code-reviewer + adr-compliance), suíte completa + sandbox SQL, PR para `main`.
PARA no PR aberto — sem merge, sem `--apply` contra produção, sem disparar os ~24k jobs reais.
