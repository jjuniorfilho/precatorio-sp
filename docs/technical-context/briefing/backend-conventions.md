# Convenções de Backend — Consulta Precatório SP

> Backend a implementar via Supabase. Este documento define as convenções que devem ser
> seguidas na criação do schema, funções e integrações.

---

## Schema de banco de dados

### Tabela: `precatorios`
```sql
CREATE TABLE precatorios (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_depre  TEXT NOT NULL,           -- ex: 0122089-09.2025.8.26.0500
  autos           TEXT,                    -- número de autos (pode ser igual ao depre)
  devedora        TEXT NOT NULL,           -- Fazenda SP, SPPREV, CBPM, IPESP, DER...
  saldo_depre     BIGINT NOT NULL DEFAULT 0,  -- em CENTAVOS
  natureza        TEXT NOT NULL,           -- "Alimentar" | "Outras"
  status          TEXT NOT NULL,           -- "Ativo" | "Sem saldo" | "Suspenso"
  suspenso        BOOLEAN NOT NULL DEFAULT false,
  data_protocolo  DATE,
  autor           TEXT,                    -- nome do credor (exibir mascarado)
  cpf_titular     TEXT,                    -- CPF sem máscara (11 dígitos)
  cnpj_titular    TEXT,                    -- CNPJ sem máscara (14 dígitos)
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para busca rápida
CREATE INDEX idx_precatorios_processo ON precatorios (processo_depre);
CREATE INDEX idx_precatorios_autos    ON precatorios (autos);
CREATE INDEX idx_precatorios_cpf      ON precatorios (cpf_titular);
CREATE INDEX idx_precatorios_cnpj     ON precatorios (cnpj_titular);
```

### Tabela: `leads`
> Schema **real do banco** (conferido por diagnóstico em 2026-09-28; o schema original do MVP era mais simples).
> Colunas de funil (`nivel_funil`, `etapa1..6_*`) NÃO são da tabela: vêm da view `leads_com_progresso`.
```sql
-- colunas (ordem real)
id                      UUID PRIMARY KEY DEFAULT gen_random_uuid()
nome                    TEXT                       -- nullable
email                   TEXT                       -- nullable desde o FOR-173 (lead avulso)
telefone                TEXT                       -- nullable
relacao                 TEXT CHECK (relacao IN ('titular','herdeiro','advogado'))  -- nullable desde o FOR-173
processo_depre          TEXT                       -- nullable; pode ser CSV de .0500 (a view leads_processos expande)
saldo_consultado        BIGINT NOT NULL DEFAULT 0  -- em CENTAVOS
devedora                TEXT
status_crm              TEXT NOT NULL DEFAULT 'novo' CHECK (status_crm IN ('novo','contatado','qualificado','interessado','proposta','negociacao','fechado','descartado'))
notas                   TEXT DEFAULT ''
token_email_validado    BOOLEAN NOT NULL DEFAULT false
token_telefone_validado BOOLEAN NOT NULL DEFAULT false
session_id              TEXT
utm_source, utm_medium, utm_campaign  TEXT
lgpd_consent            BOOLEAN NOT NULL DEFAULT false
lgpd_consent_at         TIMESTAMPTZ
created_at, updated_at  TIMESTAMPTZ DEFAULT NOW()  -- updated_at mantido pelo trigger leads_updated_at
intent                  TEXT CHECK (intent IN ('cessao','acordo','info'))
relatorio_enviado_at    TIMESTAMPTZ
verified_at             TIMESTAMPTZ
origem                  TEXT                       -- livre, sem CHECK (ver valores abaixo)
cnj                     TEXT
criado_por              UUID                       -- FOR-173: auth.users.id do admin que cadastrou o avulso (sem FK)
documento               TEXT CHECK (documento IS NULL OR documento ~ '^\d{11}(\d{3})?$')  -- FOR-173: CPF/CNPJ pesquisado, só dígitos (PII)
```
- **`origem`** (texto livre): `busca_em_formacao` | `monitorar` | `antecipacao` (gravadas por `capturar-lead-publico`) | **`avulso`** (FOR-173: cadastrado pelo operador; sem 2 canais validados; `lgpd_consent = false`). Lead do site = `origem IS DISTINCT FROM 'avulso'` (no PostgREST `.neq()` descarta NULL: usar `.or('origem.is.null,origem.neq.avulso')`).
- **Índices:** `idx_leads_created_at`, `idx_leads_email`, `idx_leads_intent`, `idx_leads_origem`, `idx_leads_status_crm` e o único parcial `uq_leads_avulso_processo_depre (processo_depre) WHERE origem = 'avulso'` (um avulso por DEPRE).
- **Triggers:** `leads_updated_at` e `trg_leads_enfileira_crawler` (FOR-169: enfileira no crawler cada `.0500` sem capa).
- **Views (só `service_role`, `security_invoker = true`):** `leads_com_progresso` (`l.*` + `nivel_funil` e `etapa1..6`, inferidas — FOR-170) e `leads_processos` (uma linha por lead × processo consultado; expõe `origem` desde o FOR-173). `criado_por` e `documento` ficam fora das views de propósito (coluna nova no meio de `l.*` exigiria `DROP VIEW`).
- **FKs para `leads`:** `tokens`, `lead_status_history`, `lead_precatorios`, `comunicacoes_agendadas` (CASCADE) e `funnel_events` (SET NULL).

### Tabelas do valor pago (portal TJSP "Pagamentos Precatórios")
- `pagamentos_consultas_log` (FOR-171): histórico das consultas (últimas 20 por processo; passos, resultado, etapa da falha). Escrita por RPC `registrar_consulta_pagamento`; leitura admin por `listar_consultas_pagamento`.
- `pagamentos_consultas_progresso` (FOR-173): **progresso efêmero** da consulta em andamento — uma linha por `processo_depre` (`estado` na_fila|em_andamento|concluida|falha, `etapa` em andamento, `tentativa`/`max_tentativas`, `iniciada_em`, `atualizado_em`). Só o disparo `manual` grava. Escrita pelo worker (RPC `registrar_progresso_consulta_pagamento`); leitura só `service_role` (RPC `obter_progresso_consulta_pagamento`). Sem PII. Limpeza preguiçosa de 7 dias.

### Tabela: `tokens`
```sql
CREATE TABLE tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id    UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  canal      TEXT NOT NULL CHECK (canal IN ('email','whatsapp')),
  codigo     TEXT NOT NULL,               -- 6 dígitos
  expires_at TIMESTAMPTZ NOT NULL,        -- NOW() + 10 minutes
  usado      BOOLEAN NOT NULL DEFAULT false,
  tentativas INT NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### Tabela: `funnel_events`
```sql
CREATE TABLE funnel_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id  TEXT NOT NULL,
  lead_id     UUID REFERENCES leads(id) ON DELETE SET NULL,
  event_type  TEXT NOT NULL,    -- ver enum abaixo
  context     JSONB DEFAULT '{}',  -- processo_id, saldo, user_agent, etc.
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- event_type values:
-- busca_realizada | resultado_exibido | cadastro_iniciado
-- token_email_enviado | token_email_validado
-- token_whatsapp_enviado | token_whatsapp_validado | lead_completo

CREATE INDEX idx_funnel_session    ON funnel_events (session_id);
CREATE INDEX idx_funnel_event_type ON funnel_events (event_type);
CREATE INDEX idx_funnel_created_at ON funnel_events (created_at DESC);
```

### Tabela: `lead_status_history`
```sql
CREATE TABLE lead_status_history (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id         UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
  status_anterior TEXT,
  status_novo     TEXT NOT NULL,
  changed_by      TEXT,                   -- email do admin
  changed_at      TIMESTAMPTZ DEFAULT NOW()
);
```

---

## RLS Policies

```sql
-- precatorios: leitura pública, escrita apenas service role
ALTER TABLE precatorios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read_precatorios"
  ON precatorios FOR SELECT TO anon, authenticated USING (true);

-- leads (real): INSERT anônimo só com consentimento; todo o resto só admin (app_metadata.role = 'admin')
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_insert_leads" ON leads FOR INSERT TO anon WITH CHECK (lgpd_consent = true);
CREATE POLICY "leads_admin_only" ON leads FOR ALL TO authenticated
  USING (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin')
  WITH CHECK (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin');
-- O lead avulso (FOR-173) é inserido por server function com service_role (ignora RLS), nunca pelo anon.

-- tokens: service role only (sem acesso via anon)
ALTER TABLE tokens ENABLE ROW LEVEL SECURITY;
-- sem policy pública — acessar apenas via service role key

-- funnel_events: INSERT anon (tracking), SELECT autenticado (admin)
ALTER TABLE funnel_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "anon_insert_funnel"
  ON funnel_events FOR INSERT TO anon WITH CHECK (true);
CREATE POLICY "admin_read_funnel"
  ON funnel_events FOR SELECT TO authenticated USING (true);
```

---

## Nomenclatura

| Tipo | Padrão | Exemplo |
|------|--------|---------|
| Tabelas | snake_case plural | `funnel_events`, `leads` |
| Colunas | snake_case | `status_crm`, `token_email_validado` |
| Índices | `idx_{tabela}_{coluna}` | `idx_leads_status_crm` |
| Policies | string descritiva | `"admin_all_leads"` |
| Funções Supabase | snake_case | `get_funnel_stats()` |

---

## Padrão de acesso no frontend

```typescript
// Busca pública (anon key)
const { data } = await supabase
  .from('precatorios')
  .select('*')
  .eq('processo_depre', normalizedProcesso)
  .single()

// Admin (authenticated)
const { data } = await supabase
  .from('leads')
  .select('*')
  .order('created_at', { ascending: false })
  .range(offset, offset + limit - 1)
```
