# Fleet — modo autonomo (`/engineer:fleet-autonomous`)

Variante do Fleet em que **o lead conduz o pipeline sem os 3 gates humanos bloqueantes**.
No lugar dos gates de qualidade, o lead executa **verificacao adversarial** ele mesmo. Os
gates NAO somem: sao substituidos por (a) verificacao adversarial do lead e (b) um **freio
de mao** que escala ao humano so em tres classes de decisao.

Este arquivo e o "como" do modo autonomo. A infra (config layer, provisionamento, cap de
RAM) e as 5 garantias seguem no [`pipeline.md`](pipeline.md) e na ADR-013. Decisao
arquitetural do modo autonomo: adendo da ADR-013.

## Quando usar este modo (vs o fleet classico)

- **`/engineer:fleet`** (gate-based): quando voce QUER as paradas humanas — arquitetura
  nova, epic grande, algo que o lead deve poder vetar antes de implementar.
- **`/engineer:fleet-autonomous`**: quando o trabalho e bem-escopado (bugs, follow-ups,
  features sobre fundacao ja existente, divida) e voce confia no lead para conduzir ate o
  PR com verificacao rigorosa. E o modo "toca isso do comeco ao fim e me chama se travar".

## Default de autonomia: **ate o PR**

O modo autonomo conduz cada issue por TODO o pipeline (provisiona → warm-up → start → plan
→ work → garantias → pre-pr → **abre o PR**) sem parar nos gates de arquitetura e plano. E
**PARA no PR aberto**.

- O **auto-merge + fechamento** (tracker → Done, docs, teardown) so acontece com **`--merge`
  explicito** na invocacao, OU com um GO explicito do humano na conversa ("pode mergear",
  "fecha tudo"). Sem isso, o comando entrega os PRs abertos e para.
- Racional: o merge remoto e o ultimo ponto barato de controle humano; o default
  conservador o preserva. Ative o auto-merge so quando confiar no lote inteiro.

## O gate de qualidade vira VERIFICACAO ADVERSARIAL do lead

Este e o coracao do modo. Antes de abrir o PR (e de novo antes do merge, se `--merge`), o
lead NAO confia no relatorio dos subagents — ele **verifica o ground-truth** de forma
independente. Padrao que ja pegou defeitos reais que os subagents nao reportaram:

1. **Roda o teste do ALVO que o diff tocou, isolado** — o projeto/pacote/modulo especifico,
   nao so o gate agregado (que pode nao cobrir aquele alvo). Um implementador que rodou o
   teste de um pacote mas nao do outro deixa passar regressao no que ele nao rodou.
2. **Le o diff inteiro** dos arquivos-chave (nao so o resumo do impl). Quando o objetivo e
   refactor, confirma **paridade** (os testes existentes passam SEM alteracao).
3. **Exercita o comportamento de verdade** (o que a skill `/verify` faz): drive o fluxo
   afetado end-to-end e observa a **saida real** — um numero, um log, um screenshot — nao so
   unit/mock. "Validado so em mock" nao conta. Coleta a evidencia.
   - **FE/UI: drive o build da BRANCH sob teste, NUNCA a stack de dev compartilhada.** Um dev
     stack que ja esta no ar (docker-compose, container ou dev server preexistente) normalmente
     serve a branch BASE (main), NAO a worktree — apontar o browser/Playwright para ele valida
     codigo VELHO e da **falso-verde**. Suba um servidor da PROPRIA worktree numa porta-offset
     e **confirme na tela que a mudanca esta la** (o campo/toggle novo) antes de medir. A porta
     tem que ser uma **origem que o CORS do backend permita**, senao a UI da "failed to fetch"
     em toda chamada.
   - **"Backend real" != "e2e real".** Exercitar o endpoint direto (curl/fetch) prova o
     CONTRATO do backend, que e deployment-agnostic — mas NAO o wiring UI->backend. Mudanca de
     FE exige dirigir a UI real; nao substituir por um API-check e reportar "e2e real".
   - **Valide a ARVORE certa:** antes de confiar num "esta up", confirme que o servico serve a
     branch sob teste, nao outra checkout (mesma classe de "o gate rodou na base, nao na worktree").
4. **As garantias (code-reviewer + adr-compliance STRICT + fleet-gate.sh) rodam em paralelo**,
   mas o lead verifica o RESULTADO. Se o relatorio de um agente nao chega (ficou idle sem
   formalizar), o lead faz a verificacao direta no codigo — que e mais forte que confiar no
   finder, nao mais fraca. Um CRITICAL/HIGH real teria sido reportado; silencio + verificacao
   direta limpa = ok.

> Regra: **"eu verifiquei" > "o subagent afirma".** Toda decisao de merge do modo autonomo
> se apoia em verificacao do lead, nunca so no relatorio de um agente.

## Freio de mao — SEMPRE para e escala ao humano (3 classes)

Mesmo em modo autonomo, estas tres classes de decisao NAO sao do lead. Ao detectar qualquer
uma, o comando PARA a issue afetada, deixa o estado explicito e escala ao humano (as demais
issues da onda seguem):

1. **Decisao de produto** — ambiguidade de negocio/dominio que nao e escolha de engenharia
   (o "certo" depende de risco/prioridade que so o dono do produto decide). Registra a
   questao na issue e devolve a decisao.
2. **Nova decisao arquitetural** — ADR novo, novo boundary/lib, trade-off estrutural. Erro
   aqui propaga por toda a implementacao (e o racional do Gate 1 classico, preservado como
   escalacao sob demanda em vez de parada sistematica).
3. **Acao irreversivel / producao** — deploy, escrita em dado de producao, qualquer coisa
   outward-facing. Exige GO explicito do humano.

> Mudancas que tem **gate mecanico proprio NAO viram freio humano** neste modo: se existe uma
> checagem no `fleet-gate.sh` (ex.: validador de migration/schema, scan de secret, lint de
> policy) + `adr-compliance-checker` STRICT que as valida, elas podem ser implementadas
> autonomamente — o que as protege e mecanico, nao o julgamento humano. O freio e reservado
> ao que a maquina NAO julga.

## Discovery-first para issues incertas

Se a issue nao tem diagnostico cravado (sintoma sem causa localizada), o lead investiga o
**dado/codigo real ANTES** de plan/impl: consulta o estado real, le o artefato/output real,
localiza o ponto exato no codigo. Cria a issue/plano com o diagnostico ja feito (arquivos +
linhas), para o impl nao re-descobrir. Separa "criar issue por suposicao" de "criar issue
com o arquivo:linha + o valor real".

## Ciclo de fechamento (so apos `--merge`/GO)

Automatizado por `scripts/fleet-closeout.sh <worktree-name> [<pr#>] [--merge] [--drop-db]
[--delete-branch]`:

1. **Guarda de rastro** (fail-closed): roda o `fleet-phase-gate.sh --phase 2` DE DENTRO da
   worktree e recusa fechar se `.claude/sessions/<issue>/` nao estiver commitada. Roda antes
   do merge de proposito — depois do `--squash --delete-branch` a branch nao existe mais e
   nao ha onde commitar. Escape: `--skip-trace-guard` (nunca `--force`, que ja significa
   outras duas coisas e viraria bypass por habito).
2. **Merge** (se `--merge`): so mergeia se o PR estiver MERGEABLE + CLEAN (fail-closed).
3. **Sincroniza** a branch base (`checkout` + `pull`).
4. **Preserva a telemetria da worktree**: funde `command-usage.jsonl` da worktree no
   checkout principal (dedup por linha, idempotente) antes do teardown. O hook resolve o
   caminho pelo cwd do agente, entao tudo que a frota registrou vive dentro da worktree e
   sumiria no `worktree remove`.
5. **Teardown**: delega ao `fleet-teardown.sh` (worktree + dados isolados via
   `fleet_teardown_data` do projeto + branch).
6. **Imprime o checklist do que o LEAD ainda faz** (o script nao toca tracker/edicoes):
   tracker `<issue>` → Done; nota na doc canonica do repo, se a mudanca for estrutural;
   memoria de sessao.

**Merge serial** quando duas issues da onda tocam o MESMO arquivo: rebase entre merges. O gate
vermelho e quase sempre externo (containers efemeros sob contencao / lint pre-existente) —
confirmar rodando o alvo isolado antes de tratar como regressao.

## O que herda do fleet classico (inalterado)

- **Cap de RAM** (agentes vivos, nao worktrees): teto `floor((RAM_GB-10)/2.5)`; pre-PR 1
  worktree por vez em maquinas ≤24 GB; nunca misturar impl (fg) e branch-* (bg). Ver `SKILL.md`.
- **Infra isolada** por worktree via config layer (`.claude/fleet.config.sh`, hooks
  `fleet_provision_data`/`fleet_teardown_data`). Postgres/Redis/etc compartilhados.
- **Status do tracker e do lead:** `In Progress` ao soltar cada worktree; `In Review` no PR;
  `Done` no fechamento.
- **Registro** em `.claude/memory/evolution/command-usage.jsonl` (ADR-008), automatico
  desde a v3.9.0: cada script do Fleet emite o proprio evento (`fleet.provision`,
  `fleet.phase1`, `fleet.phase2`, `fleet.gate`, `fleet.closeout`, com `outcome`) e os hooks
  `SubagentStart`/`SubagentStop` registram cada subagente da onda. Contar comando nao mede
  frota — o lead le o markdown e executa inline, sem invocacao para o harness ver. O que e
  gravado dentro da worktree e absorvido pelo passo 4 do close-out.
- **Estilo:** seguir a convencao de idioma/acentuacao do repo consumidor.
