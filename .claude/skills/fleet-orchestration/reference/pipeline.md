# Fleet — design do pipeline gate-based

## Principio

O workflow do Cortex e human-gated por design (`/start`, `/plan`, `/pr` exigem aval).
O Fleet preserva isso: **3 gates humanos** (arquitetura, plano, merge). Tudo entre os
gates e garantido por agentes + checagens mecanicas nao-pulaveis.

```mermaid
flowchart TD
    A["/engineer:fleet PX-2621 PX-2622 ..."] --> P0
    subgraph P0["FASE 0 — Provisionamento (autonomo)"]
        P0a["fleet-provision.sh por issue:<br/>worktree · .worktreeinclude · install (auto-detect)<br/>fleet_provision_data (dados isolados, opcional)"]
    end
    P0 --> P1
    subgraph P1["FASE 1 — Discovery + Arquitetura"]
        P1a["/engineer:warm-up + /engineer:start<br/>→ context.md + architecture.md + verificacao cruzada"]
        P1b["fleet-phase-gate.sh --phase 1<br/>exit 2 BLOQUEIA se faltar artefato"]
        P1a --> P1b
    end
    P1 --> G1{{"⛔ GATE 1 — arquitetura (lote)"}}
    G1 -->|aprovado| P2
    G1 -->|ajustes| P1
    subgraph P2["FASE 2 — Planejamento"]
        P2a["/engineer:plan → plan.md faseado"]
    end
    P2 --> G2{{"⛔ GATE 2 — plano (--auto-plan p/ pequenas)"}}
    G2 -->|aprovado| P3
    subgraph P3["FASE 3 — Implementacao (garantias nao-pulaveis)"]
        P3a["/engineer:work por fase"]
        P3b["test-engineer + code-reviewer (loop max 2)"]
        P3c["fleet-gate.sh (lint/test/custom) + adr-compliance-checker STRICT<br/>exit 2 BLOQUEIA"]
        P3a --> P3b --> P3c
    end
    P3 --> P4
    subgraph P4["FASE 4 — Pre-PR (autonomo)"]
        P4a["/engineer:pre-pr → 4 branch-* + cross-doc + ADR STRICT"]
    end
    P4 --> P5
    subgraph P5["FASE 5 — PR (autonomo)"]
        P5a["/engineer:pr → Deploy Notes + abre PR + review automatizado"]
    end
    P5 --> G3{{"⛔ GATE 3 — merge queue + merge manual"}}
    G3 --> DONE["Linear → Done · command-usage.jsonl (ADR-008)"]
```

## Por que esses 3 gates

- **Gate 1 (arquitetura):** maior alavancagem. Erro arquitetural propaga por toda a
  implementacao — barato revisar, carissimo deixar passar. Nao-negociavel.
- **Gate 2 (plano):** pode ser leve. `--auto-plan` libera issues pequenas/bem
  definidas; grandes ou que tocam schema/seguranca sempre esperam aval.
- **Gate 3 (merge):** humano por politica do `/pr` + serializado pela merge queue.

## Infra — isolamento sem colisao

A estrategia de isolamento e **definida pelo projeto** na config layer
([`configuration.md`](configuration.md)). Padroes comuns:

- Infra compartilhada (ex.: banco de dados) sobe **uma vez**; worktrees nao sobem stack
  propria. O isolamento de dados por worktree (ex.: database/schema dedicado) vai no hook
  `fleet_provision_data`.
- Testes efemeros (ex.: Testcontainers) reduzem colisao de porta — offset de porta
  (`API_PORT = base + i`) so quando a worktree boota um servico.
- Caches content-addressable (ex.: pnpm store) evitam multiplicar disco por worktree.

## Mapa das 5 garantias → enforcement

| # | Garantia | Enforcement | Onde |
|---|---|---|---|
| 1 | Funcionalidade | `test-engineer` + `branch-test-planner` + gate `test` | `/work`, `/pre-pr`, hook (v2) |
| 2 | Aderencia a ADRs | `adr-compliance-checker` STRICT + `branch-master-docs-checker` + gate custom | `/work`, `/pre-pr`, hook (v2) |
| 3 | Seguranca | `code-reviewer` + `branch-code-reviewer` (CRITICAL bloqueia) | `/work`, `/pre-pr` |
| 4 | Padroes | `adr-compliance-checker` + `code-reviewer` + gate `lint` | `/work`, hook (v2) |
| 5 | Testes | `branch-test-planner` (+30-40% edge cases) + cobertura | `/pre-pr`, hook (v2) |

> O `code-reviewer` roda em 2 passes (em `/work` = bugs/logica; em `/pre-pr` =
> seguranca/polish). Nao e redundancia — categorias complementares.

## Roadmap

- **v1 (atual):** garantias como passos explicitos do lead.
- **v2:** hooks `TaskCompleted`/`TeammateIdle` (`exit 2`) via `fleet-gate.sh` →
  garantias nao-pulaveis ([`hooks-settings.md`](hooks-settings.md)).
- **v3 (futuro):** dashboard de review queue (artifact HTML vivo) + modo headless
  `claude -p` para batch overnight.
