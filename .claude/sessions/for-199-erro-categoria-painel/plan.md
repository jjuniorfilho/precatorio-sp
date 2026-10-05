# Plan: FOR-199

## Fase A — cortex-v1 (SQL)

1. `sql/2026-10-04_for199_rpc_erro_categoria.sql`
   - `crawler_queue_erro_categoria_counts()` (sql stable, security definer)
   - `pagamentos_consultas_resumo()` (plpgsql stable, security definer, retorna jsonb)
   - grants + `NOTIFY pgrst, 'reload schema'`
2. `sql/sandbox/for199_validate_local.sh` — schema pós-FOR-198 mínimo + casos de teste das 2
   RPCs (contagem correta, NULL vira categoria "sem categoria" na saída, janela 24h exclui
   consulta antiga, grants corretos) — rodar e confirmar "TODOS OS CENÁRIOS OK" antes de seguir.

## Fase B — frontend

1. `src/lib/api/coleta.ts`: tipos (`ErroCategoria`, `CategoriaCount`, `PagamentosResumo`),
   `ERRO_CATEGORIA_LABEL`, `getCrawlerErroCategoriaBreakdown()`, `getPagamentosConsultasResumo()`.
2. `src/routes/admin.coleta.tsx`:
   - 2 `useQuery` novos.
   - `ERRO_CATEGORIA_COLOR` local + componente `CategoriaBreakdown`.
   - Breakdown dentro do card "Fila do crawler e-SAJ" (só se `q.erro > 0`).
   - Card novo "Consultas de pagamento (TJSP)" entre Circuit breaker e Refresh de ativos.
   - +2 entradas no `GLOSSARIO`.

## Fase C — verificação adversarial (lead)

1. Rodar `for199_validate_local.sh` até passar.
2. Ler o diff inteiro dos 2 arquivos de frontend.
3. Checar testes existentes do repo frontend que tocam `admin.coleta.tsx`/`coleta.ts` (se
   houver) — rodar isolado.
4. Subir dev server da worktree do frontend (porta offset) e confirmar com Playwright real: os
   2 painéis aparecem, com dado real da RPC (ou estado vazio correto se não houver erro real em
   produção agora).

## Fase D — PR

- cortex-v1 → PR contra `main`, migration SQL NÃO aplicada (freio de mão).
- frontend → PR contra `jjuniorfilho/precatorio-sp`.
- `In Review` no Linear (FOR-199). Parar — sem merge.
