#!/usr/bin/env bash
#
# gate-cortex.sh — checagens mecanicas do harness e da aplicação.
#
# Além das checagens Cortex, o gate executa os gates da aplicação TypeScript,
# schema Prisma e build. Um gate vazio não protege o modo autônomo.
#
# NAO-MUTANTE por contrato: apenas le. Sem --fix, sem --write.
# Uso: .claude/scripts/gate-cortex.sh [json|bash|frontmatter|secrets|application]
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "gate-cortex: nao e um repositorio git" >&2; exit 2; }
cd "$ROOT" || exit 2

ONLY="${1:-all}"
FAILED=0

fail() { echo "  ✖ $*"; FAILED=1; SEC_FAILED=1; }
ok()   { echo "  ✔ $*"; }

# Ignora worktrees da propria frota: sao checkouts efemeros de outras branches.
claude_files() { # $1 = padrao -name
  find .claude -path './.claude/worktrees' -prune -o -type f -name "$1" -print
}

# ---- 1. JSON parseavel ----------------------------------------------------
if [[ "$ONLY" == "all" || "$ONLY" == "json" ]]; then
  echo "> json"
  SEC_FAILED=0
  command -v python3 >/dev/null || { echo "  ✖ python3 ausente (gate fail-closed)"; exit 2; }
  n=0
  while IFS= read -r f; do
    n=$((n + 1))
    python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null \
      || fail "JSON invalido: $f"
  done < <(claude_files '*.json')
  [[ $SEC_FAILED == 0 ]] && ok "$n arquivo(s) .json validos"
fi

# ---- 2. sintaxe dos scripts ----------------------------------------------
if [[ "$ONLY" == "all" || "$ONLY" == "bash" ]]; then
  echo "> bash"
  SEC_FAILED=0
  n=0
  while IFS= read -r f; do
    n=$((n + 1))
    bash -n "$f" 2>/dev/null || fail "sintaxe bash invalida: $f"
  done < <(claude_files '*.sh')
  ok "$n script(s) .sh checados com bash -n"
  # O linter estatico e opcional: ausente = aviso, nao bloqueio (nao e universal).
  # (Nao iniciar este comentario com o nome do binario: virava diretiva SC1073.)
  if command -v shellcheck >/dev/null; then
    while IFS= read -r f; do
      shellcheck -S error -x "$f" >/dev/null 2>&1 || fail "shellcheck (severity=error): $f"
    done < <(claude_files '*.sh')
  else
    echo "  ~ shellcheck ausente — checagem estendida pulada"
  fi
fi

# ---- 3. frontmatter de agentes e skills ---------------------------------
if [[ "$ONLY" == "all" || "$ONLY" == "frontmatter" ]]; then
  echo "> frontmatter"
  SEC_FAILED=0
  n=0
  while IFS= read -r f; do
    n=$((n + 1))
    [[ "$(head -1 "$f")" == "---" ]] || { fail "sem frontmatter: $f"; continue; }
    fm="$(sed -n '2,/^---$/p' "$f")"
    grep -qE '^name:[[:space:]]*\S' <<<"$fm" || fail "frontmatter sem 'name': $f"
    grep -qE '^description:[[:space:]]*\S' <<<"$fm" || fail "frontmatter sem 'description': $f"
  done < <(find .claude/agents -type f -name '*.md' 2>/dev/null
           find .claude/skills -type f -name 'SKILL.md' 2>/dev/null)
  [[ $SEC_FAILED == 0 ]] && ok "$n agente(s)/skill(s) com frontmatter completo"
fi

# ---- 4. segredos hardcoded ----------------------------------------------
# Este repo ja teve uma API key da Linear commitada em texto plano num comando.
# O gate existe para que a proxima nao chegue ao PR.
if [[ "$ONLY" == "all" || "$ONLY" == "secrets" ]]; then
  echo "> secrets"
  SEC_FAILED=0
  pattern='(sk-[A-Za-z0-9]{20,}|gh[pous]_[A-Za-z0-9]{30,}|lin_api_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
  hits="$(grep -rIn --exclude-dir=worktrees -E "$pattern" .claude 2>/dev/null \
          | grep -v 'gate-cortex.sh' || true)"
  if [[ -n "$hits" ]]; then
    while IFS= read -r line; do fail "possivel segredo: ${line%%:*}"; done <<<"$hits"
  else
    ok "nenhum segredo hardcoded detectado"
  fi
fi

# ---- 5. aplicação TypeScript ---------------------------------------------
if [[ "$ONLY" == "all" || "$ONLY" == "application" ]]; then
  echo "> application"
  if [[ ! -f package.json ]]; then
    fail "package.json ausente"
  else
    npm test || fail "npm test"
    npm run typecheck || fail "npm run typecheck"
    npm run lint || fail "npm run lint"
    DATABASE_URL="postgresql://gate:gate@127.0.0.1:5432/gate" \
      SHADOW_DATABASE_URL="postgresql://gate:gate@127.0.0.1:5432/gate_shadow" \
      npx --no-install prisma validate || fail "prisma validate"
    npm run build || fail "npm run build"
  fi
fi

# ---- 6. infraestrutura Terraform -----------------------------------------
# Existe porque o apply do Terraform e MANUAL: sem isto, erro de sintaxe ou de
# formatacao so apareceria com o terminal ja apontando para producao. O CI roda
# o mesmo par (quality.yml, job `terraform`); aqui e para pegar antes do push.
# Nenhuma credencial e usada -- `fmt` e `validate` sao offline.
if [[ "$ONLY" == "all" || "$ONLY" == "terraform" ]]; then
  echo "> terraform"
  if [[ ! -d infra ]]; then
    ok "sem diretorio infra/ -- nada a checar"
  elif ! command -v terraform >/dev/null 2>&1; then
    ok "terraform nao instalado -- checagem pulada (o CI cobre)"
  else
    terraform fmt -check -recursive infra/ || fail "terraform fmt (rode: terraform fmt -recursive infra/)"
    for raiz in infra/bootstrap infra/envs/*/; do
      [[ -d "$raiz" ]] || continue
      # `validate` exige init; sem .terraform local, so o CI valida essa raiz.
      if [[ -d "$raiz/.terraform" ]]; then
        terraform -chdir="$raiz" validate || fail "terraform validate ($raiz)"
      fi
    done
  fi
fi

if [[ $FAILED != 0 ]]; then
  echo "✖ gate-cortex: reprovado"
  exit 1
fi
echo "✔ gate-cortex: aprovado"
