# FOR-178 — reconciliação LEGADO no nível do cumprimento

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

## FASE 1 — RPC SQL [Completada ✅]

### Migration `sql/2026-09-29_for178_merge_legado_processo_para_cumprimento.sql` [Completada ✅]

RPC conforme architecture.md (guardas, reparent de incidentes/partes/cumprimentos, delete legado,
REVOKE PUBLIC/anon + GRANT service_role/authenticated).

### Sandbox `sql/sandbox/for178_validate_local.sh` [Completada ✅]

Postgres 15 descartável com schema FOR-69 mínimo + RPCs FOR-143 + RPC nova. Reproduz o caso
DEPRE 0088499-12.2023.8.26.0500 (estado pré-crawl e estado pós-crawl-paralelo), simula em SQL a
sequência que o worker executa e confere: 1 linha incidentes pro numero_depre com cumprimento_id;
linha legado apagada; guardas; idempotência; grants.

## FASE 2 — Worker [Completada ✅]

### `reconcileLegadoCumprimento` + chamada no `persistTree` [Completada ✅]

Após upsert de cada cumprimento; se houve merge, recarrega o Map de incidentes legado.

### Teste `src/supabase-persist-tree-legado.test.ts` [Completada ✅]

Fake in-memory de `supabase.from`/`supabase.rpc` (RPCs simuladas em JS). Cenários: 1º crawl;
idempotência (2º crawl); hierarquia paralela pré-existente; cumprimento == raiz; gate
LEGADO_RECONCILE=false; erro da RPC propaga.

### Comentários:
- Sandbox: todos os cenários A–E OK (cenário B reproduz a duplicata de produção; merge deixa 1
  linha, sobrevivendo a REAL).
- Teste worker 6/6; suíte completa 140/140; typecheck limpo.
- Mutation check: desligar a chamada `reconcileLegadoCumprimento` quebra 4 testes; remover só a
  recarga do Map quebra 3 — a ordem (merge de cumprimento → recarga → loop de incidentes) está coberta.
- Guardas extras na RPC (legado precisa ser LEGADO-, cumprimento precisa pertencer ao processo real,
  cumprimentos da legado reapontados antes do delete por causa do ON DELETE CASCADE).
- Achado fora de escopo: os GRANTs dos RPCs FOR-143 (`merge_legado_processo`/`merge_legado_incidente`)
  não revogam PUBLIC → `anon` provavelmente tem EXECUTE neles em produção. Reportado, não corrigido.

## FASE 3 — pre-pr / PR [Completada ✅]

Review, PR para `main`, card FOR-178 → In Review.

### Comentários:
- code-reviewer: sem bloqueantes; 2 "should address" corrigidos (dois passes no persistTree;
  consumo do Map + rename-1-merge-resto no reconcileLegadoRows). Ver architecture.md "Revisão pós
  code review".
- test-planner-branch: 5 lacunas → 5 testes TS novos (11/11) + cenário F no sandbox. Os 4 testes
  novos que cobrem os achados falham contra o 1º commit (a1a183a) e passam agora.
- Suíte 145/145, typecheck limpo, sandbox 42 checks OK.
- Pendente de decisão humana (fora do escopo): hotfix de grants dos RPCs FOR-143 (PUBLIC/anon).
