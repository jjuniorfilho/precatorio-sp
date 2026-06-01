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
```sql
CREATE TABLE leads (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome                    TEXT NOT NULL,
  email                   TEXT NOT NULL,
  telefone                TEXT NOT NULL,
  relacao                 TEXT NOT NULL CHECK (relacao IN ('titular','herdeiro','advogado')),
  processo_depre          TEXT NOT NULL,
  saldo_consultado        BIGINT NOT NULL DEFAULT 0,  -- em CENTAVOS
  devedora                TEXT,
  status_crm              TEXT NOT NULL DEFAULT 'novo',
  notas                   TEXT DEFAULT '',
  token_email_validado    BOOLEAN NOT NULL DEFAULT false,
  token_telefone_validado BOOLEAN NOT NULL DEFAULT false,
  session_id              TEXT,
  created_at              TIMESTAMPTZ DEFAULT NOW(),
  updated_at              TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_leads_status_crm  ON leads (status_crm);
CREATE INDEX idx_leads_created_at  ON leads (created_at DESC);
```

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

-- leads: apenas usuário autenticado (admin)
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_all_leads"
  ON leads FOR ALL TO authenticated USING (true);

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
