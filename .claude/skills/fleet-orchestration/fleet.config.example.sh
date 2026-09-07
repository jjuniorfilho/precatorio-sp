#!/usr/bin/env bash
#
# fleet.config.sh — configuracao do Cortex Fleet por projeto (TEMPLATE)
#
# Copie para a raiz do .claude do seu projeto e ajuste:
#   cp .claude/skills/fleet-orchestration/fleet.config.example.sh .claude/fleet.config.sh
#
# TODAS as variaveis e funcoes abaixo sao OPCIONAIS. Sem este arquivo, o Fleet usa
# defaults (auto-detect de package manager e de lint/test). Documentacao completa em
# .claude/skills/fleet-orchestration/reference/configuration.md
#
# Este arquivo e "sourced" pelos scripts do Fleet — nao o execute diretamente.

# ---- branches e worktrees -------------------------------------------------
# Ref base para criar as branches das worktrees.
# FLEET_BASE_REF="origin/main"

# Prefixo da branch: <prefix>/<worktree-name>. Default: slug do git user.name.
# FLEET_BRANCH_PREFIX="seu-usuario"

# Onde criar as worktrees.
# FLEET_WORKTREE_DIR=".claude/worktrees"

# ---- instalacao de dependencias -------------------------------------------
# Comando rodado dentro de cada worktree apos cria-la.
# Vazio/ausente = auto-detect pelo lockfile (pnpm/yarn/bun/npm).
# FLEET_INSTALL_CMD="npm ci"
# FLEET_INSTALL_CMD="pnpm install --frozen-lockfile && pnpm prisma generate"

# ---- gates de qualidade (fleet-gate.sh) -----------------------------------
# Lista de checagens mecanicas. Cada item: "label:comando".
# Vazio/ausente = auto-detect (roda "lint" e "test" do package.json, se existirem).
# Qualquer comando que retorne != 0 faz o gate sair com exit 2 (fail-closed).
# FLEET_GATE_CMDS=(
#   "lint:npm run lint"
#   "test:npm test"
# )

# ---- isolamento de dados por worktree (opcional) --------------------------
# Hook chamado por fleet-provision.sh APOS instalar deps.
# Args: $1=WT_NAME  $2=WT_DIR  $3=SHORT_ID (id curto derivado do nome)
# Use para criar database/schema isolado, escrever .env.fleet, rodar migrations, etc.
# fleet_provision_data() {
#   local wt_name="$1" wt_dir="$2" short_id="$3"
#   : # ex.: createdb "app_${short_id}" && migrate ...
# }

# Hook chamado por fleet-teardown.sh quando --drop-db e passado. Mesmos args.
# fleet_teardown_data() {
#   local wt_name="$1" wt_dir="$2" short_id="$3"
#   : # ex.: dropdb --if-exists "app_${short_id}"
# }
