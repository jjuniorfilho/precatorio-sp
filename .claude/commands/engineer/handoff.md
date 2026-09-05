
# Engineer Handoff

Escreve o handoff que atravessa a fronteira entre sessoes: o que esta pendente, o que exige
humano, e o que voce verificou de verdade.

<arguments>
#$ARGUMENTS
</arguments>

Argumentos opcionais: um tema/foco em texto livre (ex.: `precatorio`), usado so para nomear o
arquivo e orientar a enfase. Sem argumento, o proprio estado medido define o assunto.

## Por que este comando existe

Handoff escrito de memoria vira resumo da conversa — e **a conversa nao sabe o estado do
mundo**. Ela nao ve a worktree com trabalho represado que uma sessao de dias atras deixou, nem
o gap entre o que esta em producao e o que esta na `main`.

Medido num repo real em 2026-07-31: a sessao ia registrar "producao atualizada" de memoria.
Media: **5 commits** de gap, e commits vivos numa worktree que nunca viraram PR — um deles
resolvendo uma pergunta que a documentacao ainda registrava como ABERTA. Nada disso apareceu
na conversa.

O que separa handoff util de resumo e **medir antes de escrever**.

## As tres entregas

Um handoff so existe quando as tres acontecem. A segunda e a que sempre escapa:

1. o arquivo em `docs/handoffs/AAAA-MM-DD-<slug>.md`
2. o **ponteiro** para ele no bloco `HANDOFF` do `MEMORY.md` — sem ele o `/engineer:warm-up`
   nao acha o arquivo, e um handoff que ninguem le nao e um handoff
3. o ciclo git — commit numa branch propria e **PR** (nunca push direto na `main`)

Voce nao precisa lembrar das tres: o `handoff-commit.sh` executa a 2 e a 3, e falha com
`exit 2` se qualquer uma nao completar.

---

## Passo 1 — MEDIR (antes de escrever qualquer linha)

```bash
bash .claude/scripts/handoff-measure.sh
```

**Leia a saida inteira antes de redigir.** O script e somente-leitura e cobre seis frentes: gap
entre producao e a `main`, PRs abertos, worktrees com trabalho represado, commits nao pushados,
paths de fronteira tocados, coerencia do ponteiro atual e handoffs represados em PR aberto.

Cada secao sai como `MEDIDO` ou `NAO MEDIDO <motivo>`. **Essa distincao e o insumo mais
importante do comando** — ver Passo 3.

Se algo no relatorio contradisser o que voce lembra da sessao, **o relatorio ganha**. Ele mede;
voce lembra.

## Passo 2 — JULGAR (a parte que o script nao faz)

Aqui entra o que so voce pode fazer. Um `git log` conta o que aconteceu melhor do que qualquer
resumo — o valor do handoff esta no que **nao** esta no log:

- **O que esta quebrado agora** — teste vermelho, deploy pela metade, feature atras de flag.
- **O que exige um humano** — o apply de Terraform que o CD nao faz, a migration que espera
  janela, a decisao de produto parada esperando dono.
- **O que ficou represado** — se a medicao achou worktree sem PR, diga o que tem la dentro e
  por que parou. Foi o achado que justificou este comando.
- **O que voce tentou e nao funcionou** — economiza a proxima sessao repetir o caminho.

Ordene as pendencias por **o que voce atacaria primeiro**, nao por ordem cronologica.

Corte o que o git ja conta sozinho. Se a linha comeca com "implementamos", provavelmente e
ruido: o commit ja diz isso.

## Passo 3 — ESCREVER

**Criterio fixo, estrutura livre.** As secoes variam com o que a sessao produziu; o que nao
varia sao as tres perguntas: *o que esta quebrado*, *o que exige humano*, *o que eu verifiquei
de verdade*.

Nao use template rigido. O que valia num dia (gap de producao, apply pendente, commits orfaos,
teste vermelho) nao e o que vale no outro.

### A secao obrigatoria: "o que eu NAO verifiquei"

Copie para ela **toda** secao que saiu `NAO MEDIDO`, com o motivo.

Isto nao e formalidade. Este projeto tem quatro retratacoes formais (ADR-008) pela mesma falha:
ausencia de dado lida como ausencia de fato. Se o `gh` nao respondeu, o handoff **nao pode**
dizer "nenhum PR aberto" — tem que dizer "nao consegui verificar PRs".

Um handoff que declara seus limites e mais util que um que parece completo.

### Nome do arquivo

`docs/handoffs/AAAA-MM-DD-<slug>.md`, slug em ASCII kebab-case (Regra 14). O slug deve dizer o
que a sessao **produziu**, nao a data por extenso: `tres-merges-e-o-teste-que-mentia` serve;
`sessao-de-quinta` nao.

## Passo 4 — FECHAR (ponteiro + git, mecanicos)

```bash
bash .claude/scripts/handoff-commit.sh \
  --file docs/handoffs/AAAA-MM-DD-<slug>.md \
  --linha "<uma frase do que SO existe neste handoff>"
```

O `--linha` vai para o bloco `HANDOFF` do `MEMORY.md` e e o que a proxima sessao le antes de
abrir o arquivo. Escreva o que se perderia se ninguem abrisse: *"o deploy de prod disparado no
fim da sessao — conferir o desfecho ANTES de qualquer coisa"*, e nao *"resumo da sessao"*.

O script exige que voce esteja na `main` (a medicao e a base do commit precisam ser o estado
do mundo), monta o commit numa **worktree temporaria**, empurra a branch `handoff/<slug>` e
abre o **PR**. Seu checkout nao e tocado: funciona com arvore suja, e trabalho de terceiro nao
viaja de carona.

**Nada e escrito na `main` diretamente.** O merge do PR e o ponto de parada humano — barato
(dois arquivos de doc) e compativel com qualquer protecao de branch. Repos com `main`
protegida rejeitariam um push direto, deixando o handoff preso na sua maquina.

⛔ **Nao declare o handoff concluido antes do `exit 0`** — e lembre que, ate o PR ser
mergeado, **o handoff ainda nao esta vivo**: o `/engineer:warm-up` le o ponteiro da `main`. Se
o PR ficar esquecido, a proxima execucao do `handoff-measure.sh` acusa na secao
`HANDOFF_EM_PR_ABERTO`.

---

## Quando rodar

Quando a sessao produziu algo que a proxima precisa saber: PR mergeado, deploy disparado,
trabalho represado, decisao pendente. **Nao ha gatilho automatico** — nem por tamanho de
contexto, nem por evento.

Percentual de janela mede tempo gasto, nao valor a entregar: uma sessao que leu 60 arquivos
para responder uma pergunta tem contexto enorme e nada para passar adiante. Pior, um gatilho
por limiar escreveria o handoff no pior momento — na versao mais degradada da sessao, mais
propensa a recuperar de memoria em vez de medir, que e exatamente o defeito que este comando
existe para corrigir.

## Consent

**Notificacao** para escrever e propor; **Confirmacao** para entrar na `main`. O comando cria
branch, commita e abre o PR sem parar — nada disso e irreversivel. A acao critica (o handoff
chegar na `main`) exige o merge, que e humano. E o ponto de parada que o `CONTRIBUTING.md`
pede para comandos que fazem commit, e o mesmo padrao do Fleet, que abre PR e para.

## Configuracao por projeto (opcional)

Sem config o comando funciona e declara o que nao consegue medir. Com
`.claude/handoff.config.sh` ele passa a medir gap de producao e paths de fronteira — veja
`.claude/scripts/handoff.config.example.sh`.
