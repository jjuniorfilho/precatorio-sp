#!/usr/bin/env bash
#
# handoff.config.example.sh — Cortex · config layer do /engineer:handoff
#
# COPIE para `.claude/handoff.config.sh` e ajuste. O arquivo e OPCIONAL: sem ele o
# comando funciona e declara explicitamente o que nao consegue medir.
#
# Por que existe: o nucleo e stack-agnostico (Regra 12). Nome de workflow de deploy e
# path de migration sao do SEU projeto, nao do framework — mesma divisao que o
# `fleet.config.sh` faz para o Fleet (ADR-013).
#
# Este arquivo e sourced por `.claude/scripts/handoff-measure.sh` e
# `.claude/scripts/handoff-commit.sh`. Ele e dev-owned: trate-o com a mesma confianca
# que trata os scripts do repo.

# ── Onde os handoffs vivem ────────────────────────────────────────────────────
# Diretorio dos arquivos de handoff, relativo a raiz do repo.
# HANDOFF_DIR="docs/handoffs"

# Arquivo de memoria que carrega o ponteiro do handoff vivo. E o arquivo que o
# /engineer:warm-up ja le — por isso o ponteiro mora nele, sem mecanismo novo.
# HANDOFF_MEMORY_FILE=".claude/memory/MEMORY.md"

# ── Branch principal ──────────────────────────────────────────────────────────
# Deixe vazio para autodeteccao (origin/HEAD, depois main/master/trunk locais).
# Preencha se o seu repo usa outro nome e a autodeteccao falhar.
# HANDOFF_MAIN_BRANCH=""

# ── Como o seu projeto marca "producao" ───────────────────────────────────────
# Escolha UMA das duas. Sem nenhuma, a secao GAP_DEPLOY_MAIN sai NAO MEDIDO e o
# handoff fica proibido de afirmar qualquer coisa sobre producao.
#
# (a) Workflow de deploy no GitHub Actions — usa o ultimo run bem-sucedido. Exige `gh`.
# HANDOFF_DEPLOY_WORKFLOW="deploy-prod.yml"
#
# (b) Uma ref que o projeto move a cada deploy (tag, branch de producao). Nao exige gh.
# HANDOFF_PROD_REF="refs/heads/production"

# ── Paths de fronteira ────────────────────────────────────────────────────────
# Arquivos cuja mudanca exige acao humana que o CD NAO faz sozinho. Quando um deles
# aparece no gap entre producao e a main, o handoff precisa dizer em voz alta.
#
# E a diferenca entre "o PR entrou" e "o PR entrou e o alarme ainda nao existe".
#
# HANDOFF_BOUNDARY_PATHS=(
#   "libs/database/prisma/migrations"   # migration pendente de apply
#   "infra/"                            # terraform que exige apply do operador
#   "charts/"                           # helm que exige rollout manual
# )
