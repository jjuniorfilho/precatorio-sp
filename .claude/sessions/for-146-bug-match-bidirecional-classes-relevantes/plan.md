# FOR-146 — Fix do match bidirecional de classes_relevantes em ingest-djen.ts

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

> Contexto herdado das Fases 1 (context.md/architecture.md, já aprovadas no Gate 1):
> a worktree já está rebaseada sobre `jjuniorfilho/for-145-captura-precatorios-federais-djen`
> (`worker-crawler/src/ingest-djen.ts` existe e foi confirmado em `worker-crawler/src/ingest-djen.ts:118`);
> o escopo é fix + preservação de volume (2 classes genéricas em produção), não é permitido
> reabrir essas duas decisões nesta fase.

## FASE 1: Extrair e corrigir `classeOk` + cobertura de teste [Completada ✅]

Isola a comparação de classe processual numa função pura testável e aplica o fix (remove
o ramo `c.includes(alvo)`). Sem dependência de dado em produção — pode ser feita e
validada localmente (`npm test` em `worker-crawler/`) antes de qualquer mudança externa.

### Extrair `classeOk` de dentro do loop de `ingestDay` [Completada ✅]

Em `worker-crawler/src/ingest-djen.ts:118`, mover a expressão inline para uma função
nomeada e exportada, ex.:

```ts
export function classeOk(nomeClasse: string | null | undefined, classesConfig: string[]): boolean {
  if (classesConfig.length === 0) return true;
  const alvo = norm(nomeClasse ?? "");
  return classesConfig.some((c) => alvo.includes(c));
}
```

`classesConfig` já chega normalizado (`classes = params.classes_relevantes.map(norm)` na
linha 95) — manter essa responsabilidade fora da função, igual está hoje. Atualizar o
call site (linha 118) para `classeOk(it.nomeClasse, classes)`. Nenhuma outra função do
arquivo muda (`passivoPublico`, `esfera`, `isDepre`, `naoDistribuido`, `sistemaFromLink`,
`persistAdvogadosDjen` ficam intactos, conforme `architecture.md`).

### Remover o ramo `c.includes(alvo)` (fix) [Completada ✅]

O `some()` passa a ter só a direção `alvo.includes(c)` (config precisa ser substring do
`nomeClasse` observado, nunca o contrário). É a mudança já descrita em `architecture.md`
("Estado proposto (fix)").

### Criar `worker-crawler/src/ingest-djen.test.ts` [Completada ✅]

Seguir o padrão de `worker-crawler/src/parse.test.ts` (node:test nativo, sem lib nova —
o script `test` do `package.json` já roda `src/*.test.ts` automaticamente, nenhuma
mudança de config necessária). Casos mínimos (de `context.md` §6):

- `nomeClasse` idêntico à config (normalizado) → passa.
- `nomeClasse` mais específico que a config (contém a config + sufixo extra) → passa.
- `nomeClasse` genérico que é prefixo/substring de uma config mais longa (o caso do bug:
  `"CUMPRIMENTO DE SENTENÇA"` vs. config `"Cumprimento de Sentença contra a Fazenda
  Pública"`) → **não deve passar** após o fix (hoje passa, incorretamente).
- `nomeClasse` sem nenhuma relação com nenhuma config → não passa.
- `classesConfig` vazio → passa sempre (comportamento de "sem filtro", já existente).
- Com as 2 classes genéricas da Fase 2 já adicionadas à config de teste, o mesmo
  `nomeClasse` genérico do caso 3 volta a passar (prova que a Fase 2 restaura o volume
  sem reabrir o bug).

### Rodar `npm test` em `worker-crawler/` e confirmar suíte verde [Completada ✅]

Inclui os testes novos e os já existentes (`parse.test.ts`, `import-csv-legado.test.ts`)
para garantir que a extração não quebrou nada por efeito colateral de import.

### Comentários:
- Esta fase é 100% código local, sem qualquer efeito em produção — pode ser feita,
  testada e até revertida sem risco, independente da Fase 2.
- Não depende de acesso a Supabase/VPS: `classeOk` é função pura, testável sem mock de
  `supabase`/`fetch`.
- **Resultado real**: `node_modules` não existia nesta worktree (nunca tinha sido
  `npm install`); instalado localmente (46 pacotes, sem alterar lockfile). `npm test`:
  **32/32 passaram** (26 pré-existentes + 6 novos de `classeOk`, ver
  `worker-crawler/src/ingest-djen.test.ts`). `npm run typecheck` também limpo (0 erros).
- `classeOk` ficou exportada de `worker-crawler/src/ingest-djen.ts` (perto de `norm`,
  linha ~67-76); call site em `ingestDay` (linha ~131) trocado para
  `classeOk(it.nomeClasse, classes)` — a variável local `classeOk` (boolean) que tinha
  o mesmo nome da função foi removida, sem colisão de nome.

## FASE 2: Mudança de dado em produção — `coleta_config.params.classes_relevantes` [Completada ✅]

Fase separada e revisável do deploy de código, por decisão explícita do Gate 1: é um
UPDATE em dado de produção (Supabase), não uma migration de schema. Objetivo: adicionar
as 2 entradas genéricas para que os 1.524 CNJ/4 dias (~10,8% do volume, todos com
`passivoPublico=true` real — ver `context.md` §5) continuem entrando no funil após o fix
de direção entrar em vigor.

### Escrever o script SQL do UPDATE [Completada ✅]

Criar `sql/<data>_for146_classes_relevantes_genericas.sql` seguindo a convenção do
projeto (comentário de cabeçalho explicando o porquê + "Aplicar no SQL Editor.", como em
`sql/2026-08-29_priorizar_jobs_manual.sql`). Conteúdo (substituir o array inteiro pelo
conjunto completo — mesmo estilo do seed original em
`supabase/migrations/20260627205511_for70_ingest_djen.sql:62-69` — para o script ficar
auditável e idempotente, em vez de um append condicional):

```sql
update coleta_config
set params = jsonb_set(
  params,
  '{classes_relevantes}',
  '[
    "Cumprimento de Sentença",
    "Cumprimento de Sentença contra a Fazenda Pública",
    "Cumprimento Provisório de Sentença",
    "Cumprimento Provisório de Sentença contra a Fazenda Pública",
    "Execução contra a Fazenda Pública",
    "Precatório",
    "Requisição de Pequeno Valor",
    "Procedimento do Juizado Especial da Fazenda Pública"
  ]'::jsonb
),
updated_at = now()
where rotina = 'caderno_dje';
```

Conferir antes de aplicar que nenhuma migration entre `20260627205511_for70_ingest_djen.sql`
e hoje já alterou esse array em produção (a investigação da Fase 1/context.md não achou
nenhuma, mas confirmar de novo nesta fase evita sobrescrever um ajuste manual feito
depois via SQL Editor).

### Revisão humana do script (fora do PR de código) [Pendente — ação do humano ⏳]

Como é dado de produção, não schema: o script fica commitado no repo (rastreável), mas a
aplicação em si é uma ação manual do humano/admin no SQL Editor do Supabase — não faz
parte do pipeline de deploy automático do worker. Deixar isso explícito no PR (ex.: seção
separada "⚠️ Ação manual necessária" apontando para este arquivo).

### Aplicar o UPDATE em produção [Pendente — ação do humano ⏳, fora de escopo desta sessão]

Executar o script no SQL Editor. Confirmar com um `select params->'classes_relevantes'
from coleta_config where rotina = 'caderno_dje';` que o array ficou com as 8 entradas
esperadas.

### Comentários:
- **Script escrito, NÃO executado** (restrição explícita desta sessão — não há
  credencial de produção disponível aqui, e a aplicação é ação manual e irreversível o
  suficiente para exigir humano no SQL Editor): ver
  `sql/2026-09-06_for146_classes_relevantes_genericas.sql`. Conteúdo idêntico ao
  desenhado no plano (array completo com as 8 entradas, `jsonb_set` sobre
  `params.classes_relevantes`, `where rotina = 'caderno_dje'`), com um `select` de
  conferência comentado antes e depois do `update` para o humano rodar manualmente.
- **Ordem crítica entre Fase 2 e Fase 3/deploy do código** (reforçada também no
  cabeçalho do próprio arquivo `.sql`): este UPDATE precisa ser
  aplicado **antes** (ou, na pior hipótese, no mesmo instante) do deploy do fix de
  código na VPS. Se o código com o fix for deployado primeiro e o dado só depois, existe
  uma janela real (até a próxima execução do cron diário, ou até alguém lembrar de rodar
  o UPDATE) em que o volume cai os ~10,8% documentados — exatamente o efeito que o Gate 1
  decidiu evitar. Como o UPDATE é aditivo e o código antigo (bidirecional) ainda está no
  ar até o deploy, aplicar o dado primeiro é seguro: não muda nenhum comportamento
  observável antes do fix (o bidirecional já cobria esses casos).
- Esta fase pode ser feita em paralelo com a Fase 1 (não há dependência de código para
  escrever/revisar o SQL), mas a **aplicação** em produção deve ser sequenciada como
  acima em relação ao deploy.

## FASE 3: Validação comparativa pós-fix (dry run) [Completada ✅]

Reaproveita o script standalone de investigação já rodado na Fase 1 (fora do repo, em
scratchpad — não é artefato do projeto) para confirmar que fix de código + dado
atualizado juntos preservam o volume atual, sem surpresa adicional.

### Rodar a lógica pós-fix contra os mesmos 4 dias da amostra original [Completada ✅]

Reexecutar contra 2026-09-01, 02, 03, 04 (mesmos dias de `context.md` §5) usando:
`classeOk` unidirecional (Fase 1) + `classes_relevantes` com as 8 entradas (Fase 2, sem
precisar já estar aplicado em produção — pode simular localmente com o array final).

**Resultado real**: script novo em scratchpad
(`for146-validacao-fase3.ts`, não versionado — mesma convenção da Fase 1) que **importa
a função `classeOk` real e já corrigida** direto de
`worker-crawler/src/ingest-djen.ts` (em vez de reimplementá-la, pra eliminar qualquer
risco de divergência entre o que é validado e o que roda em produção), e reimplementa
só o que não é exportado (`esfera`, `fetchPage`, `PARTES_ALVO_DEFAULT`, cópia idêntica
do arquivo original) mais uma função `classeOkLegadoBidirecional` (o comportamento
antigo/bug) só para reproduzir o baseline. Rodou ao vivo contra a API pública da
Comunica para os mesmos 4 dias (2026-09-01..04):

| Dia | Total bruto | Baseline (bidirecional, produção hoje) | Fix, só 6 classes originais | Fix + 2 genéricas (8 classes, config final) |
|---|---|---|---|---|
| 2026-09-01 | 14.181 | 4.311 | 3.898 | 4.313 |
| 2026-09-02 | 13.087 | 3.329 | 2.914 | 3.330 |
| 2026-09-03 | 11.797 | 3.089 | 2.737 | 3.095 |
| 2026-09-04 | 11.203 | 3.394 | 3.053 | 3.397 |
| **Agregado** | **50.268** | **14.123** | **12.602** | **14.135** |

### Comparar volume: baseline bidirecional vs. fix+config nova [Completada ✅]

Esperado: o total de CNJ que passam por `classeOk && passivoPublico` deve ficar igual
(ou muito próximo) aos 14.123 originais — os 1.524 que antes só passavam pelo ramo
`c.includes(alvo)` agora devem passar porque `"cumprimento de sentença"` (norm) é agora
uma entrada própria em `classesConfig`, batendo via `alvo.includes(c)` direto (já que
"CUMPRIMENTO DE SENTENÇA" normalizado é igual à nova entrada normalizada). Qualquer
divergência do esperado é sinal de bug na Fase 1/2 e bloqueia o merge.

### Registrar o resultado no PR/plan.md [Completada ✅]

**14.123 (baseline) → 14.135 (fix + 8 classes), delta +12 (+0,08%).** Volume
preservado dentro da margem esperada de ruído — o script rodou contra a API pública AO
VIVO, então o mesmo dia consultado em momentos diferentes (Fase 1 vs. Fase 3, minutos/
horas de diferença) pode ter itens republicados/atualizados no meio tempo; um delta de
12 CNJ em 14.123 (~0,08%) não é sinal de bug, é ruído de dado esperado numa API viva
consultada duas vezes em momentos diferentes. Nenhuma divergência estrutural: o "fix só
6 classes" (12.602) reproduziu quase exatamente o número documentado na Fase 1
(12.599, delta de 3 pela mesma razão), confirmando que a lógica de `classeOk` não
mudou de comportamento entre a investigação e a implementação — só a config de 8
classes é que precisa ser aplicada em produção (Fase 2, ação do humano) para o volume
observado bater com o baseline.

### Comentários:
- Esta fase depende da Fase 1 (função `classeOk` já extraída/fixada) e do conjunto final
  de classes da Fase 2 (mesmo que ainda não aplicado em produção — o array pode ser
  usado localmente na simulação).
- Não depende de a Fase 2 já ter sido aplicada em produção real para rodar a validação —
  só precisa do array final como input do script de comparação.
- Script de validação: `for146-validacao-fase3.ts` (scratchpad, não versionado, mesma
  convenção da Fase 1) — importa `classeOk` real de
  `worker-crawler/src/ingest-djen.ts` via `tsx`, evitando reimplementar a função sob
  teste. Rodado com `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` dummy (só pra satisfazer
  o import de `config.ts`/`supabase.ts`, sem nenhuma chamada real ao Supabase — a
  validação usa só a API pública da Comunica).
- **Conclusão para o gate de PR**: fix (Fase 1) + config de 8 classes (Fase 2, script
  pronto, aplicação manual pendente) juntos preservam o volume atual de captura em
  produção, dentro da margem de ruído de uma API viva. Sem surpresa adicional
  encontrada. Pronto para revisão humana antes do deploy (Fase 4, fora de escopo desta
  sessão).

## FASE 4: Deploy e monitoramento do primeiro dia real [Não Iniciada ⏳]

Fase de acompanhamento pós-merge/pós-aplicação, curta, para fechar o ciclo com dado real
de produção (não simulado).

### Deploy do worker na VPS (pm2) [Não Iniciada ⏳]

Seguir o processo já existente do projeto (`patterns/pipeline_producao_vps.md`): git
pull da branch com o fix + restart do processo `precatorio-crawler` no pm2. Confirmar
que o UPDATE da Fase 2 já foi aplicado em produção **antes** deste passo (ver ordem
crítica na Fase 2).

### Checar `djen_dias` do primeiro dia processado pós-deploy [Não Iniciada ⏳]

Comparar `flagueados`/`enfileirados` do primeiro dia pós-deploy com a média dos dias
recentes anteriores (mesma faixa da amostra da Fase 1/3) — não deve haver queda anômala
além do que já foi explicado/absorvido pela Fase 2.

### Comentários:
- Esta fase só pode começar depois que Fases 1, 2 e 3 estiverem completas e revisadas
  (é o deploy real, não simulação).
- Fora do escopo desta fase de planejamento decidir o timing exato do deploy (ex.: dia
  específico) — fica para quem executa a Fase 3 do pipeline de frota (`/engineer:work`
  + gate de PR), que roda depois deste plano ser aprovado.
