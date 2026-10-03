# Context: FOR-195 — processo principal real (acima do cumprimento) continua sem ser capturado — parte 2 da FOR-178

Card: https://linear.app/forjuris/issue/FOR-195

## Regras críticas do projeto (resumo de docs/technical-context/briefing/critical-rules.md)

- RLS sempre; RPCs `security definer` nascem com EXECUTE liberado pra `PUBLIC`/`anon` por
  padrão no Postgres — SEMPRE `revoke all ... from public, anon` + `grant ... to service_role,
  authenticated` explícito logo após o `create or replace function` (erro já cometido 2x:
  FOR-174, FOR-143/corrigido no FOR-179).
- Busca/matching tolerante a formato: CNJ sempre comparado por `cnj_normalizado` (só dígitos).
- Nenhuma ação de produção (crawl real no e-SAJ, escrita em massa) nesta fase — é discovery.

## Escopo (já cravado pelo lead antes desta sessão, não re-descobrir)

~24.292 `incidentes` legado (heurística `processo_codigo LIKE 'LEGADO-%' <=> cumprimento_id IS
NULL`, confirmada sem exceção) já foram reconciliados pela FOR-178 até o nível do
**CUMPRIMENTO de sentença** — mas a **AÇÃO PRINCIPAL REAL** (um nível acima do cumprimento)
nunca foi capturada. O `processos` row que hoje existe pra esses casos tem `cnj` = CNJ do
CUMPRIMENTO, não da ação original — e é rotulado (PR #79, já mergeado) como "Cumprimento de
Sentença" em vez de "Processo principal (raiz)" quando não há dado melhor.

Exemplo real confirmado manualmente no e-SAJ pelo usuário:
- DEPRE: `0436868-90.2025.8.26.0500`
- Cumprimento (já correto no banco): `0018028-13.2022.8.26.0562`
- **Ação principal real (ainda não capturada):** `1000594-91.2022.8.26.0562`

Dois itens relacionados da mesma issue **já foram resolvidos e não fazem parte do escopo
restante**:
- Normalização de nomenclatura nas 3 telas admin → PR #79 (mergeado) + PR #80 (mergeado,
  páginas públicas).
- O caso dos ~347k incidentes NÃO-legado cujo cumprimento roda dentro do próprio processo
  principal (sem CNJ próprio) → separado pra **FOR-196** (backfill de 2 linhas, SEM recrawl,
  porque o crawler normal via `normalizeToRoot` já resolve a raiz certa pra todo processo
  não-legado — confirmado em `worker-crawler/src/crawl.ts:137-150`).

**Escopo REAL e único desta issue (FOR-195) a partir de agora**: os ~24.292 incidentes legado
que exigem **recrawl** (confirmado: `worker-crawler` não arquiva HTML bruto em lugar nenhum —
o link `a.processoPrinc`/a ausência da seção de incidentes nunca viraram campo persistido, só
foram usados em memória na hora do crawl original — então não dá pra reconciliar com dado já
existente, tem que buscar o e-SAJ de novo).

## Meta desta sessão (discovery, NÃO build)

Não implementar nada. Investigar o código real o suficiente para:
1. Confirmar/aprofundar o mecanismo de reconciliação já estabelecido pela FOR-178
   (`merge_legado_processo_para_cumprimento`, `reconcileLegadoCumprimento`, `processoPrincLink`,
   `normalizeToRoot`).
2. Documentar, com evidência de código, as 3 decisões de arquitetura que o lead já identificou
   como pendentes (ver `architecture.md`) — sem resolvê-las sozinho, porque são "nova decisão
   arquitetural" (ADR novo / novo boundary), uma das 3 classes de freio de mão do modo
   `/engineer:fleet-autonomous`.
3. Parar no freio de mão: `context.md` + `architecture.md` completos e commitados, gate de fase 1
   verificado, SEM `/plan`, SEM `/work`, SEM PR.

## Abordagem técnica (resumo direcional, do card — não detalhar implementação aqui)

Pra cada incidente legado já reconciliado até o cumprimento (FOR-178):
1. Buscar a página do próprio CUMPRIMENTO no e-SAJ (via `showByCodigo`/`searchByCnj` — mesmas
   primitivas de `esaj.ts` já usadas em `normalizeToRoot`), SEM subir a árvore inteira.
2. Procurar `a.processoPrinc` nela (mesmo parser `processoPrincLink` de `parse.ts`).
3. **Achou** → é a ação principal real. Criar/achar a `processos` row correspondente — cuidado
   com duplicata: hoje `processos.processo_codigo` é UNIQUE, mas `processos.cnj_normalizado`
   NÃO tem unique constraint (só índice não-único, `idx_processos_cnj_normalizado` — confirmado
   em `supabase/migrations/20260627192837_for69_schema_base_propria.sql`). Múltiplos incidentes
   legado podem resolver pra uma MESMA ação principal → precisa de upsert seguro por
   `cnj_normalizado`, não `INSERT` cego.
4. **Não achou** (a página do cumprimento JÁ É a raiz, sem link de volta) → mesma regra da
   FOR-196: a ação principal é o próprio cumprimento.

## Como validar (quando for pra build, fora desta sessão)

- Caso de teste real já confirmado manualmente: DEPRE `0436868-90.2025.8.26.0500` →
  cumprimento `0018028-13.2022.8.26.0562` → ação principal `1000594-91.2022.8.26.0562`.
- Volume: ~24.292 jobs de recrawl (mesma fila/origem `manual` da FOR-178), respeitando o cap de
  concorrência da VPS (1 vCPU) — plano de execução em lote fica pra fase de build.

## Dependências / limitações

- Depende do schema e das RPCs criadas pela FOR-178 (Done, PR #27 cortex-v1) e do hotfix de
  segurança FOR-179 (REVOKE em RPCs `merge_legado_*`).
- `worker-crawler` não arquiva HTML bruto — recrawl é obrigatório, não há atalho de
  reconciliação só-de-banco.
- Nenhum crawl real nem escrita em produção nesta fase.
