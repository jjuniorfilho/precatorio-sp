# Project Briefing — Consulta Precatório SP (Forjuris)

> Gerado por `/discover` em 2026-05-31
> Atualizar executando `/discover` novamente (incremental, não-destrutivo)

---

## 📊 Status do Projeto

| Dimensão | Status | Detalhe |
|----------|--------|---------|
| Business Context | ✅ Completo | docs/business-context/ (10 arquivos) |
| Design System | ✅ Completo | BTG Pactual style, Sora + Inter |
| Protótipos HTML | ✅ Completo | 5 telas, 19 estados |
| Frontend Lovable | ✅ Gerado | TanStack Router + React 19 + shadcn/ui |
| Backend Supabase | ❌ Pendente | Nenhuma tabela criada ainda |
| Dados DEPRE | ❌ Pendente | 199.767 registros a importar |
| Integração Front-Back | ❌ Pendente | 12 mocks ativos no frontend |

**Fase atual**: FASE 4 — Implementação Backend

---

## 📚 Índice do Briefing

| Arquivo | Conteúdo | Quando usar |
|---------|----------|-------------|
| [critical-rules.md](briefing/critical-rules.md) | Regras não-negociáveis | Sempre — copiar para todo context.md |
| [frontend-lovable.md](briefing/frontend-lovable.md) | 12 mocks → endpoints | Ao implementar cada endpoint |
| [tech-stack.md](briefing/tech-stack.md) | Stack completa | Ao configurar ambiente |
| [backend-conventions.md](briefing/backend-conventions.md) | Convenções a seguir | Ao criar código backend |
| [adrs-summary.md](briefing/adrs-summary.md) | ADRs (nenhuma ainda) | — |

---

## 🎯 Guia de uso por tipo de tarefa

### Implementar endpoint de busca de precatórios
→ Ler `frontend-lovable.md` Mock #1, #2, #3
→ Tabela `precatorios` (schema em `backend-conventions.md`)

### Implementar captura de lead
→ Ler `frontend-lovable.md` Mock #4, #5, #6
→ Tabelas `leads` + `tokens`

### Implementar painel admin
→ Ler `frontend-lovable.md` Mock #7 a #12
→ Tabelas `leads` + `funnel_events` + `lead_status_history`

### Qualquer tarefa backend
→ Sempre começar por `critical-rules.md`

---

## 🔑 Repositórios

| Repo | URL | Finalidade |
|------|-----|-----------|
| cortex-v1 | jjuniorfilho/precatorio-sp | Docs, contexto, protótipos |
| frontend | jjuniorfilho/sp-precat-rios-simples-c2fc47c1 | App React (Lovable) |
| Supabase | a criar | Backend + banco de dados |

---

## 🔄 Para atualizar este briefing

```bash
/discover
```
