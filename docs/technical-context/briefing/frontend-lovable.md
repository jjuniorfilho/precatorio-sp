# Frontend Lovable — Mapeamento de Mocks

> Gerado por `/discover` em 2026-05-31
> Fonte: `~/projetos/consulta-precatorio/frontend/src/data/mockData.ts`
> **12 mocks ativos** → 12 endpoints necessários no backend

---

## Resumo

| # | Mock | Arquivo | Endpoint necessário | Prioridade |
|---|------|---------|---------------------|-----------|
| 1 | mockPrecatorios (busca por processo) | mockData.ts:56 | `GET /precatorios?q=` | P0 |
| 2 | mockPrecatorios (busca por CPF) | mockData.ts:56 | `GET /precatorios?cpf=` | P0 |
| 3 | mockPrecatorios (busca por CNPJ) | mockData.ts:56 | `GET /precatorios?cnpj=` | P0 |
| 4 | mockLeads (listagem admin) | mockData.ts:134 | `GET /admin/leads` | P1 |
| 5 | mockLeads (detalhe) | mockData.ts:134 | `GET /admin/leads/:id` | P1 |
| 6 | mockLeads (atualizar status/notas) | mockData.ts:134 | `PATCH /admin/leads/:id` | P1 |
| 7 | mockLeadsIncompletos | mockData.ts:213 | `GET /admin/leads/incompletos` | P1 |
| 8 | mockFunnelStats | mockData.ts:240 | `GET /admin/funil/stats` | P1 |
| 9 | mockLeadTimeline | mockData.ts:249 | `GET /admin/leads/:id/timeline` | P2 |
| 10 | mockCrmPipeline | mockData.ts:276 | `GET /admin/crm/pipeline` | P2 |
| 11 | Auth mock (admin login) | AppProviders.tsx | `POST /admin/auth/login` | P1 |
| 12 | Token OTP mock | verificar.*.tsx | `POST /tokens/send` + `POST /tokens/verify` | P0 |

---

## Mock #1 — Busca de precatório por processo

**Componente:** `src/routes/resultado.$processo.tsx` + `src/lib/format.ts:findPrecatorio()`

**Mock atual:**
```typescript
// src/data/mockData.ts:56
export const mockPrecatorios: Precatorio[] = [
  { id, processo_depre, autos, devedora, saldo_depre, natureza, status, suspenso,
    data_protocolo, autor, cpf, cpf_titular, cnpj_titular }
  // ... 5 registros hardcoded
]
// Busca: findPrecatorio(processo, mockPrecatorios)
```

**Endpoint necessário:**
```
GET /precatorios?q={processo_normalizado}
Response: Precatorio | null
```

**Interface TypeScript:**
```typescript
interface Precatorio {
  id: string;
  processo_depre: string;
  autos: string;
  devedora: string;
  saldo_depre: number;        // centavos!
  natureza: "Alimentar" | "Outras";
  status: "Ativo" | "Sem saldo" | "Suspenso";
  suspenso: boolean;
  data_protocolo: string;     // ISO date
  autor: string;              // nome mascarado
  cpf: string;                // CPF mascarado
  cpf_titular: string | null;
  cnpj_titular: string | null;
}
```

**Checklist de integração:**
- [ ] Backend: `GET /precatorios?q=` com busca normalizada
- [ ] Backend: Índice no Supabase por `processo_depre` e `autos`
- [ ] Frontend: Substituir `findPrecatorio()` por chamada Supabase JS
- [ ] Frontend: Adicionar loading state (já existe skeleton)
- [ ] Frontend: Error handling (processo não encontrado → variante NotFound)

---

## Mock #2 — Busca por CPF

**Componente:** `src/routes/resultado.cpf.$cpf.tsx` + `src/lib/search.ts:findByCpf()`

**Endpoint necessário:**
```
GET /precatorios?cpf={cpf_normalizado_11_digitos}
Response: Precatorio[]  // pode retornar múltiplos
```

**Checklist:**
- [ ] Backend: índice em `cpf_titular`
- [ ] Backend: mascarar `cpf` e `autor` na resposta
- [ ] Frontend: substituir `findByCpf()` por chamada Supabase

---

## Mock #3 — Busca por CNPJ

**Componente:** `src/routes/resultado.cnpj.$cnpj.tsx` + `src/lib/search.ts:findByCnpj()`

**Endpoint necessário:**
```
GET /precatorios?cnpj={cnpj_normalizado_14_digitos}
Response: Precatorio[]
```

**Checklist:**
- [ ] Backend: índice em `cnpj_titular`
- [ ] Frontend: substituir `findByCnpj()` por chamada Supabase

---

## Mock #4 — Lead: captura (POST)

**Componente:** `src/routes/cadastro.tsx` → submit do formulário

**Mock atual:** navega para `/verificar/email` sem persistir

**Endpoint necessário:**
```
POST /leads
Body: { nome, email, telefone, relacao, processo_depre, saldo_consultado, devedora, session_id }
Response: { lead_id: string }
```

**Checklist:**
- [ ] Backend: INSERT em `leads` com status_crm = "novo"
- [ ] Backend: registrar `funnel_events` (cadastro_iniciado)
- [ ] Frontend: após POST, navegar para `/verificar/email` com `lead_id`

---

## Mock #5 — Token: envio e verificação

**Componente:** `src/routes/verificar.email.tsx` + `src/routes/verificar.whatsapp.tsx`

**Mock atual:** aceita qualquer 6 dígitos como válido

**Endpoints necessários:**
```
POST /tokens/send
Body: { lead_id, canal: "email" | "whatsapp" }
Response: { expires_at: string }

POST /tokens/verify
Body: { lead_id, canal, codigo }
Response: { valid: boolean }
```

**Checklist:**
- [ ] Backend: gerar token de 6 dígitos, salvar em `tokens` com TTL 10min
- [ ] Backend: integrar com provedor de e-mail (Resend/SendGrid)
- [ ] Backend: integrar com WhatsApp API (Twilio/Z-API/Evolution)
- [ ] Backend: registrar eventos em `funnel_events`
- [ ] Frontend: substituir mock por chamada real

---

## Mock #6 — Listagem de leads (admin)

**Componente:** `src/routes/admin.leads.tsx`

**Mock atual:**
```typescript
export const mockLeads: Lead[] = [ /* 5 leads hardcoded */ ]
// Com filtros: status_crm, devedora, relacao, saldo range, search, período
```

**Endpoint necessário:**
```
GET /admin/leads?status=novo&devedora=fazenda&relacao=titular&saldo_min=0&saldo_max=10000000&q=maria&period=7&page=1&limit=20
Response: { data: Lead[], total: number, page: number }
```

**Checklist:**
- [ ] Backend: query paginada com todos os filtros
- [ ] Backend: autenticação admin (Supabase Auth + role)
- [ ] Frontend: substituir `useAdmin().leads` por query Supabase

---

## Mock #7 — Detalhe do lead + atualizar status

**Componente:** `src/routes/admin.leads.tsx` → Dialog

**Endpoints necessários:**
```
GET /admin/leads/:id
Response: Lead + timeline

PATCH /admin/leads/:id
Body: { status_crm?: CrmStatus, notas?: string }
Response: Lead atualizado
```

**Checklist:**
- [ ] Backend: registrar mudança em `lead_status_history`
- [ ] Frontend: substituir `updateLeadStatus()` / `updateLeadNotes()`

---

## Mock #8 — Leads incompletos

**Componente:** `src/routes/admin.incompletos.tsx`

**Mock atual:**
```typescript
export const mockLeadsIncompletos: LeadIncompleto[] = [
  { session_id, processo_buscado, saldo_encontrado, etapa_abandono, dispositivo, data }
]
```

**Endpoint necessário:**
```
GET /admin/leads/incompletos?period=7&page=1
Response: { data: LeadIncompleto[], total: number }
```

**Checklist:**
- [ ] Backend: query em `funnel_events` agrupado por `session_id` sem lead completo
- [ ] Backend: nenhum dado pessoal exposto (só session_id)

---

## Mock #9 — Funil de conversão

**Componente:** `src/routes/admin.funil.tsx`

**Mock atual:**
```typescript
export const mockFunnelStats = {
  visitantes: 8420, buscas: 5220, resultados: 3790,
  cadastrosIniciados: 1516, tokensValidados: 842, leadsCompletos: 421
}
```

**Endpoint necessário:**
```
GET /admin/funil/stats?period=7
Response: { visitantes, buscas, resultados, cadastrosIniciados, tokensValidados, leadsCompletos }
```

**Checklist:**
- [ ] Backend: COUNT de `funnel_events` por `event_type` no período
- [ ] Frontend: conectar filtro de período aos dados

---

## Mock #10 — Pipeline CRM

**Componente:** `src/routes/admin.funil.tsx`

**Mock atual:**
```typescript
export const mockCrmPipeline: Record<CrmStatus, number> = {
  novo: 12, contatado: 48, qualificado: 21, ...
}
```

**Endpoint necessário:**
```
GET /admin/crm/pipeline
Response: Record<CrmStatus, number>
```

---

## Mock #11 — Timeline do lead

**Componente:** Dialog de detalhe em `admin.leads.tsx`

**Mock atual:** `mockLeadTimeline` indexado por lead_id

**Endpoint necessário:**
```
GET /admin/leads/:id/timeline
Response: { evento, tempo, tipo }[]
```

**Dados:** vem de `funnel_events` + `lead_status_history` do lead

---

## Mock #12 — Auth admin

**Componente:** `src/routes/admin.login.tsx`

**Mock atual:** `admin@forjuris.com.br` / `admin123` no localStorage

**Endpoint necessário:** Supabase Auth nativo
```typescript
// Frontend substituir por:
const { data, error } = await supabase.auth.signInWithPassword({ email, password })
```

**Checklist:**
- [ ] Criar usuário admin no Supabase Auth
- [ ] Configurar RLS: tabelas admin acessíveis apenas por `auth.role() = 'authenticated'`
- [ ] Frontend: substituir localStorage mock por `supabase.auth`
