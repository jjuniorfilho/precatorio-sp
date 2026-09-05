#!/usr/bin/env bash
#
# handoff-smoke-test.sh — /engineer:handoff · testes de comportamento zero-dependencia
#
# Valida os branches comportamentais de handoff-measure.sh e handoff-commit.sh. Sem
# dependencias externas — apenas bash, git e mktemp. Seguro em CI ou pre-PR.
# (`bats-core` permanece rejeitado: viola a filosofia zero-dependencia do projeto.)
#
# Filosofia: cada caso monta um sandbox em /tmp, roda o alvo e verifica saida + exit code.
# Nenhum estado persiste entre casos.
#
# HIGIENE E CASO DE TESTE, NAO RECOMENDACAO. A suite termina verificando que a arvore real
# do repo seguiu limpa. Isso existe porque aconteceu: um harness com `d=$(mk)` — substituicao
# de comando abre subshell, e o `cd` nao propaga — rodou os casos DENTRO do repo e sobrescreveu
# o MEMORY.md (177 linhas de conhecimento curado viraram 4 de lixo), criou docs/handoffs/,
# 4 commits vazios e uma worktree fantasma. Por isso `mk()` altera o diretorio do shell atual
# e e chamada como comando, nunca como `$(mk)`.
#
# Uso:
#   bash .claude/scripts/handoff-smoke-test.sh            # tudo
#   bash .claude/scripts/handoff-smoke-test.sh measure    # so o measure
#   bash .claude/scripts/handoff-smoke-test.sh commit     # so o commit
#
set -uo pipefail

SUITE="${1:-all}"   # measure | commit | all
case "$SUITE" in
  measure|commit|all) ;;
  *) echo "handoff-smoke-test: suite invalida '$SUITE' (use measure|commit|all)" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
M="$SCRIPT_DIR/handoff-measure.sh"
SC="$SCRIPT_DIR"
REAL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

PASS=0; FAIL=0
GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'
_ok()   { PASS=$((PASS+1)); printf "${GREEN}  PASS${NC} %s\n" "$1"; }
_bad()  { FAIL=$((FAIL+1)); printf "${RED}  FAIL${NC} %s\n" "$1"; [[ -n "${2:-}" ]] && printf "       esperava /%s/\n" "$2"; }
chk()   { if printf '%s' "$3" | grep -qE "$2"; then _ok "$1"; else _bad "$1" "$2"; fi; }
nchk()  { if printf '%s' "$3" | grep -qE "$2"; then _bad "$1 (proibido /$2/)"; else _ok "$1"; fi; }
rc_is() { if [ "$2" = "$3" ]; then _ok "$1 (exit $3)"; else _bad "$1 (exit $2, esperado $3)"; fi; }

# NAO usar `d=$(mk)`: subshell, o `cd` nao propaga, e os casos rodam na arvore real.
mk() { D="$(mktemp -d)"; cd "$D" || exit 1; git init -q -b main .; git config user.email t@t; git config user.name t; }

mkrepo() {
  BARE="$(mktemp -d)/bare.git"; git init -q --bare -b main "$BARE"
  D="$(mktemp -d)"; cd "$D" || exit 1
  git init -q -b main .; git config user.email t@t; git config user.name t
  mkdir -p .claude/memory docs/handoffs .claude/scripts
  cp "$SC/_handoff-lib.sh" "$SC/handoff-commit.sh" "$SC/handoff-measure.sh" .claude/scripts/
  { echo "# Project Memory"; echo; for i in $(seq 1 40); do echo "linha curada $i"; done; } > .claude/memory/MEMORY.md
  git add -A; git commit -qm init
  git remote add origin "$BARE"; git push -q -u origin main
}
H() { bash .claude/scripts/handoff-commit.sh "$@" 2>&1; }

if [[ "$SUITE" == "measure" || "$SUITE" == "all" ]]; then
echo "== C3/#1: worktree prunable nao pode sumir da contagem =="
mk; git commit -q --allow-empty -m init
git worktree add "$D/wt-gone" -b feature-gone -q 2>/dev/null
(cd "$D/wt-gone" && touch g && git add g && git commit -qm "trabalho importante")
mv "$D/wt-gone" "$D/wt-gone-MOVED"
out=$(bash "$M" 2>&1)
chk "reporta medicao PARCIAL" "NAO MEDIDO.*PARCIAL" "$out"
chk "cita worktree prunable"  "prunable" "$out"

echo "== #2: repo sem commits — cabecalho em UMA linha =="
mk; out=$(bash "$M" 2>&1)
chk "cabecalho de UMA linha" "^data=.*arvore_suja" "$out"
nchk "sem newline no meio"   "branch=HEAD$" "$out"

echo "== C5/#3: HANDOFF_DIR inexistente nao pode virar 'coerente' =="
mk; git commit -q --allow-empty -m init
mkdir -p .claude/memory
printf 'x\n<!-- HANDOFF:START -->\nVer docs/handoffs/2026-07-30-algo.md\n<!-- HANDOFF:END -->\n' > .claude/memory/MEMORY.md
out=$(bash "$M" 2>&1)
nchk "nao afirma coerencia"  "ponteiro coerente" "$out"
chk  "diz que dir nao existe" "HANDOFF_DIR.*nao existe" "$out"

echo "== M7/#4: ponteiro com espaco / sem diretorio nao gera falso defeito (a) =="
mk; git commit -q --allow-empty -m init
mkdir -p docs/handoffs .claude/memory
echo x > "docs/handoffs/2026-07-31-sessao com espaco.md"
printf 'x\n<!-- HANDOFF:START -->\nHandoff vivo: `docs/handoffs/2026-07-31-sessao com espaco.md`\n<!-- HANDOFF:END -->\n' > .claude/memory/MEMORY.md
out=$(bash "$M" 2>&1)
nchk "nao acusa defeito (a)" "NAO cita nenhum arquivo" "$out"
chk  "reconhece coerencia"   "ponteiro coerente" "$out"

echo "== C2: clone com origin/HEAD mas sem branch main local =="
mk; git commit -q --allow-empty -m init; up="$D"
c="$(mktemp -d)"; git clone -q "$up" "$c/clone"; cd "$c/clone" || exit 1
git checkout -q -b develop; git branch -q -D main 2>/dev/null
git worktree add "$D/wt" -b trabalho -q 2>/dev/null
(cd "$D/wt" && touch f && git add f && git commit -qm "commit nao mergeado")
out=$(bash "$M" 2>&1)
nchk "nao declara vazio o que esta cheio" "nenhuma worktree com commit nao-mergeado" "$out"
chk  "acha a worktree"                    "worktree\(s\) com trabalho nao-mergeado" "$out"

echo "== C2b: HANDOFF_MAIN_BRANCH com typo =="
out=$(HANDOFF_MAIN_BRANCH=mian bash "$M" 2>&1)
chk  "avisa que nao resolve" "nao resolve nem local nem em origin" "$out"
nchk "nao imprime commits=?" "commits=\?" "$out"

echo "== C4: upstream registrado mas remote-tracking podado =="
mk; git commit -q --allow-empty -m init
B="$(mktemp -d)/b.git"; git init -q --bare -b main "$B"
git remote add origin "$B"; git push -q -u origin main
git update-ref -d refs/remotes/origin/main    # tracking podado, config de upstream intacta
out=$(bash "$M" 2>&1)
nchk "nao imprime MEDIDO com ?" "MEDIDO.*\? commit" "$out"
chk  "diz que o upstream nao resolve" "(nao resolve|nao tem upstream)" "$out"

echo "== C6: config quebrada degrada, nao mata o script =="
mk; git commit -q --allow-empty -m init
mkdir -p .claude; printf 'HANDOFF_DIR="$NAO_DEFINIDA/x"\n' > .claude/handoff.config.sh
out=$(bash "$M" 2>&1); rc=$?
chk "script completou"      "fim — secoes NAO MEDIDO" "$out"
[ "$rc" = "0" ] && { echo "  PASS  exit 0"; PASS=$((PASS+1)); } || { echo "  FAIL  exit=$rc"; FAIL=$((FAIL+1)); }

echo "== C6b: config com erro de sintaxe =="
printf 'HANDOFF_BOUNDARY_PATHS=(\n' > .claude/handoff.config.sh
out=$(bash "$M" 2>&1)
chk "avisa config invalida" "AVISO.*(NAO completou|SINTAXE|sintaxe)" "$out"

echo "== ponteiro pendurado (arquivo apontado nao existe) =="
mk; git commit -q --allow-empty -m init
mkdir -p docs/handoffs .claude/memory; echo x > docs/handoffs/2026-07-31-novo.md
printf '<!-- HANDOFF:START -->\ndocs/handoffs/2026-07-01-sumiu.md\n<!-- HANDOFF:END -->\n' > .claude/memory/MEMORY.md
out=$(bash "$M" 2>&1)
chk "detecta pendurado" "ponteiro PENDURADO" "$out"

echo "== R1: ponteiro correto + outro .md citado na mesma linha =="
mk; git commit -q --allow-empty -m init
mkdir -p docs/handoffs .claude/memory
echo x > docs/handoffs/2026-07-31-novo.md; echo y > docs/handoffs/2026-07-29-velho.md
printf '<!-- HANDOFF:START -->\nLEIA: `docs/handoffs/2026-07-31-novo.md` (substitui o 2026-07-29-velho.md)\n<!-- HANDOFF:END -->\n' > .claude/memory/MEMORY.md
out=$(bash "$M" 2>&1)
nchk "nao acusa PENDURADO"  "PENDURADO" "$out"
chk  "reconhece coerente"   "ponteiro coerente" "$out"

echo "== R2: config com exit nao pode zerar a saida =="
mk; git commit -q --allow-empty -m init; mkdir -p .claude
printf 'HANDOFF_DIR="docs/handoffs"\nexit 1\n' > .claude/handoff.config.sh
out=$(bash "$M" 2>&1)
chk "script completou"   "fim — secoes NAO MEDIDO" "$out"
chk "avisa que nao completou" "AVISO.*NAO completou" "$out"

echo "== R3: main local atras de origin/main nao pode dar gap zero =="
mk; git commit -q --allow-empty -m base; up="$D"
c="$(mktemp -d)"; git clone -q "$up" "$c/cl"; cd "$up" || exit 1
git tag prod HEAD
for i in 1 2 3 4 5; do git commit -q --allow-empty -m "commit $i"; done
cd "$c/cl" || exit 1; git fetch -q origin; mkdir -p .claude
printf 'HANDOFF_PROD_REF="refs/tags/prod"\n' > .claude/handoff.config.sh
git fetch -q origin 'refs/tags/*:refs/tags/*'
out=$(bash "$M" 2>&1)
nchk "nao afirma gap zero" "commits=0" "$out"
chk  "avisa atraso local"  "AVISO.*atras de origin" "$out"

echo "== R4: branch orfa (sem merge base) nao pode dar arquivos=0 =="
mk; git commit -q --allow-empty -m init; echo a > a.txt; git add a.txt; git commit -qm a
git worktree add -q "$D/wo" --detach 2>/dev/null
(cd "$D/wo" && git checkout -q --orphan orfa && rm -f a.txt && echo z > z1.txt && echo z > z2.txt && git add -A && git commit -qm "orfao")
out=$(bash "$M" 2>&1)
chk  "cenario montado (achou a worktree orfa)" "worktree\(s\) com trabalho nao-mergeado" "$out"
nchk "nao imprime arquivos=0 falso" "arquivos=0" "$out"

echo "== R5 + Bug A: um veredito por secao; path nao-adotado nao vira acusacao =="
mk; git commit -q --allow-empty -m base; git tag prod HEAD
mkdir -p migrations infra; echo s > migrations/001.sql; echo t > infra/main.tf
git add -A; git commit -qm "infra e migration"
mkdir -p .claude
printf 'HANDOFF_PROD_REF="refs/tags/prod"\nHANDOFF_BOUNDARY_PATHS=("migrations" "charts/")\n' > .claude/handoff.config.sh
out=$(bash "$M" 2>&1)
fr=$(printf '%s' "$out" | sed -n '/## FRONTEIRA_TOCADA/,/^## /p')
chk  "tem MEDIDO"                 "MEDIDO" "$fr"
nchk "nao tem NAO MEDIDO junto"   "NAO MEDIDO" "$fr"
nchk "nao acusa typo"             "typo na config faz" "$fr"
chk  "cita fora de cobertura"     "fora da cobertura" "$fr"

echo "== R8: git worktree list falhando nao pode virar 'nenhuma worktree' =="
mk; git commit -q --allow-empty -m init
# forca falha da listagem apontando GIT_DIR para lugar invalido nao serve (mataria tudo);
# valida-se o caminho feliz + presenca da guarda no codigo
chk "guarda existe no codigo" "git worktree list falhou" "$(cat "$M")"

fi

if [[ "$SUITE" == "commit" || "$SUITE" == "all" ]]; then
echo "== GATE 0: recusa fora da main =="
mkrepo; echo conteudo > docs/handoffs/2026-07-31-teste.md
git checkout -q -b feature/x
out=$(H --file docs/handoffs/2026-07-31-teste.md --linha "x" --no-pr); rc=$?
rc_is "sai 2" "$rc" 2
chk "explica e instrui" "handoff se baseia em 'main'" "$out"
git checkout -q main

echo "== GATE 1: arquivo ausente / vazio / fora do padrao =="
out=$(H --file docs/handoffs/nao-existe-2026-01-01.md --linha "x" --no-pr); rc=$?
rc_is "ausente sai 2" "$rc" 2
: > docs/handoffs/2026-07-31-vazio.md
out=$(H --file docs/handoffs/2026-07-31-vazio.md --linha "x" --no-pr)
chk "detecta vazio" "esta VAZIO" "$out"
echo x > docs/handoffs/semdata.md
out=$(H --file docs/handoffs/semdata.md --linha "x" --no-pr)
chk "exige padrao de data" "fora do padrao" "$out"

echo "== argumentos: valor faltando nao pode dar erro criptico =="
out=$(H --file); rc=$?
chk "avisa --file sem valor" "exige um valor" "$out"
nchk "sem unbound variable" "unbound variable" "$out"

echo "== GATE 2 + 3: caminho feliz completo =="
out=$(H --file docs/handoffs/2026-07-31-teste.md --linha "o que so existe aqui" --no-pr); rc=$?
rc_is "sai 0" "$rc" 0
chk "reporta a branch pushada" "branch .handoff/2026-07-31-teste. pushada" "$out"
mem=$(git show "handoff/2026-07-31-teste:.claude/memory/MEMORY.md" 2>/dev/null)
chk "ponteiro cita o arquivo" "2026-07-31-teste\.md" "$mem"
chk "corpo curado preservado"  "linha curada 40" "$mem"
chk "bloco no topo"            "^<!-- HANDOFF:START" "$mem"
# a branch do handoff subiu, e a main NAO foi tocada
if git ls-remote --exit-code --heads origin "handoff/2026-07-31-teste" >/dev/null 2>&1; then _ok "branch handoff/* pushada"; else _bad "branch nao chegou no remote"; fi
if [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]; then _ok "main intocada (sem push direto)"; else _bad "a main foi alterada"; fi
versionado="$(git status --porcelain | grep -v '^??' || true)"
if [ -z "$versionado" ]; then _ok "nenhum arquivo versionado alterado no checkout"; else _bad "alterou versionado: $versionado"; fi

echo "== idempotencia: rodar 2x nao duplica bloco nem acumula ponteiro =="
out=$(H --file docs/handoffs/2026-07-31-teste.md --linha "o que so existe aqui" --no-pr)
n=$(git show "handoff/2026-07-31-teste:.claude/memory/MEMORY.md" 2>/dev/null | grep -c 'HANDOFF:START' || echo 0)
if [ "$n" = "1" ]; then _ok "um unico bloco"; else _bad "$n blocos"; fi

echo "== substituicao: handoff novo troca o ponteiro, nao acumula =="
echo novo > docs/handoffs/2026-08-01-novo.md
out=$(H --file docs/handoffs/2026-08-01-novo.md --linha "agora e este" --no-pr)
mem=$(git show "handoff/2026-08-01-novo:.claude/memory/MEMORY.md" 2>/dev/null)
chk  "aponta para o novo"       "2026-08-01-novo\.md" "$mem"
nchk "nao cita mais o antigo"   "2026-07-31-teste\.md" "$mem"
chk  "corpo ainda preservado"   "linha curada 40" "$mem"
n=$(printf '%s' "$mem" | grep -c 'HANDOFF:START' || echo 0)
if [ "$n" = "1" ]; then _ok "segue com um bloco"; else _bad "$n blocos"; fi

echo "== ate o merge, a main NAO tem o ponteiro novo (por desenho) =="
out=$(bash .claude/scripts/handoff-measure.sh 2>&1 | sed -n '/HANDOFF_VIVO/,$p')
nchk "ponteiro da main ainda nao aponta para o novo" "ponteiro coerente com o handoff mais recente: 2026-08-01-novo" "$out"
if [ ! -f docs/handoffs/2026-08-01-novo.md ]; then _ok "arquivo local removido (pull futuro nao quebra)"; else _bad "arquivo ficou untracked — o merge do PR falharia"; fi
# e o merge do PR faz o ponteiro valer
git merge -q --no-edit "handoff/2026-08-01-novo"
out=$(bash .claude/scripts/handoff-measure.sh 2>&1 | sed -n '/HANDOFF_VIVO/,$p')
chk "apos o merge, ponteiro coerente" "ponteiro coerente" "$out"

echo "== git add NAO captura arquivo de terceiro =="
echo "trabalho alheio" > outro.txt; git add outro.txt
echo mais > docs/handoffs/2026-08-02-outro.md
out=$(H --file docs/handoffs/2026-08-02-outro.md --linha "terceiro" --no-pr)
st=$(git status --porcelain outro.txt)
chk "outro.txt continua fora do commit" "^A  outro\.txt" "$st"

echo "== --dry-run nao escreve nem commita =="
mkrepo; echo c > docs/handoffs/2026-07-31-dry.md
antes=$(md5 -q .claude/memory/MEMORY.md 2>/dev/null || md5sum .claude/memory/MEMORY.md)
out=$(H --file docs/handoffs/2026-07-31-dry.md --linha "x" --dry-run); rc=$?
rc_is "dry-run sai 0" "$rc" 0
depois=$(md5 -q .claude/memory/MEMORY.md 2>/dev/null || md5sum .claude/memory/MEMORY.md)
[ "$antes" = "$depois" ] && { echo "  PASS  MEMORY.md intacto"; PASS=$((PASS+1)); } || { echo "  FAIL  MEMORY.md mudou"; FAIL=$((FAIL+1)); }

echo "== charset: path com caractere fora da allowlist =="
out=$(H --file "docs/handoffs/2026-07-31-com espaco.md" --linha "x")
chk "recusa caractere invalido" "fora de" "$out"


echo "== C1: bloco malformado NAO pode reescrever o arquivo =="
mkrepo; echo conteudo > docs/handoffs/2026-07-31-c1.md
# END com formatacao diferente: o awk antigo apagaria daqui ate o EOF
{ echo "<!-- HANDOFF:START -->"; echo "ponteiro velho sem fechamento"; cat .claude/memory/MEMORY.md; } > m.tmp && mv m.tmp .claude/memory/MEMORY.md
git add -A; git commit -qm "memoria com START orfao"
antes=$(grep -c . .claude/memory/MEMORY.md)
out=$(H --file docs/handoffs/2026-07-31-c1.md --linha "x" --no-pr); rc=$?
depois=$(grep -c . .claude/memory/MEMORY.md)
rc_is "recusa START orfao" "$rc" 2
if [ "$antes" = "$depois" ]; then _ok "arquivo intocado ($antes linhas)"; else _bad "arquivo mudou: $antes -> $depois"; fi

echo "== C1b: corpo CITANDO o marcador (o caso que a doc do memory-manager cria) =="
mkrepo; echo conteudo > docs/handoffs/2026-07-31-c1b.md
{ echo "# Project Memory"; echo; echo "Regra: nunca editar entre <!-- HANDOFF:START --> e <!-- HANDOFF:END -->."; for i in $(seq 1 20); do echo "curada $i"; done; } > .claude/memory/MEMORY.md
git add -A; git commit -qm "memoria citando o formato"
antes=$(grep -c . .claude/memory/MEMORY.md)
out=$(H --file docs/handoffs/2026-07-31-c1b.md --linha "x" --no-pr); rc=$?
depois=$(grep -c . .claude/memory/MEMORY.md)
if [ "$antes" = "$depois" ]; then _ok "corpo preservado ($antes linhas)"; else _bad "corpo perdido: $antes -> $depois"; fi
rc_is "recusa (rc)" "$rc" 2
nchk "nao afirma sucesso" "tres entregas completas" "$out"

echo "== C3: alteracao alheia local NAO viaja para o PR (worktree isola) =="
mkrepo; echo c > docs/handoffs/2026-07-31-c3.md
echo "DESTILACAO NAO REVISADA" >> .claude/memory/MEMORY.md
out=$(H --file docs/handoffs/2026-07-31-c3.md --linha "x" --no-pr); rc=$?
rc_is "conclui mesmo com MEMORY.md local sujo" "$rc" 0
chk "avisa que a alteracao local fica de fora" "NAO entra no PR" "$out"
wtmem=$(git show "handoff/2026-07-31-c3:.claude/memory/MEMORY.md" 2>/dev/null)
nchk "destilacao alheia NAO viajou" "DESTILACAO NAO REVISADA" "$wtmem"

echo "== M5: merge em andamento bloqueia antes de escrever =="
mkrepo; echo c > docs/handoffs/2026-07-31-m5.md
git checkout -q -b outra; echo x > conflito.txt; git add -A; git commit -qm "lado A"
git checkout -q main; echo y > conflito.txt; git add -A; git commit -qm "lado B"
git merge outra -q >/dev/null 2>&1 || true
antes=$(grep -c . .claude/memory/MEMORY.md)
out=$(H --file docs/handoffs/2026-07-31-m5.md --linha "x" --no-pr); rc=$?
rc_is "recusa durante merge" "$rc" 2
depois=$(grep -c . .claude/memory/MEMORY.md)
if [ "$antes" = "$depois" ]; then _ok "nao escreveu durante o merge"; else _bad "escreveu: $antes -> $depois"; fi
git merge --abort >/dev/null 2>&1 || true

echo "== M4: push nao pode publicar outras branches =="
mkrepo
git config push.default matching
git checkout -q -b wip-secreta; echo s > s.txt; git add -A; git commit -qm "wip"; git push -q origin wip-secreta
echo "mais wip" >> s.txt; git add -A; git commit -qm "wip nao publicado"
sha_local=$(git rev-parse wip-secreta)
git checkout -q main
echo c > docs/handoffs/2026-07-31-m4.md
out=$(H --file docs/handoffs/2026-07-31-m4.md --linha "x" --no-pr); rc=$?
rc_is "cenario montado (handoff concluiu)" "$rc" 0
sha_remoto=$(git ls-remote origin refs/heads/wip-secreta | cut -f1)
if [ "$sha_local" != "$sha_remoto" ]; then _ok "wip-secreta NAO foi publicada junto"; else _bad "push carregou outra branch"; fi

echo "== commit toca exatamente 2 arquivos =="
n=$(git show --name-only --format= "handoff/2026-07-31-m4" 2>/dev/null | grep -c . || echo 0)
if [ "$n" = "2" ]; then _ok "commit com exatamente 2 arquivos"; else _bad "commit com $n arquivos"; fi

echo "== falha no commit nao suja o checkout local (worktree isola) =="
mkrepo; echo c > docs/handoffs/2026-07-31-rb.md
mkdir -p .git/hooks; printf '#!/bin/sh\nexit 1\n' > .git/hooks/pre-commit; chmod +x .git/hooks/pre-commit
out=$(H --file docs/handoffs/2026-07-31-rb.md --linha "x" --no-pr); rc=$?
rc_is "falha no commit" "$rc" 2
st=$(git status --porcelain -- .claude/memory/MEMORY.md)
if [ -z "$st" ]; then _ok "MEMORY.md local intocado"; else _bad "sujou: $st"; fi
rm -f .git/hooks/pre-commit
out=$(H --file docs/handoffs/2026-07-31-rb.md --linha "x" --no-pr); rc=$?
rc_is "retry conclui" "$rc" 0
if [ -z "$(git worktree list | grep -c handoffwt || true)" ] || [ "$(git worktree list | grep -c handoffwt || true)" = "0" ]; then _ok "worktree temporaria removida"; else _bad "worktree vazou"; fi

echo "== --no-pr pusha a branch e para =="
mkrepo; echo c > docs/handoffs/2026-07-31-np.md
out=$(H --file docs/handoffs/2026-07-31-np.md --linha "x" --no-pr); rc=$?
rc_is "sai 0" "$rc" 0
chk "avisa gate 3 em aberto" "Gate 3 fica em aberto" "$out"
chk "diz que a branch subiu" "pushada" "$out"
if gh --version >/dev/null 2>&1; then _ok "(--no-pr: PR nao aberto por contrato)"; else _ok "(--no-pr)"; fi
fi

# ── higiene: a suite nao pode ter tocado a arvore real ────────────────────────
echo "== higiene: arvore real intocada =="
real="$(git -C "$REAL_ROOT" status --porcelain 2>/dev/null)"
nchk "MEMORY.md real intacto"  "^ M \.claude/memory/MEMORY\.md" "$real"
nchk "sem docs/handoffs de teste" "^\?\? docs/handoffs" "$real"
wt="$(git -C "$REAL_ROOT" worktree list 2>/dev/null | grep -c . || true)"
if [ "$wt" = "1" ]; then _ok "so a worktree principal"; else _bad "$wt worktrees registradas"; fi

echo
printf "Resultado: ${GREEN}%d PASS${NC}  ${RED}%d FAIL${NC}\n" "$PASS" "$FAIL"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
