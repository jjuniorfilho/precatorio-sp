# Context: FOR-202 — cessao_credito sem estado "não verificado"

## Contexto / motivação

`incidentes.cessao_credito` é `boolean NOT NULL DEFAULT false` (FOR-143). Diferente da
coluna irmã `djen_depre.acordo_homologado` (`boolean` nullable — `null` = não verificado,
FOR-159/160, já provado em produção há semanas, com filtro de 3 estados no admin), não
existe como distinguir "verificado, sem cessão" de "nunca verificado, ficou no default
false" olhando só a coluna `cessao_credito`.

Surgiu durante o acompanhamento do FOR-201 (crawler passou a persistir andamentos de
cumprimento/processo raiz, não só de incidente) e de uma onda de verificação em massa que
o usuário disparou em paralelo (fora desta sessão) pra confirmar cessão de crédito nos
incidentes com `numero_depre`. O usuário vai repetir esse padrão de "onda de verificação"
pro `acordo_homologado` em seguida — faz sentido fechar essa lacuna agora, não ficar
reescrevendo query de proxy toda vez que alguém perguntar "isso foi verificado?".

## Causa raiz (já confirmada no código)

Em `classify_processo`/`classify_incidentes` (plpgsql, roda automaticamente a cada crawl
via `worker-crawler/src/index.ts:155`), o CTE `match` faz:

```sql
bool_or(r.flag = 'cessao_credito') AS f_cessao
```

via `LEFT JOIN todos_andamentos ta ... LEFT JOIN classificacao_regras r ON ...`. Quando um
incidente não tem NENHUM andamento nas 3 fontes (tabela `andamentos`, jsonb
`cumprimentos.andamentos`, jsonb `processos.andamentos` — as 2 últimas adicionadas no
FOR-201), `f_cessao` já sai `NULL` naturalmente desse `bool_or`/LEFT JOIN. O bug está no
UPDATE final:

```sql
cessao_credito = COALESCE(m.f_cessao, false)
```

Esse `COALESCE` converte o `NULL` genuíno (nunca verificado) em `false` — apagando a
diferença entre "verificado, negativo" e "nunca verificado".

## Impacto medido em produção (2026-10-21)

Via amostra estatística (`TABLESAMPLE SYSTEM(5)` — contagem exata com 3 subqueries
correlacionadas competia I/O com o crawler em produção e não terminava em tempo
razoável): de **871.127** incidentes com `cessao_credito = false` hoje (de 887.092
totais), **~23% (≈200.800) nunca foram verificados de verdade** — zero andamentos em
qualquer uma das 3 fontes.

## Achado adicional confirmado (bug separado, mesma área)

`_where_processo_incidente` em produção (capturada ao vivo via `pg_get_functiondef`, não
pelo arquivo `.sql` mais recente do repo — já tinha divergido antes, ver nota do FOR-201
sobre o `ano_oc`/`calcular_oc`) tem o parâmetro `p_cessao_credito boolean default null` na
assinatura, mas **o corpo da função não tem nenhum bloco que o utilize**. O filtro
"Cessão de crédito: Sim/Não" na tela `/admin/processo-incidente` hoje é um no-op — Sim e
Não devolvem o mesmo conjunto. Provavelmente um `CREATE OR REPLACE` posterior (talvez o do
FOR-189, que tocou a mesma função) partiu de uma versão anterior ao FOR-160 e perdeu esse
trecho. Vai ser corrigido como parte natural desta issue (reescrevendo o filtro do zero,
já como enum).

## Decisão de produto (usuário, 2026-10-21)

Tornar `cessao_credito` nullable, com `NULL` = não verificado — mesmo padrão exato de
`acordo_homologado`. Confirmado explicitamente: **não** usar coluna de timestamp separada
(`verificado_em`) nem enum de texto pra esse campo — boolean nullable é suficiente e
minimiza drift com os outros 7 flags da mesma função, que continuam boolean.

**Fora de escopo, por decisão explícita do dono do produto**: os outros 6 flags booleanos
da mesma função (`calculo_homologado`, `incidente_instaurado`, `termo_declaracao`,
`oficio_deferido`, `oficio_expedido`, `ordem_cronologica`, `possivelmente_pago`) têm a
MESMA ambiguidade (mesmo `COALESCE(..., false)`), e ela se propaga pra `fase`/`macrofase`/
`elegivel` (calculados a partir desses flags). Não mexer agora — registrar como issue de
acompanhamento (ver seção "Fora de escopo" em architecture.md).

## Revisão de especialista (subagent `database-architect`, independente, 2026-10-21)

Já rodada antes desta sessão de fleet, revisando: o código real de `classify_processo`/
`classify_incidentes`, as 3 RPCs, a captura ao vivo de produção, e o frontend. Veredito:
abordagem (nullable + `CASE WHEN tem_andamento`) correta e mais simples que as
alternativas. Ajustes incorporados ao plano (ver architecture.md):
- `SET lock_timeout`/`statement_timeout` antes do `ALTER COLUMN`, com retry.
- Backfill por cursor de `id` (não `OFFSET`), em lotes, recalculando "sem andamento" **ao
  vivo** dentro de cada `UPDATE` (não contra a lista pré-materializada da amostra — evita
  sobrescrever com `NULL` um incidente que o crawler acabou de classificar de verdade).
- Minimizar o intervalo entre o backfill terminar e o deploy do frontend tri-state (janela
  de UI enganosa: "Não" pra linhas que na verdade virariam "não verificado").
- Confirmado: `tem_andamento = bool_or(ta.incidente_id IS NOT NULL)` é matematicamente
  correto nos edge cases (array jsonb vazio `[]` vs `NULL`, descrição vazia).
- Sem RLS, view materializada ou CHECK constraint dependendo de `cessao_credito` ser
  `NOT NULL` — nada mais quebra por tirar o `NOT NULL`.

## Escopo confirmado desta issue

1. Schema: `incidentes.cessao_credito` — `DROP NOT NULL`, `DROP DEFAULT`.
2. Fix em `classify_processo`/`classify_incidentes`: só o cálculo de `cessao_credito`
   passa a usar `tem_andamento`; os outros 7 flags ficam intocados.
3. Backfill de correção dos ~200.800 (`false` → `NULL`), em lotes, cursor por `id`,
   recálculo ao vivo.
4. Reescrita de `_where_processo_incidente`/`buscar_processos_incidente`/
   `contar_processos_incidente`: `p_cessao_credito` vira `text`
   (`'sim'|'nao'|'nao_verificado'`) — e ganha de fato um corpo de filtro (hoje não tem
   nenhum).
5. Frontend (`precatorio-sp`, `/admin/processo-incidente`): filtro de 3 estados + badge
   tri-state, mesmo padrão já usado pro `acordo_homologado` nos mesmos arquivos.

## Validação planejada

Postgres local efêmero (Homebrew `postgresql@15`, padrão já estabelecido no projeto —
ver `sql/sandbox/for201_validate_local.sh` como molde) antes de aplicar em produção.
