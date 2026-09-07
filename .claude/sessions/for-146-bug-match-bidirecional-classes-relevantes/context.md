# Context: FOR-146 — Bug de match bidirecional de classes_relevantes em ingest-djen.ts

> Sessão rodada em modo frota (fleet-orchestration), Fase 1 (warm-up + start), sem
> humano disponível para interview síncrona. As 5 clarificações abaixo foram
> autorrespondidas a partir do texto da issue Linear FOR-146 e de investigação de
> código/dados real; qualquer divergência deve ser corrigida no gate humano da Fase 1.

## ⚠️ Regras Críticas do Projeto (Project Briefing)

(copiado de `docs/technical-context/briefing/critical-rules.md` — nota: este briefing
é de 2026-05-31 e descreve a fase inicial do MVP de captura/lead; a regra relevante
para esta issue é a de **busca tolerante a formato / normalização de input**, cujo
princípio (normalizar antes de comparar) é exatamente o que `norm()` já faz em
`ingest-djen.ts` — o bug não está na normalização, está na direção do `.includes()`.)

- Multi-tenancy/segurança: não se aplica diretamente (ingestão server-side, sem dado de lead).
- Performance: a rotina roda 1x/dia (cron) + backfill manual; não há SLA de latência por item.
- Convenção de nomenclatura snake_case nas tabelas: `coleta_config`, `djen_dias`, `djen_depre`,
  `eproc_pendentes`, `crawler_queue` (via RPC `enqueue_crawler_job`) — todas já existentes,
  nenhuma tabela nova é necessária para este fix.

## 1. Motivação (contexto)

`worker-crawler/src/ingest-djen.ts` roda diariamente na VPS (cron) e também em modo
backfill, filtrando o caderno do DJEN/Comunica do TJSP para achar processos relevantes
(classe processual batendo com `coleta_config.params.classes_relevantes` **e** parte
passiva sendo um ente público — `passivoPublico`). O que passa nos dois filtros é
enfileirado no crawler e-SAJ (ou parqueado em `djen_depre`/`eproc_pendentes` conforme o
caso).

O filtro de classe (`classeOk`) foi escrito com match **bidirecional**:

```js
const classeOk = classes.length === 0 || classes.some((c) =>
  norm(it.nomeClasse ?? "").includes(c) || c.includes(norm(it.nomeClasse ?? ""))
);
```

A intenção original provavelmente era tolerar tanto "nomeClasse mais específico que a
config" quanto "nomeClasse mais genérico que a config" — mas a segunda direção
(`c.includes(alvo)`) é estruturalmente perigosa: qualquer `nomeClasse` que seja
**prefixo/substring** de uma classe configurada mais longa passa, mesmo sem nenhuma
relação semântica com "Fazenda Pública".

## 2. Meta (resultado esperado)

Eliminar a direção `c.includes(alvo)`, mantendo só `alvo.includes(c)` — i.e., o
`nomeClasse` observado no DJEN precisa **conter** (como substring, após normalização) a
classe configurada, nunca o contrário. Isso é exatamente o fix já aplicado em
`classificaPorNomeClasse` no worker federal (`ingest-djen-federal.ts`, ainda não
mergeado/não disponível nesta worktree — ver Limitações).

O fix em si é trivial (uma linha). **O trabalho real desta fase é a investigação**:
medir, contra dados reais, se a mudança de direção altera volume de enfileiramento em
produção (a issue pede isso explicitamente, por ser rotina já em produção).

## 3. Estratégia (direcional)

1. Reproduzir a lógica exata de `ingestDay()` (fetch por `nomeParte` do
   `PARTES_ALVO_DEFAULT`, filtro `classeOk` bidirecional vs. unidirecional,
   `passivoPublico`) contra dias reais do TJSP via Comunica API pública.
2. Comparar quantos CNJ que seriam enfileirados hoje (bidirecional) deixariam de ser
   enfileirados com o fix (unidirecional) — isolando o efeito puro da mudança de
   direção do match de classe (sem misturar com outras variáveis).
3. Com o resultado quantificado, decidir se o fix é "só engenharia" (comportamento
   claramente incorreto, remove ruído) ou se tem componente de produto (o volume
   removido pode incluir processos que a operação **quer** capturar, só que com
   `nomeClasse` genérico).
4. Aplicar o fix em `ingest-djen.ts` (troca de uma linha) — feito na Fase 3
   (`/engineer:work`), não nesta fase.
5. Adicionar teste unitário cobrindo o caso exato do bug (nomeClasse curto que é
   prefixo de uma classe configurada mais longa) para não regredir.

## 4. Novas APIs/ferramentas?

Nenhuma API nova. A investigação usa a mesma API pública já usada pelo worker
(`https://comunicaapi.pje.jus.br/api/v1/comunicacao`), sem autenticação, já documentada
no cabeçalho do próprio `ingest-djen.ts`.

## 5. Investigação real rodada nesta fase (achado principal)

Rodei um script standalone (fora do repo, em scratchpad — não é artefato do projeto)
que replica byte-a-byte a lógica de `fetchPage` + `classeOk` + `passivoPublico` de
`ingest-djen.ts` (peguei o conteúdo atual do arquivo via
`git show jjuniorfilho/for-145-captura-precatorios-federais-djen:worker-crawler/src/ingest-djen.ts`,
já que o arquivo não existe em `origin/main` — ver Limitações) contra 4 dias reais:
**2026-09-01, 02, 03 e 04**.

`classes_relevantes` usado (seed de
`supabase/migrations/20260627205511_for70_ingest_djen.sql`, não encontrei migration
posterior que altere esse valor):

```
Cumprimento de Sentença contra a Fazenda Pública
Cumprimento Provisório de Sentença contra a Fazenda Pública
Execução contra a Fazenda Pública
Precatório
Requisição de Pequeno Valor
Procedimento do Juizado Especial da Fazenda Pública
```

**Resultado agregado (4 dias, ~50k itens brutos processados):**

| Métrica | Valor |
|---|---|
| Total de CNJ que passariam por `classeOk` (bidirecional, comportamento atual) **e** `passivoPublico` | 14.123 |
| Desses, quantos também passariam com o fix (`alvo.includes(c)` só) | 12.599 (~89,2%) |
| Desses, quantos são falso-positivo puro do bug (só passam hoje, por causa de `c.includes(alvo)`) | **1.524 (~10,8%)** |

**100% dos 1.524 falso-positivos** vêm de exatamente 2 padrões de `nomeClasse`:
- `"CUMPRIMENTO DE SENTENÇA"` (genérico, sem sufixo) → bate hoje contra a config
  `"Cumprimento de Sentença contra a Fazenda Pública"` só porque a config (longa) contém
  o `nomeClasse` (curto) como substring.
- `"CUMPRIMENTO PROVISÓRIO DE SENTENÇA"` (genérico) → mesma dinâmica contra
  `"Cumprimento Provisório de Sentença contra a Fazenda Pública"`.

Isso bate exatamente com o exemplo da issue. Nenhum falso-positivo veio de
"Execução"/"Precatório"/"RPV"/"Juizado" — só das duas classes de "Cumprimento".

**Achado que muda o cálculo de risco**: todos esses 1.524 casos JÁ passaram no filtro
`passivoPublico` — ou seja, são processos reais em fase de cumprimento de sentença
**contra um ente público de fato** (Fazenda/Município/Autarquia etc. no polo passivo),
só que o TJSP não rotulou a classe processual com o sufixo "contra a Fazenda Pública"
(ela não é uma classe processual CNJ padronizada — é um rótulo textual da própria
config). Ou seja: **o fix não é 100% "remove lixo"** — ele também remove ~10,8% do
volume atual que hoje chega ao funil e que, de fato, é execução/cumprimento de sentença
contra ente público, apenas classificado de forma genérica pelo TJSP.

Isso é exatamente o tipo de decisão que a issue pede para investigar antes de mexer:
tecnicamente o match bidirecional é um bug (permite prefixo em qualquer direção, sem
relação semântica), mas o efeito prático em produção não é "ruído puro" — é uma redução
real de ~11% no volume diário de CNJ capturados, e esse volume tem `passivoPublico=true`.
**Recomendação**: aplicar o fix (a direção `c.includes(alvo)` é logicamente errada e
insustentável — no limite, deixaria passar qualquer `nomeClasse` de uma letra só, ou
"Precatório" batendo em qualquer classe que contenha a palavra "Precatório" como parte
de nome maior), mas o gate humano da Fase 1 deve estar ciente do trade-off de volume e,
se quiser manter esses ~11% no funil, isso deve virar decisão explícita de produto:
adicionar `"Cumprimento de Sentença"` e `"Cumprimento Provisório de Sentença"` (sem
sufixo) como entradas próprias em `classes_relevantes`, não reintroduzir o match
bidirecional.

## 6. Como validar

- Teste unitário isolando `classeOk` (extrair a função de match para ser testável sem
  depender de `ingestDay()` inteiro) com casos: (a) nomeClasse == config exato; (b)
  nomeClasse mais específico que config (deve passar); (c) nomeClasse genérico que é
  prefixo de uma config mais longa (NÃO deve passar após o fix — hoje passa,
  incorretamente); (d) nomeClasse sem nenhuma relação (não deve passar).
- Rodar novamente o script de amostra real (ou um `--dry-run` equivalente dentro do
  próprio `ingest-djen.ts`, se vier a existir) contra um dia após o fix e conferir que
  a queda de volume bate com o previsto (~11%) e que não há surpresa adicional.

## 7. Dependências

- `coleta_config.params.classes_relevantes` (tabela em produção) — o fix não muda o
  schema nem o conteúdo dessa config, só a lógica de comparação em código.
- Nenhuma dependência de outra issue para o fix em si.

## 8. Limitações

- **`worker-crawler/` não existe em `origin/main`** (branch-base desta worktree). Ele só
  existe em branches de feature não mergeadas (toda a linhagem do épico FOR-68 em
  diante: `jjuniorfilho/consolida-for68-backend` → ... → `for-145-...`). Esta worktree
  foi provisionada a partir de `origin/main`, então **o arquivo a ser corrigido não
  existe fisicamente nela hoje**. Isso é tratado com detalhe em `architecture.md`
  (seção de risco) — é a decisão mais importante a validar no gate humano antes da
  Fase 2/3 (plan/work), porque sem resolver isso não há onde aplicar o fix dentro desta
  worktree.
- `ingest-djen-federal.ts` (referência de fix já aplicado, citada na issue) existe só
  como arquivo não commitado no checkout principal (outra branch, fora desta worktree).
  Por instrução explícita da issue e do orquestrador, **não foi lido** (evitar tocar o
  checkout principal) — o fix aqui foi desenhado só a partir da descrição da issue.
- A investigação rodou fora do repo (script standalone em `/private/tmp/.../scratchpad`,
  não versionado) porque o worktree não tem `worker-crawler/node_modules` nem
  credenciais de Supabase; usou a API pública da Comunica diretamente com a mesma
  lógica de filtro, o que é suficiente para isolar o efeito do bug de match de classe
  (não depende de acesso a banco).
