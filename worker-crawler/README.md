# worker-crawler — Crawler e-SAJ TJSP (FOR-71)

Worker externo (roda na VPS) que consome a fila `crawler_queue` (FOR-73) e popula a base própria (FOR-69) via **service_role**, classificando cada processo (FOR-72). Estágio 1 — **deslogado**, HTTP puro (e-SAJ `cpopg` é GET, sem captcha; `#tabelaTodasMovimentacoes` já vem no HTML — sem navegador headless).

## Fluxo (loop)
`claim_crawler_jobs(N)` → para cada job: **normaliza à raiz** (`a.processoPrinc`) → desce cumprimentos→incidentes → extrai capa/partes/advogados-OAB/valor/data-base/numero_depre/andamentos → **persiste** (upsert + andamentos idempotentes) → `classify_processo` → `complete_crawler_job` (ou `fail_crawler_job` com retry/backoff).

## Contrato da fila (seed)
- `crawler_queue.processo_codigo` é usado como **seed**. **Recomendado: CNJ** (número unificado `NNNNNNN-DD.AAAA.8.26.FFFF`) — o worker resolve via `search.do` (NUMPROC) e sobe à raiz.
- Se o seed for um código interno e-SAJ, o worker tenta `show.do` direto (precisa do foro; derivado do CNJ quando disponível).
- ⚠️ **Reconciliar com FOR-73:** o `refresh-stale` enfileira `processos.processo_codigo` (código interno). Avaliar enfileirar `processos.cnj` para o worker resolver de forma uniforme. (TODO)

## Rodar
```bash
cp .env.example .env   # preencher SUPABASE_URL + SERVICE_ROLE_KEY (secreta)
npm install
npm run dev            # tsx watch
# produção:
npm run build && node dist/index.js
```
Seed manual p/ teste (no SQL Editor / psql):
```sql
SELECT enqueue_crawler_job('1003169-89.2019.8.26.0073', 'manual');
```

## Deploy (VPS)
Processo gerenciado por **systemd** ou **pm2**. Env mínimo: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`. Educação com o e-SAJ via `CONCURRENCY`/`DELAY_MS` (conservador por padrão). A `SERVICE_ROLE_KEY` fica **só na VPS**.

## TODO / verificação
- **Validar seletores** de `src/parse.ts` contra páginas reais do e-SAJ (capa, `#tablePartesPrincipais`, `#tabelaTodasMovimentacoes`, `a.processoPrinc`, `a.incidente`) — a doc lista os principais, mas rótulos/ids podem variar.
- Resolver leitura do **código interno da raiz** (`selfCodigo`) — depende do hidden real da página.
- Opção A: incidente placeholder `Indefinido` (`<codigo>#placeholder`) para cumprimento/raiz sem incidente.
- Ler `concurrency/delay` de `coleta_config.params` (hoje via env).

## Referências
- Doc técnica: `../docs/business-context/crawler-tjsp-esaj/Documentacao_Crawler_TJSP_eSAJ.md`
- Schema: FOR-69 · Fila/RPCs: FOR-73 · Classificação: FOR-72
