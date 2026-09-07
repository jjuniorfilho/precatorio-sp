> Carregado na Fase 0 da skill `prototype-to-plan`, quando é preciso mapear a fundação de engenharia real do projeto para separar reuso de net-new. Roteiro de quais arquivos ler e o que extrair de cada um.

# Roteiro de leitura da fundação (Fase 0)

O objetivo é responder, para cada capacidade que o protótipo exige: **"isso já existe? onde?"** O resultado é o **mapa reuso-vs-net-new**, que impede a frota de reconstruir o que já está pronto e expõe o miolo net-new (geralmente pequeno e arriscado).

## Ordem de leitura

### 1. `CLAUDE.md` (raiz)
A fonte mais densa. Procure menções a:
- Endpoints já implementados (a seção `apps/api/src/api/v1/` lista os slices verticais com rotas).
- Telas/rotas do admin já existentes (`apps/admin/`).
- Capacidades de worker (pipeline, OCR, report, webhooks).
- O **contrato api↔admin** (gate `openapi.json` → `api.gen.ts` → `api.contract.ts`).
- O modelo de RBAC e RLS (roles, scopes, `executeWithTenant`, `@PlatformOnly`).

Grep útil para capacidades:
```
grep -nEi "POST /|GET /|PATCH /|DELETE /" CLAUDE.md
grep -nEi "role|scope|RLS|tenant|@Scopes|PLATFORM_ADMIN|TENANT_USER" CLAUDE.md
```

### 2. Índice de ADRs — `master-docs/technical-context/adr/`
Liste os ADRs e leia os títulos. Identifique quais **governam** a feature do protótipo:
- Multi-tenant/RLS (005), Vertical Slice (004), Result Pattern (006), Auth (007), API-first/versioning (014), JSONB discriminator (008).
- Qualquer ADR que a feature toque (ex.: se a feature alimenta um gate de qualidade, leia o ADR de shadow/cutover 019).
Anote o **próximo número de ADR livre** e os reservados (ex.: 028).

### 3. Contrato OpenAPI — `apps/api/openapi.json`
É a verdade dos endpoints existentes (gerado, commitado). Para cada capacidade do protótipo, procure o path correspondente:
```
grep -nE "\"/(lawsuits|reports|documents|agents|runs)" apps/api/openapi.json
```
Se o endpoint existe → **reuso**. Se não existe → **net-new (BE + contrato)**, e o gate `pnpm contract:check` vai precisar rodar.

### 4. Schema de dados — `libs/database/prisma/schema.prisma`
Liste models e enums. Para cada entidade nova que o protótipo escreve (ex.: uma "revisão", um "comentário"):
- Confirme que **não existe** model equivalente.
- Identifique a entidade-pai (FK) e como o RLS se aplica (a maioria das tabelas tem `tenant_id` + policy; algumas são cross-tenant NO-RLS — siga o precedente da tabela vizinha).
```
grep -nE "^model |^enum " libs/database/prisma/schema.prisma
```

### 5. Design system / libs de UI
- `libs/ui/` (`@px-agents/ui`) — componentes DS reutilizáveis e o tema.
- `apps/admin/src/` — padrões de tela, `index.css`/`tailwind.config.cjs` (tokens, tema).
- `docs/design-system/` e `docs/prototypes/` — DS canônico e protótipos anteriores.
Se o protótipo inventou paleta/fontes próprias (divergiu do DS), isso é um **decision-gate de tema** (Fase 1), não um detalhe.

### 6. RBAC / Auth — `libs/shared/src/auth/` e `apps/api/src/auth/`
- Roles existentes (ex.: `PLATFORM_ADMIN`, `TENANT_ADMIN`, `TENANT_USER`) e o enum no Prisma.
- Scopes e os guards (`JwtAuthGuard`, `ScopesGuard`, `@Scopes`, `@PlatformOnly`).
- Como o tenant é resolvido e isolado (`executeWithTenant`, `TenantInterceptor`).
Isso alimenta o decision-gate de papel/role e os ACs de segurança.

## Saída: o mapa reuso-vs-net-new

Monte e apresente ao usuário uma tabela:

| Capacidade do protótipo | Já existe? (arquivo/endpoint/model) | Veredito | Camada |
|---|---|---|---|
| Listar processos | `GET /lawsuits` | reuso | — |
| Upload de documentos | `POST /lawsuits/:id/documents` | reuso | — |
| Preview de relatório | `GET /reports/:id` + signed URL | reuso (talvez re-skin) | FE |
| Visualizador de docs | parcial (signed URL existe; índice não) | net-new parcial | FE + leve BE |
| Revisão com veredito/comentários | não | **net-new** | BE (tabela + endpoints) + FE |
| Role-gating do perfil | depende da decisão de role | net-new | RBAC |

Regra de ouro: **o que está na coluna "reuso" não vira issue de reconstrução** — no máximo issue de re-skin/consumo. As issues pesadas saem da coluna net-new.
