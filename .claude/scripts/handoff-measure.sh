#!/usr/bin/env bash
#
# handoff-measure.sh — Cortex · matriz de medicao do /engineer:handoff
#
# SOMENTE LEITURA DO REPO. Nunca altera arquivo versionado, indice ou ref — o unico efeito
# em disco e um temporario de `mktemp`, usado para isolar o carregamento da config. Deliberado — medir precisa ser seguro de rodar a qualquer momento,
# inclusive fora do comando ("tem algo represado?"). Quem escreve e o handoff-commit.sh.
#
# Por que o comando mede em vez de lembrar:
#
# Handoff escrito de memoria vira resumo da conversa, e a conversa nao sabe o estado do
# mundo. Medido num repo real em 2026-07-31: a sessao ia registrar "producao atualizada"
# e havia 5 commits de gap; e havia commits vivos numa worktree que nunca viraram PR, um
# deles resolvendo uma pergunta que a documentacao ainda registrava como ABERTA. Nada
# disso apareceu na conversa — so apareceu porque alguem rodou `git log`. A sessao que
# produziu aqueles commits tinha terminado dias antes.
#
# ── REGRA DE DESENHO NAO-NEGOCIAVEL ──────────────────────────────────────────────
#
# O rotulo `MEDIDO` E O PRODUTO deste script. Ele so pode ser impresso quando a medicao
# de fato aconteceu. Toda secao que nao pode medir imprime `NAO MEDIDO` com o motivo.
#
# Disso decorrem duas regras operacionais, aprendidas da forma cara (a primeira versao
# deste script produziu 6 afirmacoes falsas, nenhuma detectavel por shellcheck):
#
#   1. CAPTURE O STATUS DE SAIDA, NUNCA INFIRA DE VAZIO.
#      `cmd 2>/dev/null || true` seguido de `[[ -z "$out" ]] && "nenhum X"` transforma
#      falha em zero. E o defeito da ADR-008 escrito em bash: `gh pr list` falhando num
#      repo sem remote produzia exatamente a frase "nenhum PR aberto".
#
#   2. VERIFIQUE TODA REF E TODO PATH ANTES DE USAR NUM RANGE.
#      Nome que nao resolve faz `rev-list` e `diff` sairem vazios com status 0 — e a
#      secao declara vazio o que esta cheio. Num clone comum, `origin/HEAD` aponta para
#      `origin/main` e a branch `main` LOCAL pode nao existir.
#
# Este projeto tem 4 retratacoes formais (ADR-008, v3.8.0 -> v3.11.3) pela mesma falha de
# raciocinio: ausencia de dado lida como ausencia de fato. Um `MEDIDO` falso aqui carimba
# o desconhecido de verificado, que e pior do que nao medir.
#
# Uso:
#   bash .claude/scripts/handoff-measure.sh
#   HANDOFF_MAIN_BRANCH=trunk bash .claude/scripts/handoff-measure.sh   # env vence a config
#
# Config opcional por projeto: .claude/handoff.config.sh (ver handoff.config.example.sh)
# Stack-agnostico por construcao (Regra 12): nenhum path de projeto vive aqui.
#
set -uo pipefail

# SCRIPT_DIR resolvido ANTES de qualquer `cd`: com BASH_SOURCE relativo — que e como a doc
# manda invocar — calcular isto depois do `cd "$ROOT"` faz o dirname virar a raiz do repo e a
# lib nunca ser encontrada. E a armadilha que matou a telemetria de processo na v3.10.1, e ali
# tambem falhava em silencio.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "handoff-measure: nao e um repositorio git" >&2; exit 2; }
cd "$ROOT" || { echo "handoff-measure: nao foi possivel entrar em $ROOT" >&2; exit 2; }

_LIB="$SCRIPT_DIR/_handoff-lib.sh"
if [[ ! -f "$_LIB" ]]; then
  # Fail-CLOSED, ao contrario do _emit.sh do Fleet: la a telemetria perdida nao muda o que o
  # dev ve; aqui a lib carrega a resolucao da branch principal, e seguir sem ela produziria
  # medicao errada com rotulo MEDIDO — pior que nao medir.
  echo "handoff-measure: _handoff-lib.sh ausente em $_LIB — abortando" >&2
  echo "handoff-measure: se ele existe no checkout principal, precisa ser COMMITADO para chegar aqui." >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$_LIB"



# ── helpers de saida ──────────────────────────────────────────────────────────
sec()  { printf '\n## %s\n' "$1"; }
ok()   { printf 'MEDIDO      %s\n' "$1"; }
nope() { printf 'NAO MEDIDO  %s\n' "$1"; }
item() { printf '  %s\n' "$1"; }

handoff_resolver_main || true

BRANCH="$(handoff_branch_atual)"

# `git status --porcelain` e nao `git diff --quiet`: o primeiro enxerga untracked, e
# arquivo novo nao-commitado e justamente o que se perde entre sessoes.
if ST_OUT="$(git status --porcelain 2>&1)"; then
  DIRTY_COUNT="$(printf '%s' "$ST_OUT" | grep -c . || true)"
  DIRTY_TXT="${DIRTY_COUNT} arquivo(s)"
else
  DIRTY_TXT="NAO MEDIDO ($(first_line "$ST_OUT"))"
fi

# ── cabecalho ─────────────────────────────────────────────────────────────────
printf '# HANDOFF MEASURE — %s\n' "$(basename "$ROOT")"
printf 'data=%s  branch=%s  main=%s  arvore_suja=%s\n' \
  "$(date -u +%Y-%m-%dT%H:%MZ)" "$BRANCH" "${MAIN_REF:-<nao resolvida>}" "$DIRTY_TXT"

[[ -n "$CONFIG_AVISO" ]] && printf 'AVISO: %s\n' "$CONFIG_AVISO"
[[ -n "$MAIN_ATRASO" ]] && printf 'AVISO: %s\n' "$MAIN_ATRASO"
if [[ -z "$MAIN_REF" ]]; then
  printf 'AVISO: branch principal nao resolvida (%s).\n' "$MAIN_WHY"
  printf 'Secoes que dependem dela sairao NAO MEDIDO — nenhuma vai fingir vazio.\n'
fi

# gh e opcional. Quando falta, cada secao dependente diz o que perdeu — nunca some.
GH_OK=0
GH_WHY=""
if ! command -v gh >/dev/null 2>&1; then
  GH_WHY="gh nao esta no PATH — instale o GitHub CLI para medir esta secao"
elif ! GH_AUTH_OUT="$(gh auth status 2>&1)"; then
  # `gh auth status` toca a rede: offline e rate-limit caem aqui tambem. Afirmar
  # "nao autenticado" seria inventar a causa num relatorio cujo valor e a precisao dela.
  GH_WHY="gh nao confirmou autenticacao (sem login, sem rede ou rate limit): $(first_line "$GH_AUTH_OUT")"
else
  GH_OK=1
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "GAP_DEPLOY_MAIN"
# ══════════════════════════════════════════════════════════════════════════════
# O sha que esta em producao. Duas fontes possiveis, ambas configuraveis: um workflow
# de deploy (o run bem-sucedido mais recente) ou uma ref que o projeto move ao deployar.
# Sem nenhuma das duas, a resposta honesta e "nao sei" — e o script diz isso.

PROD_SHA=""
PROD_ORIGEM=""
GAP_BASE=""

if [[ -n "$HANDOFF_PROD_REF" ]]; then
  if PROD_SHA="$(git rev-parse --verify --quiet "${HANDOFF_PROD_REF}^{commit}" 2>/dev/null)" && [[ -n "$PROD_SHA" ]]; then
    PROD_ORIGEM="HANDOFF_PROD_REF=$HANDOFF_PROD_REF"
  else
    PROD_SHA=""
    nope "HANDOFF_PROD_REF='$HANDOFF_PROD_REF' nao resolve para um commit (falta 'git fetch'?)"
    [[ -n "$HANDOFF_DEPLOY_WORKFLOW" ]] && \
      item "HANDOFF_DEPLOY_WORKFLOW='$HANDOFF_DEPLOY_WORKFLOW' NAO foi tentado — PROD_REF tem precedencia"
  fi
elif [[ -n "$HANDOFF_DEPLOY_WORKFLOW" ]]; then
  if [[ "$GH_OK" -eq 1 ]]; then
    if RUN_OUT="$(gh run list --workflow "$HANDOFF_DEPLOY_WORKFLOW" --limit 20 \
                    --json headSha,conclusion \
                    -q '[.[] | select(.conclusion=="success")][0].headSha' 2>&1)"; then
      if [[ -n "$RUN_OUT" && "$RUN_OUT" != "null" ]]; then
        PROD_SHA="$RUN_OUT"
        PROD_ORIGEM="workflow $HANDOFF_DEPLOY_WORKFLOW (ultimo run com sucesso)"
      else
        nope "workflow '$HANDOFF_DEPLOY_WORKFLOW' sem run bem-sucedido nos ultimos 20"
      fi
    else
      nope "gh run list falhou: $(first_line "$RUN_OUT")"
    fi
  else
    nope "$GH_WHY (HANDOFF_DEPLOY_WORKFLOW esta configurado mas exige gh)"
  fi
else
  nope "nem HANDOFF_PROD_REF nem HANDOFF_DEPLOY_WORKFLOW configurados em .claude/handoff.config.sh"
  item "sem isso o handoff NAO pode afirmar nada sobre producao — declare a limitacao no texto"
fi

if [[ -n "$PROD_SHA" ]]; then
  if ! ref_ok "$PROD_SHA"; then
    nope "sha de producao ${PROD_SHA:0:7} nao existe no checkout local — rode 'git fetch' e repita"
  elif [[ -z "$MAIN_REF" ]]; then
    nope "branch principal nao resolvida — impossivel calcular o gap"
  elif GAP_COUNT="$(git rev-list --count "${PROD_SHA}..${MAIN_REF}" 2>&1)"; then
    GAP_BASE="$PROD_SHA"
    ok "base=${PROD_SHA:0:7} head=${MAIN_REF} commits=${GAP_COUNT}  [$PROD_ORIGEM]"
    if [[ "$GAP_COUNT" != "0" ]]; then
      git log --oneline --no-decorate "${PROD_SHA}..${MAIN_REF}" 2>/dev/null | head -20 \
        | while IFS= read -r l; do item "$l"; done
    fi
  else
    nope "rev-list ${PROD_SHA:0:7}..${MAIN_REF} falhou: $(first_line "$GAP_COUNT")"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "PRS_ABERTOS"
# ══════════════════════════════════════════════════════════════════════════════
# A lista de branches com PR aberto tambem alimenta WORKTREES_REPRESADAS: trabalho
# sem PR e categoricamente diferente de trabalho aguardando review.

PR_BRANCHES=""      # delimitado por | para busca sem array associativo (bash 3.2)
PR_BRANCHES_OK=0

if [[ "$GH_OK" -eq 1 ]]; then
  # Status, nao vazio: num repo sem remote do GitHub o `gh pr list` FALHA, e tratar a
  # saida vazia como "zero PRs" imprimia exatamente a frase que este script existe para
  # nunca imprimir.
  if PR_RAW="$(gh pr list --state open --limit 50 \
                 --json number,title,headRefName,isDraft \
                 -q '.[] | "#\(.number)|\(.headRefName)|\(if .isDraft then "draft" else "pronto" end)|\(.title)"' 2>&1)"; then
    PR_BRANCHES_OK=1
    if [[ -z "$PR_RAW" ]]; then
      ok "nenhum PR aberto"
    else
      ok "$(printf '%s\n' "$PR_RAW" | grep -c . || true) PR(s) aberto(s)"
      while IFS='|' read -r num head draft title; do
        [[ -z "$num" ]] && continue
        PR_BRANCHES="${PR_BRANCHES}|${head}|"
        item "$num  [$draft]  $head  — $title"
      done <<< "$PR_RAW"
    fi
  else
    nope "gh pr list falhou: $(first_line "$PR_RAW")"
  fi
else
  nope "$GH_WHY"
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "WORKTREES_REPRESADAS"
# ══════════════════════════════════════════════════════════════════════════════
# A secao que justificou o comando sozinho: encontrou commits e dezenas de arquivos vivos
# numa worktree que nunca virou PR — invisiveis para qualquer sessao, porque a que os
# produziu tinha acabado dias antes. 100% generica: so precisa de git.
#
# Aqui um `continue` silencioso e o pior defeito possivel: reduz a contagem sem dizer, e
# a secao inteira existe para achar o que ninguem esta vendo. Todo candidato pulado por
# erro vira aviso explicito.

if [[ -z "$MAIN_REF" ]]; then
  nope "branch principal nao resolvida ($MAIN_WHY) — impossivel saber o que nao foi mergeado"
elif ! WT_LIST="$(git worktree list --porcelain 2>&1)"; then
  # `done < <(cmd)` torna o status do cmd INACESSIVEL por construcao: se a listagem
  # falhasse, o laco nao rodava, os contadores ficavam em zero e a secao imprimia
  # "nenhuma worktree" — o unico ponto onde "vazio = nada" tinha sobrevivido, e logo
  # no topo, onde nenhuma guarda de dentro do laco alcanca.
  nope "git worktree list falhou: $(first_line "$WT_LIST")"
else
  ACHOU=0
  PULADAS=0
  WT_OUT=""
  PULADAS_OUT=""

  # `${line#worktree }` em vez de awk com `$1=""`: o awk remonta o registro com OFS e
  # colapsa espacos duplos, corrompendo paths que os contenham.
  while IFS= read -r line; do
    case "$line" in worktree\ *) ;; *) continue ;; esac
    wt="${line#worktree }"
    [[ -z "$wt" ]] && continue

    if [[ ! -d "$wt" ]]; then
      PULADAS=$((PULADAS + 1))
      PULADAS_OUT="${PULADAS_OUT}  ${wt}
      diretorio ausente (worktree prunable) — pode conter trabalho nao-mergeado INVISIVEL aqui
      inspecione com 'git worktree list' / 'git worktree prune' antes de confiar nesta secao
"
      continue
    fi

    wt_branch="$(git -C "$wt" symbolic-ref --short --quiet HEAD 2>/dev/null)" || wt_branch=""
    [[ -z "$wt_branch" ]] && wt_branch="(detached)"
    [[ "$wt_branch" == "$MAIN_NAME" ]] && continue

    if ! n_commits="$(git -C "$wt" rev-list --count "${MAIN_REF}..HEAD" 2>&1)"; then
      PULADAS=$((PULADAS + 1))
      PULADAS_OUT="${PULADAS_OUT}  ${wt}
      branch=${wt_branch}  NAO foi possivel contar commits: $(first_line "$n_commits")
"
      continue
    fi
    [[ "$n_commits" == "0" ]] && continue

    ACHOU=$((ACHOU + 1))

    # Os campos secundarios precisam do mesmo rigor do principal. Na iteracao anterior
    # eles ficaram com `2>/dev/null | grep -c . || true`, entao numa branch orfa (sem
    # merge base) o `git diff A...B` falhava e saia `arquivos=0` sob MEDIDO — com dois
    # arquivos reais em disco. E justamente o campo que sustenta a frase "51 arquivos
    # represados": o numero que vende a secao era o unico ainda fabricavel.
    if _fout="$(git -C "$wt" diff --name-only "${MAIN_REF}...HEAD" 2>&1)"; then
      n_files="$(printf '%s' "$_fout" | grep -c . || true)"
    else
      n_files="?"   # sem merge base, por exemplo
    fi
    if _sout="$(git -C "$wt" status --porcelain 2>&1)"; then
      wt_dirty="$(printf '%s' "$_sout" | grep -c . || true)"
    else
      wt_dirty="?"
    fi

    if [[ "$PR_BRANCHES_OK" -eq 1 ]]; then
      case "$PR_BRANCHES" in
        *"|${wt_branch}|"*) pr_state="tem PR aberto" ;;
        *)                  pr_state="SEM PR — represado" ;;
      esac
    else
      pr_state="PR desconhecido (gh indisponivel)"
    fi

    wt_label="$wt"
    [[ "$wt" == "$ROOT" ]] && wt_label="$wt   (esta worktree)"

    # Substituicao de comando, nao `| while`: o pipe abre subshell e a acumulacao em
    # WT_OUT se perderia sem deixar rastro.
    commits_txt="$(git -C "$wt" log --oneline --no-decorate "${MAIN_REF}..HEAD" 2>/dev/null \
                   | head -5 | sed 's/^/        /')"

    WT_OUT="${WT_OUT}  ${wt_label}
      branch=${wt_branch}  commits=${n_commits}  arquivos=${n_files}  nao-commitado=${wt_dirty}  [${pr_state}]
${commits_txt}
"
  done <<< "$WT_LIST"

  if [[ "$PULADAS" -gt 0 ]]; then
    nope "medicao PARCIAL — $PULADAS worktree(s) nao inspecionavel(is), $ACHOU represada(s) entre as inspecionadas"
    printf '%s' "$PULADAS_OUT"
    [[ "$ACHOU" -gt 0 ]] && printf '%s' "$WT_OUT"
  elif [[ "$ACHOU" -eq 0 ]]; then
    ok "nenhuma worktree com commit nao-mergeado em $MAIN_REF"
  else
    ok "$ACHOU worktree(s) com trabalho nao-mergeado"
    printf '%s' "$WT_OUT"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "COMMITS_NAO_PUSHADOS"
# ══════════════════════════════════════════════════════════════════════════════
# `git rev-parse --abbrev-ref @{u}` FALHA mas ecoa o literal "@{u}" no stdout, entao
# guardar por vazio nao pega. Guardar por status, sim.

if UPSTREAM="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" && [[ -n "$UPSTREAM" ]]; then
  if N_UNPUSHED="$(git rev-list --count "${UPSTREAM}..HEAD" 2>&1)"; then
    ok "$N_UNPUSHED commit(s) local(is) a frente de $UPSTREAM"
    if [[ "$N_UNPUSHED" != "0" ]]; then
      git log --oneline --no-decorate "${UPSTREAM}..HEAD" 2>/dev/null | head -10 \
        | while IFS= read -r l; do item "$l"; done
    fi
  else
    nope "upstream '$UPSTREAM' registrado mas nao resolve (remote-tracking podado?): $(first_line "$N_UNPUSHED")"
  fi
else
  nope "branch '$BRANCH' nao tem upstream configurado (git push -u)"
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "FRONTEIRA_TOCADA"
# ══════════════════════════════════════════════════════════════════════════════
# Paths cuja mudanca exige acao humana que o CD nao faz — migration, infraestrutura.
# E a diferenca entre "o PR entrou" e "o PR entrou e o alarme ainda nao existe".
#
# `git diff` e permissivo com pathspec: path inexistente devolve status 0 e saida vazia.
# Um typo na config viraria "nada a aplicar" — justamente na secao de maior consequencia.

if [[ "${#HANDOFF_BOUNDARY_PATHS[@]}" -eq 0 ]]; then
  nope "HANDOFF_BOUNDARY_PATHS vazio em .claude/handoff.config.sh"
  item "declare os paths que exigem acao manual (migrations, infra/) para medir esta secao"
elif [[ -z "$GAP_BASE" ]]; then
  nope "sem base de producao (ver GAP_DEPLOY_MAIN) — nao ha intervalo onde procurar"
else
  # UM VEREDITO POR SECAO. A iteracao anterior imprimia `NAO MEDIDO` e `MEDIDO` na mesma
  # secao quando havia um path valido e outro nao — e o comando da Fase 3 copia as linhas
  # `NAO MEDIDO` para "o que eu nao verifiquei", entao ele copiaria a secao E reportaria o
  # achado como verificado.
  #
  # E "path ausente" nao e sinonimo de typo: o proprio handoff.config.example.sh sugere
  # declarar migrations, infra/ e charts/, e um projeto que ainda nao adotou um deles
  # ficaria com alerta em TODA execucao, sem nada a corrigir. Alerta permanente e como se
  # ensina um time a ignorar alerta.
  COBERTOS=0
  AUSENTES=""
  for _p in "${HANDOFF_BOUNDARY_PATHS[@]}"; do
    [[ -z "$_p" ]] && continue
    _pc="${_p%%/}"
    case "$_p" in
      *'*'*|*'?'*|*'['*)   # pathspec com glob: `git diff` aceita, `cat-file` nao
        COBERTOS=$((COBERTOS + 1)); continue ;;
    esac
    if git cat-file -e "${MAIN_REF}:${_pc}" 2>/dev/null; then
      COBERTOS=$((COBERTOS + 1))
    else
      AUSENTES="${AUSENTES} '${_p}'"
    fi
  done

  if [[ "$COBERTOS" -eq 0 ]]; then
    nope "nenhum dos paths de HANDOFF_BOUNDARY_PATHS existe em ${MAIN_REF}:${AUSENTES}"
    item "typo na config, ou nenhuma dessas categorias foi adotada ainda — esta secao nao cobre nada hoje"
  elif TOCADOS="$(git diff --name-only "${GAP_BASE}..${MAIN_REF}" -- "${HANDOFF_BOUNDARY_PATHS[@]}" 2>&1)"; then
    if [[ -z "$TOCADOS" ]]; then
      ok "nenhum path de fronteira tocado no gap ($COBERTOS path(s) cobertos)"
    else
      ok "$(printf '%s\n' "$TOCADOS" | grep -c . || true) arquivo(s) de fronteira no gap — exige acao humana"
      printf '%s\n' "$TOCADOS" | head -20 | while IFS= read -r l; do item "$l"; done
    fi
    [[ -n "$AUSENTES" ]] && \
      item "nota: nao existe(m) em ${MAIN_REF}, fora da cobertura desta medicao:${AUSENTES}"
  else
    nope "git diff dos paths de fronteira falhou: $(first_line "$TOCADOS")"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "HANDOFF_VIVO_ATUAL"
# ══════════════════════════════════════════════════════════════════════════════
# Detecta o defeito (a) ANTES de escrever: o ponteiro apontando para um handoff que ja
# nao e o mais recente. Foi o estado real de um repo em 2026-07-31 — arquivo escrito e
# commitado, ponteiro parado no da sessao anterior.
#
# Tres estados distintos, e confundi-los seria cometer aqui o erro que este script existe
# para evitar: nao achar no formato esperado NAO e o mesmo que nao existir.

BLOCO=""
APONTADO=""
if [[ -f "$HANDOFF_MEMORY_FILE" ]]; then
  BLOCO="$(sed -n '/HANDOFF:START/,/HANDOFF:END/p' "$HANDOFF_MEMORY_FILE" 2>/dev/null || true)"
  if [[ -n "$BLOCO" ]]; then
    # DUAS passadas, e a ordem importa.
    #
    # (1) Entre crases — que e como o /engineer:handoff escreve o ponteiro. Delimitado,
    #     entao aceita espaco no nome sem risco de gula.
    # (2) Fallback sem espaco, para ponteiro escrito a mao.
    #
    # A tentacao e usar um charset permissivo direto (`[^`"']*\.md`), e ela custou caro:
    # `*` e guloso e casa ate o ULTIMO .md da linha, entao um ponteiro correto seguido de
    # "(substitui o 2026-07-29-velho.md)" virava um path inexistente e a secao acusava
    # PENDURADO — pior que o falso alarme que a mudanca tentava consertar, porque o
    # comando reescreveria um ponteiro que estava certo.
    #
    # LIMITE ASSUMIDO: nome com espaco SEM crases nao e reconhecido. Nao ha regex correta
    # para isso — sem delimitador, "a.md b.md" e ambiguo por construcao. A escolha e
    # coerente com a Regra 14 (nomes de arquivo em ASCII, sem caractere especial), que ja
    # desencoraja espaco, e o proprio comando sempre escreve o ponteiro entre crases.
    APONTADO="$(printf '%s\n' "$BLOCO" \
                | sed -n 's/.*`\([^`]*[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-[^`]*\.md\)`.*/\1/p' \
                | head -1 || true)"
    [[ -z "$APONTADO" ]] && APONTADO="$(printf '%s\n' "$BLOCO" \
                | grep -oE '([A-Za-z0-9_.-]+/)*[0-9]{4}-[0-9]{2}-[0-9]{2}-[A-Za-z0-9._-]+\.md' \
                | head -1 || true)"
  fi
fi

# Glob em vez de `ls | grep`: nome com espaco quebraria o pipe, e o glob ja expande em
# ordem lexicografica — com prefixo AAAA-MM-DD isso e ordem cronologica.
MAIS_RECENTE=""
DIR_EXISTE=0
if [[ -d "$HANDOFF_DIR" ]]; then
  DIR_EXISTE=1
  for _f in "$HANDOFF_DIR"/[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md; do
    [[ -e "$_f" ]] || continue   # glob sem match vem literal
    MAIS_RECENTE="$(basename "$_f")"
  done
fi

if [[ ! -f "$HANDOFF_MEMORY_FILE" ]]; then
  nope "arquivo de memoria '$HANDOFF_MEMORY_FILE' nao existe"
elif [[ "$DIR_EXISTE" -eq 0 ]]; then
  # Sem o diretorio nao ha como saber qual e o mais recente — e sem isso nao ha como
  # afirmar coerencia. Antes esta combinacao caia no ramo "coerente" por curto-circuito.
  nope "HANDOFF_DIR='$HANDOFF_DIR' nao existe — impossivel comparar o ponteiro com o handoff mais recente"
  [[ -n "$APONTADO" ]] && item "o bloco aponta para: $APONTADO"
elif [[ -z "$BLOCO" && -z "$MAIS_RECENTE" ]]; then
  ok "nenhum handoff registrado ainda (primeiro handoff deste repo)"
elif [[ -z "$BLOCO" ]]; then
  nope "bloco HANDOFF:START/END ausente em $HANDOFF_MEMORY_FILE — repo ainda nao usa o formato do comando"
  item "mais recente em $HANDOFF_DIR/: $MAIS_RECENTE"
  item "pode haver ponteiro escrito a mao fora do bloco: NAO da para afirmar que falta ponteiro"
  item "a primeira execucao do /engineer:handoff cria o bloco"
elif [[ -z "$APONTADO" ]]; then
  ok "bloco HANDOFF existe mas NAO cita nenhum arquivo de handoff"
  item "mais recente em $HANDOFF_DIR/: ${MAIS_RECENTE:-<nenhum>}"
  item "ATENCAO: handoff existe e ninguem o encontra pelo warm-up — e o defeito (a)"
else
  APONTADO_BASE="$(basename "$APONTADO")"
  # Checar o caminho COMO ESCRITO quando ele traz diretorio: procurar sempre em
  # $HANDOFF_DIR faria um ponteiro para 'docs/notes/X.md' ser validado contra
  # 'docs/handoffs/X.md' — arquivo diferente, veredito sem sentido.
  case "$APONTADO" in
    */*) APONTADO_PATH="$APONTADO" ;;
    *)   APONTADO_PATH="$HANDOFF_DIR/$APONTADO" ;;
  esac
  if [[ ! -f "$APONTADO_PATH" ]]; then
    ok "ponteiro PENDURADO — aponta para arquivo que nao existe"
    item "aponta para: $APONTADO"
    item "mais recente em $HANDOFF_DIR/: ${MAIS_RECENTE:-<nenhum>}"
  elif [[ -z "$MAIS_RECENTE" ]]; then
    nope "nenhum arquivo no padrao AAAA-MM-DD-*.md em $HANDOFF_DIR — nao ha com que comparar"
    item "o bloco aponta para: $APONTADO"
  elif [[ "$APONTADO_BASE" != "$MAIS_RECENTE" ]]; then
    ok "ponteiro DESATUALIZADO"
    item "aponta para: $APONTADO_BASE"
    item "mais recente: $MAIS_RECENTE"
    item "ATENCAO: o warm-up carregaria o handoff errado como vivo"
  else
    ok "ponteiro coerente com o handoff mais recente: $APONTADO_BASE"
  fi
fi

# ══════════════════════════════════════════════════════════════════════════════
sec "HANDOFF_EM_PR_ABERTO"
# ══════════════════════════════════════════════════════════════════════════════
# O handoff vai para a main por PR (nunca push direto). Isso troca um problema por outro
# menor: o handoff so fica vivo depois do merge, e um PR esquecido reabre o defeito (a) com
# outra roupa — arquivo escrito que ninguem le. Aqui ele deixa de ser esquecivel.

if [[ "$GH_OK" -ne 1 ]]; then
  nope "$GH_WHY"
elif ! HPR="$(gh pr list --state open --limit 30 --json number,headRefName,url,createdAt \
                -q '.[] | select(.headRefName | startswith("handoff/")) | "#\(.number)|\(.headRefName)|\(.url)"' 2>&1)"; then
  nope "gh pr list falhou: $(first_line "$HPR")"
elif [[ -z "$HPR" ]]; then
  ok "nenhum handoff represado em PR aberto"
else
  ok "$(printf '%s\n' "$HPR" | grep -c . || true) handoff(s) em PR ABERTO — nao estao vivos ainda"
  while IFS='|' read -r num head url; do
    [[ -z "$num" ]] && continue
    item "$num  $head"
    item "    $url"
  done <<< "$HPR"
  item "ATENCAO: o warm-up le o ponteiro da main — enquanto o PR nao mergear, o handoff nao existe para a proxima sessao"
fi

printf '\n# fim — secoes NAO MEDIDO devem virar a secao "o que eu nao verifiquei" do handoff\n'
