> Carregado na Fase 4 da skill `prototype-to-plan`, quando é preciso decompor o trabalho em issues no Linear corretamente: por camada, contract-first, em 2 ondas. Inclui ids do projeto, convenção de labels, template de issue e o grafo de dependência.

# Decomposição por camada + plano de ondas no Linear (Fase 4)

Orquestra o fluxo de `product:task`, mas impõe a estrutura que evita o drift. **Apresente o plano (árvore + grafo de dependência + ondas) para confirmação antes de criar no Linear.**

## Contexto do projeto (DESCUBRA — não hardcode)

Leia o `CLAUDE.md` do projeto (seção Linear) ou pergunte ao usuário para o **project + team** alvo e a **convenção de labels**. **Não assuma os IDs de um projeto específico** — eles variam por projeto.

### Labels (convenção típica PX-style; confirme a do projeto)
- `type:*` — `feature`, `bug`, `improvement`, `research`, `spike` (≥1 por issue)
- `area:*` — `backend`, `frontend`, `infra`, `ai`, `data` (≥1 por issue)
- `int:*` — integrações externas (condicional)

## As 5 camadas (ordem de dependência)

1. **Decisões / ADR** — se os ADRs não estiverem mergeados, a primeira issue é doc-only (publicar os ADRs). `type:improvement` + `area:backend`/`infra`.
2. **BE + contrato** — schema/migration + endpoints + **regenerar `openapi.json` e `api.gen.ts`**. Esta camada **aterrissa primeiro** porque define o contrato que o FE consome. `type:feature` + `area:backend` (+ `area:data` se houver migration).
3. **RBAC / segurança** — role-gating, guards, isolamento de tenant. Pode ser parte do BE ou issue própria se for substancial. `area:backend`.
4. **FE** — telas consumindo o `api.gen.ts` **real** da camada 2. Mock-first é permitido para velocidade, mas o **gate é modo real**. `type:feature` + `area:frontend`.
5. **e2e real** — Playwright contra a stack seedada. `type:improvement` + `area:frontend`.

## Sequência em 2 ondas (NÃO tudo paralelo no t0)

```
ONDA 1 — contract-first (trava o contrato)
  [1] Publicar ADR(s)            (doc-only)
  [2] BE: schema + migration + endpoints + regen contrato   ─┐
  [3] RBAC: role-gating + guards + teste de RLS              ─┴─ dependem de [1]

        ▼ (contrato openapi.json/api.gen.ts mergeado)

ONDA 2 — FE larga (consome o contrato real)
  [4a] FE: tela A   ─┐
  [4b] FE: tela B    ├─ dependem de [2] (contrato real)
  [4c] FE: tela C   ─┘
  [5]  e2e real     ── depende de [4*]
```

Regra dura: **nenhuma issue de FE que consome um endpoint novo entra na Onda 1.** Se o FE precisa de um endpoint que ainda não existe, ele depende da issue de BE que o cria. Modele isso como dependência explícita no Linear (blocking).

## Template de issue (cada uma carrega)

```markdown
## Descrição funcional
<o quê e por quê, 1-2 parágrafos. Referencie a tela do protótipo por nome.>

## Arquitetura técnica & plano de execução
<arquivos a tocar, slices, contratos. Cite arquivo:linha do existente.
Para BE: a migration, o endpoint, o regen do contrato.
Para FE: o componente, o hook, o service consumindo api.gen.ts.>

## Componentes afetados
<libs/apps tocados>

## Critérios de aceitação
- [ ] <funcional, derivado do protótipo>
- [ ] <funcional>
### ACs anti-drift (obrigatórios por camada)
- [ ] (BE) `pnpm contract:check` verde — openapi.json + api.gen.ts regenerados e commitados
- [ ] (BE/migration) `./scripts/check-migration-rls.sh` verde
- [ ] (RBAC) teste prova que a role NÃO acessa superfície proibida e NÃO vê outro tenant
- [ ] (FE) validado em **modo real** (`VITE_USE_MOCKS=false`) contra a API seedada, não só mock
- [ ] (FE) acessibilidade: foco de teclado, reduced-motion respeitado

## Pontos de atenção para validação
<edge cases, riscos>

## Referências
- PRD: <link/caminho>
- ADR: ADR-NNN
- Protótipo: <caminho commitado> (tela: <nome>)
```

## Dependências & estimativa

- Marque **blocking/blocked-by** no Linear conforme o grafo acima.
- Se uma issue ficar grande (BE com migration + N endpoints + RBAC), considere pai + filhas (o `product:task` já faz isso; declare a intenção antes).
- Não estime a partir do backlog antigo sem checar o código — itens de dívida ficam stale (lição real: um item de dívida já estava resolvido; outro era feature, não dívida). Valide no código antes de dimensionar.

## Handoff (Fase 5)

Após criar as issues, entregue:
- IDs das issues por onda, com o grafo de dependência.
- Próximo comando: `/engineer:fleet` começando pela **Onda 1**.
- Gates locais antes de cada PR: `pnpm contract:check`, `./scripts/check-migration-rls.sh`, validação em modo real.

## Registro em memória (se `.claude/memory/` existir)

```markdown
### YYYY-MM-DD — prototype-to-plan — <feature>
**Protótipo:** <caminho>
**Decisões travadas:** <resumo 1 linha>
**ADRs gerados:** ADR-NNN
**Ondas Linear:** Onda 1 [ids] → Onda 2 [ids]
**Confiança:** alta | media | baixa
```
