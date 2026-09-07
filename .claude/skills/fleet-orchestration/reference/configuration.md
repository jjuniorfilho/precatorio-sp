# Fleet — config layer (`.claude/fleet.config.sh`)

Os scripts do Fleet sao **stack-agnosticos**. Tudo que e especifico do projeto
(como instalar deps, isolar dados, quais gates rodar) e declarado em um arquivo
**opcional** `.claude/fleet.config.sh`, carregado por `fleet-provision.sh`,
`fleet-gate.sh` e `fleet-teardown.sh`.

**Sem config, o Fleet funciona com defaults** (auto-detect de package manager e de
lint/test). Copie o template para comecar:

```bash
cp .claude/skills/fleet-orchestration/fleet.config.example.sh .claude/fleet.config.sh
```

> `.claude/fleet.config.sh` e por-projeto e pode conter caminhos locais — avalie
> adiciona-lo ao `.gitignore` se contiver segredos. O template (`*.example.sh`) e
> versionado; o config efetivo e decisao do projeto.

## Variaveis e hooks

Todos sao opcionais. Os scripts aplicam defaults quando ausentes.

| Nome | Tipo | Default | Funcao |
|---|---|---|---|
| `FLEET_BASE_REF` | var | `origin/main` | ref base para criar branches das worktrees |
| `FLEET_BRANCH_PREFIX` | var | git user.name (slug) | prefixo da branch: `<prefix>/<worktree-name>` |
| `FLEET_WORKTREE_DIR` | var | `.claude/worktrees` | onde as worktrees sao criadas |
| `FLEET_INSTALL_CMD` | var | auto-detect | comando de instalacao de deps; vazio = detecta lockfile (pnpm/yarn/bun/npm) |
| `FLEET_GATE_CMDS` | array | auto-detect | gates a rodar: `("label:comando" …)`; vazio = detecta lint/test do `package.json` |
| `fleet_provision_data` | funcao | no-op | provisiona dados isolados (ex.: `createdb` + migrate). Recebe `$1=WT_NAME $2=WT_DIR $3=SHORT_ID` |
| `fleet_teardown_data` | funcao | no-op | remove dados isolados (ex.: `dropdb`). Recebe os mesmos args |

`FLEET_GATE_SCOPE` (env, nao na config) filtra quais gates rodam numa execucao: ex.
`FLEET_GATE_SCOPE=lint,test` ou `FLEET_GATE_SCOPE=lint` para feedback rapido. Os labels
correspondem aos `label:` de `FLEET_GATE_CMDS` (ou `lint`/`test` no modo auto-detect).

> **Notas sobre `FLEET_GATE_CMDS`:**
> - E um array bash — so funciona via `fleet.config.sh` (sourced). Nao da para passar por
>   prefixo de env (`FLEET_GATE_CMDS=(...) fleet-gate.sh` nao tem efeito).
> - Cada comando roda num `bash -c` novo: herda cwd e env exportado, mas NAO funcoes nem
>   variaveis nao-exportadas da config. Comandos de gate devem ser self-contained
>   (binarios no PATH funcionam; helpers definidos na config, nao).
> - Use labels simples (`[a-z0-9_-]`); `/` no label e sanitizado no nome do arquivo de log.

## Exemplo A — projeto Node simples (sem dados isolados)

Muitos projetos nem precisam de config: o auto-detect cobre npm/pnpm/yarn/bun e os
scripts `lint`/`test` do `package.json`. Um config minimo so para fixar a base:

```bash
# .claude/fleet.config.sh
FLEET_BASE_REF="origin/main"
# FLEET_INSTALL_CMD vazio  → auto-detect (ex.: "npm ci")
# FLEET_GATE_CMDS vazio    → auto-detect ("npm run lint", "npm test")
```

## Exemplo B — monorepo com banco isolado por worktree (estilo px-agents)

```bash
# .claude/fleet.config.sh
FLEET_BASE_REF="origin/main"
FLEET_WORKTREE_DIR=".claude/worktrees"

# Deps: pnpm + prisma client por worktree
FLEET_INSTALL_CMD="pnpm install --frozen-lockfile && pnpm prisma generate --schema=libs/database/prisma/schema.prisma"

# Gates: RLS custom + nx affected
FLEET_GATE_CMDS=(
  "rls:./scripts/check-migration-rls.sh"
  "lint:pnpm nx affected -t lint --base=origin/main --head=HEAD"
  "test:pnpm nx affected -t test --base=origin/main --head=HEAD"
)

# Database Postgres isolado por worktree (compartilha o servidor, isola o schema)
PG_HOST="${FLEET_PG_HOST:-localhost}"; PG_PORT="${FLEET_PG_PORT:-5434}"
PG_USER="${FLEET_PG_USER:-dev}"; PG_PASS="${FLEET_PG_PASS:-dev}"

fleet_provision_data() {
  local wt_name="$1" wt_dir="$2" short_id="$3"
  local db="app_${short_id}"
  local url="postgresql://${PG_USER}:${PG_PASS}@${PG_HOST}:${PG_PORT}/${db}"
  export PGPASSWORD="$PG_PASS"
  psql -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${db}'" postgres | grep -q 1 \
    || createdb -h "$PG_HOST" -p "$PG_PORT" -U "$PG_USER" "$db"
  printf 'DATABASE_URL="%s"\n' "$url" >> "$wt_dir/.env.fleet"
  ( cd "$wt_dir" && DATABASE_URL="$url" pnpm prisma migrate deploy \
      --schema=libs/database/prisma/schema.prisma )
}

fleet_teardown_data() {
  local short_id="$3"
  export PGPASSWORD="${FLEET_PG_PASS:-dev}"
  dropdb -h "${FLEET_PG_HOST:-localhost}" -p "${FLEET_PG_PORT:-5434}" \
    -U "${FLEET_PG_USER:-dev}" --if-exists "app_${short_id}"
}
```

> Este exemplo reproduz, via config layer, exatamente o comportamento que era hardcoded
> no projeto de origem — agora sem nenhum codigo project-specific nos scripts core
> (Regra Critica 12).

---

## Comandos de gate devem ser NAO-MUTANTES

O `FLEET_GATE_CMDS` roda comandos de **checagem**. Um comando que reescreve arquivos
transforma o gate num pe-de-cabra silencioso:

```bash
# ⛔ ERRADO — muta a arvore que o gate esta julgando
FLEET_GATE_CMDS=("lint:npm run lint")      # se o script tem `eslint --fix`

# ✔ CERTO — checa e reporta
FLEET_GATE_CMDS=("lint:npm run lint:check")  # `eslint` sem --fix
```

Armadilhas comuns: `eslint --fix`, `prettier --write`, `ruff --fix`, `gofmt -w`,
`black` (sem `--check`), `cargo fmt` (sem `--check`).

**Por que o framework recusa em vez de so avisar.** O gate e a ultima coisa antes do commit,
entao conferir `git status` depois dele e justamente o habito que ninguem tem: a mudanca de
terceiro entra no commit de quem estava trabalhando. E fere o contrato do gate — um comando que
altera o objeto medido nao e fail-closed, porque pode transformar vermelho em verde escrevendo
no codigo.

Desde a v3.13.0 o `fleet-gate.sh` compara o estado da arvore antes e depois de cada comando e
**sai com codigo 2** se algo mudou, listando o delta. Se a mutacao for deliberada:

```bash
FLEET_GATE_ALLOW_MUTATION=1   # avisa em destaque, mas nao bloqueia
```

## Gate sobre projeto legado: baseline por assinatura

Gate fail-closed que exige **zero** erros nunca fica verde num projeto legado — e um gate que
nunca fica verde e desligado no primeiro dia. O padrao que funciona e comparar contra uma
**baseline por assinatura** (arquivo + codigo do erro), falhando so no que e NOVO:

```bash
# package.json
"type-check:baseline": "node scripts/typecheck-baseline.js"
```

```bash
FLEET_GATE_CMDS=("typecheck:npm run type-check:baseline")
```

O wrapper roda o type-check real, normaliza cada erro para `<arquivo>:<codigo>`, e compara com
uma baseline versionada. Erro que ja existia passa; erro novo bloqueia. A baseline encolhe
conforme a divida e paga, e o gate nunca fica frouxo.

> Observado num consumidor em 2026-07-31: com esse wrapper, o gate da frota ficou **mais
> rigoroso que o CI do proprio repositorio**, que rodava um `tsc --noEmit` no-op porque o
> `tsconfig.json` tinha `files: []`. O gate pegou o que o CI nao via.

## Onde ficam os logs do gate

`/tmp/fleet-gate-<worktree>-<label>.log`, um por worktree — worktrees diferentes (ou projetos
diferentes na mesma maquina) nunca compartilham arquivo. Cada log abre com worktree, branch,
commit e horario.

Fica em `/tmp` de proposito, e nao dentro da worktree: post-mortem de gate acontece **depois**
do teardown. Para mudar o diretorio: `FLEET_GATE_LOG_DIR=/outro/caminho`.
