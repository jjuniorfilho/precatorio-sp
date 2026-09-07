# Memory Schema — Referência Detalhada

> Schema completo de cada arquivo de memória, regras de decay e exemplos de destilação.
> Carregado sob demanda quando o agente precisa de detalhes de formato.

---

## Schema: sessions/YYYY-MM-DD-slug.md

**Formato obrigatório**:
- Header com metadata (comando, feature, branch)
- Resumo em 1-3 parágrafos
- Decisões tomadas com justificativas
- Problemas encontrados com soluções
- Learning summaries dos sub-agentes
- Nível de confiança (alta/média/baixa)

**Regras**:
- Max 200 linhas por arquivo de sessão
- Nome: `YYYY-MM-DD-slug.md` (slug derivado da feature/branch)
- Se sessão já existe (mesma data + slug), fazer append ao invés de sobrescrever
- Não incluir código-fonte — apenas referências a arquivos

---

## Schema: patterns/decisions.md

**Formato de entrada**:
```markdown
### YYYY-MM-DD — [título da decisão]
**Contexto**: [situação que levou à decisão]
**Decisão**: [o que foi decidido]
**Justificativa**: [por que]
**Confiança**: alta | média | baixa
```

**Regras**:
- Append-only (novas entradas no final)
- Decisões vinculadas a ADR marcadas com `ADR-NNN`
- Destiladas periodicamente para MEMORY.md quando confiança ≥ média

---

## Schema: patterns/errors.md

**Formato de entrada**:
```markdown
### YYYY-MM-DD — [descrição do erro]
**Erro**: [mensagem ou descrição]
**Causa**: [root cause identificada]
**Solução**: [como foi resolvido]
**Recorrência**: primeira vez | recorrente (N vezes)
```

**Regras**:
- Append-only
- Erros recorrentes (2+ vezes) são candidatos para MEMORY.md
- Incluir mensagens de erro exatas quando possível

---

## Schema: patterns/preferences.md

**Formato de entrada**:
```markdown
### YYYY-MM-DD — [preferência detectada]
**Preferência**: [o que o usuário/equipe prefere]
**Evidência**: [como foi detectada]
**Sessões**: [lista de sessões onde apareceu]
**Confiança**: alta | média | baixa
```

**Regras**:
- Preferências explícitas do usuário = confiança alta imediata
- Preferências inferidas precisam de 5+ sessões para confiança alta

---

## Schema: patterns/agent-learnings.md

**Formato de entrada**:
```markdown
### YYYY-MM-DD — /[comando] — [branch]

#### [nome-do-agente]
- **Padrões detectados**: [...]
- **Decisões tomadas**: [...]
- **Warnings**: [...]
- **Sugestão para memória**: [...]
```

**Regras**:
- Gerado automaticamente por comandos multi-agente (/pre-pr, /work)
- Cada agente produz seu próprio Learning Summary
- Padrões recorrentes marcados com `[RECORRENTE]`
- Consolidação periódica: mesclar duplicatas, promover para MEMORY.md

---

## Schema: MEMORY.md

**Limite**: Max 200 linhas (linhas após 200 são truncadas no contexto)

**Seções recomendadas**:
1. Padrões Arquiteturais
2. Preferências da Equipe
3. Erros Conhecidos
4. Decisões Técnicas

**Metadata no rodapé**:
```markdown
---
Última destilação: YYYY-MM-DD
Sessões analisadas: N
Entradas ativas: N | Stale: N | Permanentes: N
```

---

## Regras de Decay

| Idade sem referência | Status | Ação | Exceção |
|---------------------|--------|------|---------|
| 0-29 dias | ACTIVE | Nenhuma | — |
| 30-89 dias | STALE | Marcar `[STALE]` | ADR-linked → PERMANENT |
| 90+ dias | EXPIRED | Propor remoção | ADR-linked → PERMANENT |
| Qualquer | PERMANENT | Nunca decai | Decisões vinculadas a ADR |

**Verificação de referência**: Uma entrada é "referenciada" se:
- Aparece em uma sessão recente
- É citada em um pattern file
- Está vinculada a um ADR ativo
- Foi consultada explicitamente pelo usuário

---

## Exemplo de Destilação

### Antes (3 sessões individuais):

**sessions/2026-02-28-auth.md**:
> Decisão: Usar JWT com refresh tokens. Justificativa: padrão da equipe.

**sessions/2026-03-02-api.md**:
> Decisão: Usar JWT para autenticação da API. Consistente com sessão anterior.

**sessions/2026-03-05-security.md**:
> Decisão: JWT com rotação de refresh tokens a cada 7 dias.

### Depois (entrada destilada no MEMORY.md):

```markdown
## Decisões Técnicas
- **Autenticação JWT com refresh tokens** — Padrão confirmado (3 sessões).
  Rotação de refresh tokens a cada 7 dias. Confiança: ALTA.
```

---

## Formato de Relatório de Auditoria

```markdown
## Memory Audit Report — YYYY-MM-DD

### Métricas
| Camada | Arquivos | Entradas | Tamanho |
|--------|----------|----------|---------|
| MEMORY.md | 1 | N | N linhas (max 200) |
| sessions/ | N | — | N total linhas |
| patterns/ | N | N | N total linhas |
| evolution/ | N | N | N total linhas |

### Health Checks
- [x] MEMORY.md abaixo de 200 linhas
- [x] Todas as sessões abaixo de 200 linhas
- [x] Sem conflitos detectados
- [x] Sem entradas EXPIRED não tratadas

### Decay Status
- Active: N entradas
- Stale: N entradas (listadas abaixo)
- Expired: N entradas (remoção proposta)
- Permanent: N entradas (ADR-linked)

### Conflitos
- [lista de conflitos ou "Nenhum conflito detectado"]

### Recomendações
- [ações sugeridas]
```
