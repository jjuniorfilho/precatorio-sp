# FASE 5 — Rollout Fase A (PJe: TRF1, TRF3, TRF5)

Runbook de comandos pra rodar na VPS de produção (`/opt/precatorio-worker`, deploy via scp — não é repo git). Rodar cada bloco na ordem, conferindo o resultado antes de ir pro próximo.

## 1. Deploy do código atual

Do seu ambiente local (dentro de `cortex-v1/`):

```bash
scp worker-crawler/src/ingest-djen-federal.ts \
    root@31.97.242.130:/opt/precatorio-worker/src/ingest-djen-federal.ts

ssh root@31.97.242.130 'cd /opt/precatorio-worker && npm run build'
```

(`ingest-djen-federal.ts` já foi copiado manualmente durante a Fase 4 — rodar de novo aqui garante que a versão final, com os fixes da Fase 3, está lá.)

## 2. Habilitar `coleta_config` pra TRF1/TRF3/TRF5

No SQL Editor (Supabase):

```sql
UPDATE coleta_config SET enabled = true
 WHERE rotina IN ('caderno_djen_trf1', 'caderno_djen_trf3', 'caderno_djen_trf5');
```

## 3. Backfill sequencial (5 dias, um tribunal de cada vez)

Na VPS (`ssh root@31.97.242.130`, dentro de `/opt/precatorio-worker`). **Sequencial, não simultâneo** — decisão do PRD, mitiga risco de rate-limit combinado nos 3 tribunais.

```bash
cd /opt/precatorio-worker

nohup node dist/ingest-djen-federal.js --tribunal=TRF1 --from=2026-09-01 --to=2026-09-05 --backfill \
  > backfill-trf1.log 2>&1 &
wait

nohup node dist/ingest-djen-federal.js --tribunal=TRF3 --from=2026-09-01 --to=2026-09-05 --backfill \
  > backfill-trf3.log 2>&1 &
wait

nohup node dist/ingest-djen-federal.js --tribunal=TRF5 --from=2026-09-01 --to=2026-09-05 --backfill \
  > backfill-trf5.log 2>&1 &
wait
```

(`wait` garante que um tribunal termina antes do próximo começar — se preferir rodar em background sem bloquear o terminal, tira o `wait` e confere os logs depois com `tail -f backfill-trf*.log`.)

## 4. Verificação pós-backfill

No SQL Editor:

```sql
-- Status por dia/tribunal
SELECT tribunal, data, status, total, flagueados, erro
  FROM djen_dias
 WHERE tribunal IN ('TRF1','TRF3','TRF5') AND data >= '2026-09-01'
 ORDER BY tribunal, data;

-- Runs com erro/erro_parcial (se houver, investigar antes de prosseguir)
SELECT rotina, started_at, status, itens_ok, itens_erro, detalhe
  FROM coleta_runs
 WHERE rotina IN ('caderno_djen_trf1','caderno_djen_trf3','caderno_djen_trf5')
 ORDER BY started_at DESC
 LIMIT 20;

-- Amostra pra revisão manual (~20-30 por tribunal) — meta: >90% de acerto
-- precatório/RPV vs leitura humana do teor (andamentos.descricao)
SELECT p.tribunal, c.cnj AS cnj_cumprimento, i.tipo_previsto, i.macrofase, i.fase,
       a.data AS data_publicacao, left(a.descricao, 300) AS teor
  FROM incidentes i
  JOIN cumprimentos c ON c.id = i.cumprimento_id
  JOIN processos p ON p.id = i.processo_id
  LEFT JOIN andamentos a ON a.incidente_id = i.id
 WHERE p.tribunal = 'TRF3'  -- trocar por TRF1/TRF5 conforme for revisando
 ORDER BY a.data DESC
 LIMIT 30;
```

## 5. Cron separado (só depois da amostra aprovada)

Wrapper sequencial na VPS (`/opt/precatorio-worker/cron-federal.sh`):

```bash
#!/bin/bash
cd /opt/precatorio-worker
YESTERDAY=$(date -d "yesterday" +%Y-%m-%d)
for TRF in TRF1 TRF3 TRF5; do
  node dist/ingest-djen-federal.js --tribunal=$TRF --date=$YESTERDAY >> cron-federal.log 2>&1
done
```

```bash
chmod +x /opt/precatorio-worker/cron-federal.sh
crontab -l  # conferir o que já existe (não sobrescrever o cron do estadual, `10 8 * * *`)
crontab -e
# adicionar (horário deslocado do estadual pra não competir por recurso na VPS 1 CPU):
# 30 9 * * * /opt/precatorio-worker/cron-federal.sh
```

## Critério de avanço pra Fase 6 (eproc: TRF2/TRF4/TRF6)

Só prosseguir depois de:
- [ ] N dias consecutivos de captura diária sem erro (definir N — sugestão: 5-7 dias corridos do cron).
- [ ] Amostra revisada manualmente com >90% de acerto por tribunal.
