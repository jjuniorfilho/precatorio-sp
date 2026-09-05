#!/usr/bin/env bash
#
# handoff-commit.sh — Cortex · gate das tres entregas do /engineer:handoff
#
# O handoff so existe quando TRES coisas acontecem:
#
#   1. o arquivo em docs/handoffs/AAAA-MM-DD-<slug>.md
#   2. o PONTEIRO para ele no bloco HANDOFF do MEMORY.md
#   3. o ciclo git — commit numa branch propria + PR
#
# A segunda e a que sempre escapa. Medido num repo real em 2026-07-31: arquivo escrito,
# commitado e pushado; o ponteiro continuava apontando para o handoff da sessao anterior. O
# `/engineer:warm-up` carregaria o handoff errado como vivo — e a licao sobre esse mesmo
# defeito ja estava escrita na memoria daquele projeto.
#
# Por isso ESTE SCRIPT ESCREVE O PONTEIRO, em vez de conferir se alguem escreveu. O defeito e
# esquecimento; pedir para nao esquecer e o remedio que ja falhou. Ao agente cabe o texto — o
# julgamento do que e noticia — e ao script, o passo mecanico que ninguem lembra.
#
# POR QUE PR, E NAO PUSH NA MAIN. A versao anterior commitava e pushava direto na `main`. Isso
# violava a letra do CONTRIBUTING.md ("comando que faz commits DEVE incluir um ponto de parada")
# e a ADR-012, que classifica push como Confirmacao. Pior: era inviavel no caso geral — o
# proprio cortex-framework tem um ruleset `branches-somente-owner`, e qualquer repo de time com
# main protegida rejeitaria o push, deixando o handoff preso na maquina de quem escreveu.
#
# O PR resolve os dois: o merge E o ponto de parada humano (barato — dois arquivos de doc), e
# funciona sob qualquer protecao de branch.
#
# O commit e montado numa WORKTREE TEMPORARIA criada a partir da main. Isso mantem o checkout
# de quem esta trabalhando intocado (funciona com arvore suja) e faz a branch nascer limpa: so
# os dois arquivos entram, entao uma destilacao do memory-manager pendente no checkout local
# NAO viaja de carona sob a mensagem do handoff.
#
# Sai com CODIGO 2 em qualquer falha, no mesmo contrato do fleet-gate.sh: o stderr volta como
# feedback para o agente corrigir, e a fase nao avanca.
#
# Uso:
#   handoff-commit.sh --file docs/handoffs/2026-07-31-slug.md --linha "o que so existe aqui"
#   handoff-commit.sh --file ... --linha "..." --dry-run    # nao escreve, nao commita
#   handoff-commit.sh --file ... --linha "..." --no-pr      # pusha a branch, nao abre PR
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "handoff-commit: nao e um repositorio git" >&2; exit 2; }
cd "$ROOT" || { echo "handoff-commit: nao foi possivel entrar em $ROOT" >&2; exit 2; }

_LIB="$SCRIPT_DIR/_handoff-lib.sh"
if [[ ! -f "$_LIB" ]]; then
  echo "handoff-commit: _handoff-lib.sh ausente em $_LIB — abortando" >&2
  echo "handoff-commit: se ele existe no checkout principal, precisa ser COMMITADO para chegar aqui." >&2
  exit 2
fi
# shellcheck source=/dev/null
source "$_LIB"

die() { echo "⛔ handoff-commit: $*" >&2; exit 2; }

# ── argumentos ────────────────────────────────────────────────────────────────
FILE=""
LINHA=""
DRY_RUN=0
NO_PR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --file)
      # Validar presenca ANTES do `shift 2`: sem isto, `--file` como ultimo argumento
      # produz "unbound variable" criptico sob `set -u` (licao dos scripts do Fleet).
      [[ $# -ge 2 ]] || die "--file exige um valor"
      FILE="$2"; shift 2 ;;
    --linha)
      [[ $# -ge 2 ]] || die "--linha exige um valor"
      LINHA="$2"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    --no-pr) NO_PR=1; shift ;;
    *) die "argumento desconhecido: $1" ;;
  esac
done

[[ -n "$FILE" ]]  || die "--file e obrigatorio"
[[ -n "$LINHA" ]] || die "--linha e obrigatorio (uma frase do que SO existe neste handoff)"

# Allowlist de charset no path (licao do Fleet): o valor entra em comando de git e em
# manipulacao de arquivo. Sem espaco, coerente com a Regra 14 (nomes de arquivo em ASCII).
case "$FILE" in
  *[!A-Za-z0-9._/-]*) die "--file contem caractere fora de [A-Za-z0-9._/-]: '$FILE'
   nomes de arquivo do framework sao ASCII kebab-case (Regra 14)" ;;
esac
case "$LINHA" in
  *$'\n'*) die "--linha deve ser UMA linha (recebeu quebra de linha)" ;;
esac

handoff_resolver_main || true
BRANCH="$(handoff_branch_atual)"

# ══════════════════════════════════════════════════════════════════════════════
# GATE 0 — a branch
# ══════════════════════════════════════════════════════════════════════════════
# O handoff descreve o ESTADO DO MUNDO, nao o da feature: pertence a main. Escrito numa
# branch de trabalho ele fica preso a um merge que talvez nunca aconteca — que e a mesma
# classe do problema que o comando existe para resolver (trabalho vivo que ninguem ve).
[[ -n "$MAIN_NAME" ]] || die "branch principal nao resolvida ($MAIN_WHY)
   defina HANDOFF_MAIN_BRANCH em .claude/handoff.config.sh"

if [[ "$BRANCH" != "$MAIN_NAME" ]]; then
  die "voce esta em '$BRANCH', e o handoff se baseia em '$MAIN_NAME'.
   O handoff descreve o estado do mundo, nao o da feature: a medicao e a base do commit
   precisam ser a main. (O commit em si vai para uma branch propria + PR — nada e escrito
   na main diretamente.)
   Faca:  git checkout $MAIN_NAME  (e rode o /engineer:handoff de la)"
fi

# ══════════════════════════════════════════════════════════════════════════════
# GATE 1 — o arquivo
# ══════════════════════════════════════════════════════════════════════════════
[[ -f "$FILE" ]] || die "arquivo de handoff nao existe: $FILE"
[[ -s "$FILE" ]] || die "arquivo de handoff esta VAZIO: $FILE"

BASE="$(basename "$FILE")"
case "$BASE" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md) ;;
  *) die "nome fora do padrao AAAA-MM-DD-<slug>.md: $BASE
   o padrao e o que permite ordenar cronologicamente e achar o mais recente" ;;
esac

MEM="$HANDOFF_MEMORY_FILE"
[[ -f "$MEM" ]] || die "arquivo de memoria nao existe: $MEM
   o ponteiro precisa morar onde o /engineer:warm-up ja le"

# ── pre-condicoes do repo, ANTES de escrever qualquer byte ────────────────────
# Escrever primeiro e validar depois deixa estado inconsistente quando algo falha no meio:
# o MEMORY.md mutado e staged dentro de um merge, ou reescrito num arquivo que o git nem
# rastreia. Tudo que pode recusar, recusa aqui.
for _st in MERGE_HEAD REBASE_HEAD CHERRY_PICK_HEAD REVERT_HEAD; do
  [[ -e "$(git rev-parse --git-path "$_st" 2>/dev/null)" ]] && \
    die "ha um $_st em andamento — resolva antes de escrever o handoff
   commit parcial durante merge falha, e o MEMORY.md ficaria alterado e staged no indice"
done

git ls-files --error-unmatch -- "$MEM" >/dev/null 2>&1 \
  || die "'$MEM' nao e rastreado por este repo (gitignored, ou fora da arvore)
   sem git nao ha de onde recuperar se algo der errado — e este script reescreve o arquivo"

# O MEMORY.md tem DOIS escritores: este script e o memory-manager (architecture.md T4).
# Commitar com trabalho alheio pendente publicaria uma destilacao nao revisada sob a
# mensagem 'docs(handoff)'.
# Alteracao local no MEMORY.md deixou de ser bloqueio: a branch do handoff nasce do HEAD numa
# worktree propria, entao a sujeira local nao viaja de carona. Mas o ponteiro sera escrito
# sobre a versao do HEAD, e quem tem destilacao pendente precisa saber disso.
MEM_SUJO="$(git status --porcelain -- "$MEM" 2>/dev/null)"
if [[ -n "$MEM_SUJO" ]]; then
  echo "handoff-commit: AVISO — '$MEM' tem alteracao local nao commitada." >&2
  echo "handoff-commit: o ponteiro sera escrito sobre a versao do HEAD; sua alteracao NAO entra no PR." >&2
  echo "handoff-commit: e como este PR toca '$MEM', voce precisara commitar ou stashar essa" >&2
  echo "handoff-commit: alteracao antes de mergear — senao o merge recusa (comportamento do git)." >&2
fi

# ══════════════════════════════════════════════════════════════════════════════
# GATE 2 — o ponteiro (escrito aqui, nao conferido)
# ══════════════════════════════════════════════════════════════════════════════
# Substituicao idempotente: remove o bloco inteiro e reinsere no topo. Rodar duas vezes nao
# duplica bloco nem acumula ponteiro — o modo de falha que transformaria o "handoff vivo"
# numa lista de handoffs mortos.
# ── VALIDACAO ESTRUTURAL DO BLOCO, antes de tocar no arquivo ──────────────────
#
# O awk que remove o bloco antigo apaga tudo entre a abertura e o fechamento. Se o par nao
# estiver bem formado, ele apaga da abertura ate o EOF — e o `MEMORY.md` e conhecimento
# curado de meses.
#
# O gatilho mais provavel nao e corrupcao: e o proprio arquivo CITAR o formato do bloco. A
# doc do memory-manager ensina esses marcadores, e uma destilacao que traga esse texto para
# o corpo do MEMORY.md criaria uma abertura orfa. Por isso a validacao e estrutural e
# acontece ANTES de qualquer escrita: fora do formato exato, o script recusa e nao reescreve.
#
# Padrao unificado com o handoff-measure.sh (`HANDOFF:START`, sem exigir o `<!--`): antes os
# dois scripts usavam expressoes diferentes, entao existia bloco que um enxergava e o outro nao.
N_START="$(grep -c 'HANDOFF:START' "$MEM" || true)"
N_END="$(grep -c 'HANDOFF:END' "$MEM" || true)"

if [[ "$N_START" -gt 1 || "$N_END" -gt 1 ]]; then
  die "estrutura invalida em $MEM: $N_START marcador(es) START e $N_END END (esperado no maximo 1 de cada)
   o script NAO reescreveu nada. Deixe exatamente um par, ou nenhum."
fi
if [[ "$N_START" -ne "$N_END" ]]; then
  die "marcador HANDOFF orfao em $MEM: START=$N_START END=$N_END
   o script NAO reescreveu nada — com o par incompleto, a remocao do bloco apagaria ate o fim do arquivo."
fi
if [[ "$N_START" -eq 1 ]]; then
  L_START="$(grep -n 'HANDOFF:START' "$MEM" | head -1 | cut -d: -f1)"
  L_END="$(grep -n 'HANDOFF:END' "$MEM" | head -1 | cut -d: -f1)"
  [[ "$L_START" -lt "$L_END" ]] || die "marcadores HANDOFF fora de ordem em $MEM (START na linha $L_START, END na $L_END)
   o script NAO reescreveu nada."
fi

NOVO_BLOCO="$(printf '<!-- HANDOFF:START — gerado por /engineer:handoff, nao editar a mao -->\n## ⚠️ LEIA PRIMEIRO — handoff vivo\n\n**`%s`**\n\n%s\n<!-- HANDOFF:END -->\n' "$FILE" "$LINHA")"

_strip_bloco() { awk '/HANDOFF:START/{d=1;next} /HANDOFF:END/{d=0;next} !d' "$1"; }

# ── worktree temporaria: a branch nasce da main, o checkout de quem trabalha fica intocado ──
SLUG="${BASE%.md}"
HB="handoff/${SLUG}"
WT="$(mktemp -d -t handoffwt.XXXXXX 2>/dev/null || echo "/tmp/handoffwt.$$")"
rmdir "$WT" 2>/dev/null || true   # `git worktree add` exige que o destino nao exista

_limpar_wt() {
  [[ -n "${WT:-}" ]] || return 0
  git worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT" 2>/dev/null || true
  git worktree prune >/dev/null 2>&1 || true
}
trap _limpar_wt EXIT

# Re-execucao no mesmo dia reusa a branch em vez de falhar: o handoff e reescrito ate ficar bom.
if git show-ref --verify --quiet "refs/heads/${HB}"; then
  git worktree add -q "$WT" "$HB" 2>/dev/null \
    || die "nao foi possivel montar a worktree em '$WT' na branch existente '$HB'"
else
  git worktree add -q -b "$HB" "$WT" "$MAIN_REF" 2>/dev/null \
    || die "nao foi possivel criar a worktree em '$WT' a partir de $MAIN_REF"
fi

WT_MEM="$WT/$MEM"
[[ -f "$WT_MEM" ]] || die "'$MEM' nao existe na base $MAIN_REF — a branch do handoff nasceria sem o arquivo de memoria"

# ── VALIDACAO ESTRUTURAL DO BLOCO, antes de escrever ──────────────────────────
#
# O awk que remove o bloco apaga tudo entre abertura e fechamento; com o par malformado,
# apagaria da abertura ate o EOF — e o MEMORY.md e conhecimento curado de meses.
#
# O gatilho mais provavel nao e corrupcao: e o proprio arquivo CITAR o formato do bloco. A doc
# do memory-manager ensina esses marcadores, e uma destilacao que traga esse texto para o corpo
# criaria uma abertura orfa. Por isso a validacao e estrutural e acontece ANTES de qualquer
# escrita. Padrao unificado com o handoff-measure.sh: antes os dois scripts usavam expressoes
# diferentes, entao existia bloco que um enxergava e o outro nao.
N_START="$(grep -c 'HANDOFF:START' "$WT_MEM" || true)"
N_END="$(grep -c 'HANDOFF:END' "$WT_MEM" || true)"

if [[ "$N_START" -gt 1 || "$N_END" -gt 1 ]]; then
  die "estrutura invalida em $MEM: $N_START marcador(es) START e $N_END END (esperado no maximo 1 de cada)
   nada foi escrito. Deixe exatamente um par, ou nenhum."
fi
if [[ "$N_START" -ne "$N_END" ]]; then
  die "marcador HANDOFF orfao em $MEM: START=$N_START END=$N_END
   nada foi escrito — com o par incompleto, a remocao do bloco apagaria ate o fim do arquivo."
fi
if [[ "$N_START" -eq 1 ]]; then
  L_START="$(grep -n 'HANDOFF:START' "$WT_MEM" | head -1 | cut -d: -f1)"
  L_END="$(grep -n 'HANDOFF:END' "$WT_MEM" | head -1 | cut -d: -f1)"
  [[ "$L_START" -lt "$L_END" ]] || die "marcadores HANDOFF fora de ordem em $MEM (START linha $L_START, END linha $L_END)
   nada foi escrito."
fi

TMP_MEM="$(mktemp -t handoffmem.XXXXXX 2>/dev/null || echo "/tmp/handoffmem.$$")"
{ printf '%s\n' "$NOVO_BLOCO"; _strip_bloco "$WT_MEM"; } > "$TMP_MEM" \
  || { rm -f "$TMP_MEM"; die "falha ao montar o novo $MEM"; }

grep -q 'HANDOFF:START' "$TMP_MEM" || { rm -f "$TMP_MEM"; die "bloco nao foi escrito no temporario — abortado"; }

# ── BASELINE INDEPENDENTE: o corpo vem do HEAD, nao do mesmo parser ───────────
#
# A versao anterior comparava contagem de linhas usando o MESMO awk que produz o resultado.
# Isso e tautologico: se o parser apaga demais, apaga nos dois lados e a guarda nunca dispara.
# A baseline agora vem de `git show`, que nenhum bug deste script alcanca, e a verificacao e de
# CONTEUDO — toda linha nao-vazia do corpo antigo tem de sobreviver.
BASE_TMP="$(mktemp -t handoffbase.XXXXXX 2>/dev/null || echo "/tmp/handoffbase.$$")"
_limpar_tmp() { rm -f "$TMP_MEM" "$BASE_TMP" "${BASE_TMP}.s" "${TMP_MEM}.s"; }

git show "${MAIN_REF}:${MEM}" > "$BASE_TMP" 2>/dev/null \
  || { _limpar_tmp; die "nao foi possivel ler '$MEM' de $MAIN_REF para servir de baseline"; }

_strip_bloco "$BASE_TMP" | grep -v '^[[:space:]]*$' | sort > "${BASE_TMP}.s"
_strip_bloco "$TMP_MEM"  | grep -v '^[[:space:]]*$' | sort > "${TMP_MEM}.s"
PERDIDAS="$(comm -23 "${BASE_TMP}.s" "${TMP_MEM}.s" | head -5)"
N_BASE="$(grep -c . "${BASE_TMP}.s" || true)"

if [[ -n "$PERDIDAS" ]]; then
  _limpar_tmp
  die "o corpo curado de $MEM PERDERIA linhas — abortado sem escrever.
   Primeiras perdidas:
$(printf '%s\n' "$PERDIDAS" | sed 's/^/     /')
   Este script so troca o bloco do ponteiro; se o corpo mudaria, ha algo errado no arquivo."
fi

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "── dry-run: bloco que seria escrito em $MEM ──"
  printf '%s\n' "$NOVO_BLOCO"
  echo "── corpo curado verificado contra $MAIN_REF: $N_BASE linha(s), nenhuma perdida ──"
  echo "── branch que seria criada: $HB (PR contra $MAIN_NAME) ──"
  _limpar_tmp
  echo "✔ dry-run: gates 0-2 passaram; nada foi escrito, commitado nem pushado."
  exit 0
fi

# ── escrita e commit, tudo dentro da worktree ─────────────────────────────────
mkdir -p "$(dirname "$WT/$FILE")" || { _limpar_tmp; die "falha ao criar diretorio de $FILE na worktree"; }
cp "$FILE" "$WT/$FILE" || { _limpar_tmp; die "falha ao copiar o handoff para a worktree"; }
cat "$TMP_MEM" > "$WT_MEM" || { _limpar_tmp; die "falha ao gravar $MEM na worktree"; }
_limpar_tmp

# Confirmacao do gate: o NOME do arquivo dentro do bloco. Grep pelo nome, JAMAIS pela data —
# a data casa com o handoff anterior do mesmo dia e o gate passaria em falso.
awk '/HANDOFF:START/{d=1} d{print} /HANDOFF:END/{d=0}' "$WT_MEM" | grep -qF "$BASE" \
  || die "o bloco HANDOFF nao cita '$BASE' depois da escrita — nao prossiga"

# `git add` dos DOIS arquivos e de mais nada. A worktree nasceu limpa da main, entao aqui nao
# ha trabalho de terceiro para capturar por acidente.
git -C "$WT" add -- "$FILE" "$MEM" || die "git add falhou na worktree"

if git -C "$WT" diff --cached --quiet -- "$FILE" "$MEM"; then
  echo "handoff-commit: nada a commitar (arquivo e ponteiro identicos aos de $MAIN_REF)"
else
  git -C "$WT" commit -q -m "docs(handoff): ${SLUG}

${LINHA}" -- "$FILE" "$MEM" \
    || die "git commit falhou na worktree (hook de pre-commit? identidade do git ausente?)"
fi

# ── GATE 3: a branch sobe e o PR abre ─────────────────────────────────────────
REMOTE="$(git config "branch.${MAIN_NAME}.remote" 2>/dev/null)" || REMOTE=""
[[ -n "$REMOTE" ]] || REMOTE="$(git remote | head -1)"
[[ -n "$REMOTE" ]] || die "o repo nao tem remote configurado — o handoff nao tem para onde ir"

# Refspec explicito: `git push` nu sob push.default=matching publicaria outras branches locais.
git -C "$WT" push -q -u "$REMOTE" "HEAD:refs/heads/${HB}" \
  || die "git push da branch '$HB' para $REMOTE falhou — o handoff existe so localmente"

if ! git ls-remote --exit-code --heads "$REMOTE" "$HB" >/dev/null 2>&1; then
  die "a branch '$HB' nao aparece em $REMOTE apos o push — nao da para confirmar que o handoff subiu"
fi

# O arquivo foi escrito no checkout local pelo agente e copiado para a worktree. Agora que ele
# esta seguro no remote, o original local precisa SAIR — senao ele fica untracked e, no dia em
# que o PR for mergeado, o `git pull` falha com "untracked working tree files would be
# overwritten by merge". Seria uma armadilha em cada uso, e o dev pagaria por ela dias depois,
# longe da causa.
if [[ -f "$FILE" ]] && ! git ls-files --error-unmatch -- "$FILE" >/dev/null 2>&1; then
  rm -f "$FILE" && \
    echo "handoff-commit: '$FILE' removido do checkout local (ja esta na branch '$HB');" >&2 && \
    echo "handoff-commit: ele volta pelo git quando o PR for mergeado — sem isso o proximo pull falharia." >&2
fi

PR_URL=""
if [[ "$NO_PR" -eq 1 ]]; then
  echo "✔ handoff-commit: branch '$HB' pushada. PR NAO aberto (--no-pr)."
  echo "  Gate 3 fica em aberto: sem PR mergeado, o handoff nao chega em $MAIN_NAME."
  exit 0
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "✔ handoff-commit: branch '$HB' pushada, mas o PR NAO foi aberto (gh ausente no PATH)."
  echo "  Abra manualmente contra '$MAIN_NAME' — sem merge, o handoff nao fica vivo."
  exit 0
fi

PR_EXISTENTE="$(gh pr list --head "$HB" --state open --json url -q '.[0].url' 2>/dev/null || true)"
if [[ -n "$PR_EXISTENTE" && "$PR_EXISTENTE" != "null" ]]; then
  PR_URL="$PR_EXISTENTE"
  echo "handoff-commit: PR ja aberto para '$HB' — atualizado com o novo commit."
else
  if ! PR_OUT="$(gh pr create --base "$MAIN_NAME" --head "$HB" \
        --title "docs(handoff): ${SLUG}" \
        --body "${LINHA}

Handoff de sessao gerado por \`/engineer:handoff\`. Dois arquivos: o handoff e o ponteiro no \`${MEM}\`.

⚠️ **Enquanto este PR nao for mergeado, o handoff nao esta vivo** — o \`/engineer:warm-up\` le o ponteiro da ${MAIN_NAME}." 2>&1)"; then
    echo "handoff-commit: branch pushada, mas 'gh pr create' falhou: $(first_line "$PR_OUT")" >&2
    echo "  Abra o PR manualmente contra '$MAIN_NAME' — sem merge, o handoff nao fica vivo." >&2
    exit 2
  fi
  PR_URL="$(printf '%s' "$PR_OUT" | grep -Eo 'https://[^ ]+/pull/[0-9]+' | head -1)"
fi

echo "✔ handoff-commit: as tres entregas completas."
echo "   arquivo   $FILE"
echo "   ponteiro  bloco HANDOFF em $MEM (corpo conferido contra $MAIN_REF: $N_BASE linhas)"
echo "   PR        ${PR_URL:-<sem url>}"
echo
echo "⚠️  O handoff so fica VIVO quando este PR for mergeado — ate la o warm-up le o ponteiro anterior."
