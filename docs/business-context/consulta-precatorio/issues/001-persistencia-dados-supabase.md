# Modelagem e Persistencia de Dados no Supabase

**Tipo**: Feature
**Prioridade**: P0 - Critica
**Fase**: MVP (Fase 1)
**Status**: Backlog

---

## POR QUE

- O portal precisa de uma base consultavel de ~200K precatorios para entregar valor imediato ao usuario (consulta gratuita de saldo)
- Leads qualificados (saldo positivo + contato validado) sao o principal ativo de negocio — precisam ser persistidos de forma segura e estruturada
- Funnel tracking e essencial para medir conversao, identificar gargalos e otimizar a jornada de consulta → lead
- LGPD exige medidas tecnicas de protecao de dados pessoais (Art. 46) — RLS e anonimizacao de IP sao o minimo viavel

## O QUE

### 1. Tabela `precatorios` — Base DEPRE

Importacao one-off via script Node.js dos ~200K registros do arquivo `precatorios_depre_completo.xlsx`.

**Colunas (14 da planilha + 1 preparacao Fase 2):**

| Coluna | Tipo | Obrigatorio | Indice |
|--------|------|-------------|--------|
| id | UUID, PK | Sim | PK |
| ordem_pagamento | VARCHAR | Sim | - |
| processo_depre | VARCHAR | Sim | Sim (busca) |
| natureza | VARCHAR | Nao | - |
| es_ep | VARCHAR | Nao | - |
| autos | VARCHAR | Nao | Sim (busca) |
| ordem_orcamentaria | VARCHAR | Sim | - |
| suspenso | BOOLEAN | Sim | - |
| data_protocolo | DATE | Sim | - |
| protocolo_geral | VARCHAR | Nao | - |
| autos_antigos | VARCHAR | Nao | - |
| advogados | TEXT | Nao | - |
| devedora | VARCHAR | Sim | - |
| natureza_saldo | VARCHAR | Nao | - |
| saldo_depre | BIGINT (centavos) | Nao | - |
| cpf | VARCHAR, nullable | Nao | - |
| created_at | TIMESTAMPTZ | Sim (default NOW) | - |

**Acesso:** Leitura publica (anon SELECT), escrita bloqueada para client.

**Performance:**
- Query pura no banco: < 200ms
- Round-trip completo (frontend → Supabase → resposta renderizada): < 2s

### 2. Tabela `leads` — Dados de Leads

| Coluna | Tipo | Notas |
|--------|------|-------|
| id | UUID, PK | |
| nome | VARCHAR | Validacao: min 2 palavras |
| email | VARCHAR | UNIQUE composto com processo_depre |
| telefone | VARCHAR | Campo padrao de contato telefonico |
| whatsapp | VARCHAR | |
| cpf | VARCHAR, nullable | |
| relacao | VARCHAR (titular/herdeiro/advogado) | |
| processo_depre | VARCHAR, FK → precatorios | |
| saldo_consultado | BIGINT (centavos) | |
| devedora | VARCHAR | |
| token_email_validado | BOOLEAN, default false | |
| token_telefone_validado | BOOLEAN, default false | |
| origem | VARCHAR, nullable | |
| utm_source | VARCHAR, nullable | |
| utm_medium | VARCHAR, nullable | |
| utm_campaign | VARCHAR, nullable | |
| dispositivo | VARCHAR, nullable | |
| consent_comunicacao | BOOLEAN, default false | LGPD: "Concordo em receber comunicacoes sobre meu precatorio" |
| consent_marketing | BOOLEAN, default false | LGPD: "Desejo receber novidades e conteudo educativo" |
| consent_ip | TEXT, nullable | IP anonimizado no momento do consentimento |
| consent_at | TIMESTAMPTZ, nullable | Data/hora do consentimento |
| last_interaction_at | TIMESTAMPTZ, default NOW | Ultima interacao do usuario (para politica de retencao) |
| created_at | TIMESTAMPTZ, default NOW | |
| updated_at | TIMESTAMPTZ, default NOW | |

**Regras de negocio:**
- Lead so e salvo apos validacao **sequencial** de AMBOS os canais: primeiro e-mail, depois telefone
- O canal de telefone e sempre usado (nao SMS/WhatsApp alternativo) — telefone e o padrao
- Fluxo sequencial e intuitivo: (1) usuario preenche formulario → (2) recebe token por e-mail → (3) confirma token e-mail → (4) recebe token por telefone → (5) confirma token telefone → (6) lead salvo
- Mesmo e-mail pode consultar multiplos processos (gera multiplos leads)
- Lead duplicado (mesmo email + mesmo processo) = atualiza dados existentes
- Sessao persistente: e-mail/telefone ja validados ficam em cookie/localStorage no browser. Usuario recorrente que informa mesmo e-mail ou telefone ja validado pula validacao por token
- Consentimento LGPD obrigatorio: checkbox de comunicacao (obrigatorio) e checkbox de marketing (opcional) devem ser registrados com IP anonimizado e timestamp

**Politica de retencao de dados (LGPD):**
- Nome, email, telefone: retidos ate revogacao pelo titular ou 2 anos sem interacao
- CPF: retido ate revogacao ou cessao concluida
- Historico de consultas (funnel_events): 2 anos
- O campo `last_interaction_at` e atualizado a cada nova consulta ou interacao do usuario
- Implementacao de rotina de limpeza automatica pode ser feita em fase futura

**Acesso:** Zero acesso client. Somente via Edge Functions com service role.

### 3. Tabela `tokens` — Validacao de Contato

| Coluna | Tipo | Notas |
|--------|------|-------|
| id | UUID, PK | |
| lead_id | UUID, FK → leads | |
| codigo | VARCHAR | Hasheado (nunca plain text) |
| canal | VARCHAR (email/telefone) | Telefone e o canal padrao para validacao de contato |
| enviado_em | TIMESTAMPTZ | |
| expira_em | TIMESTAMPTZ | |
| tentativas | INT, default 0 | |
| validado | BOOLEAN, default false | |
| validado_em | TIMESTAMPTZ, nullable | |

**Acesso:** Zero acesso client. Somente via Edge Functions com service role.

### 4. Tabela `funnel_events` — Tracking do Funil

| Coluna | Tipo | Notas |
|--------|------|-------|
| id | BIGSERIAL, PK | |
| session_id | UUID, NOT NULL | Gerado no frontend com `crypto.randomUUID()`, persistido em `sessionStorage` |
| event_name | TEXT, NOT NULL | Enum logico: visited, searched, result_found, result_not_found, signup_started, email_token_sent, email_validated, phone_token_sent, phone_validated, lead_completed |
| user_agent | TEXT, nullable | Truncado em 512 chars |
| ip_anonymous | TEXT, nullable | Ultimo octeto IPv4 zerado / ultimos 80 bits IPv6 truncados. Anonimizacao server-side na Edge Function |
| context | JSONB, nullable | Dados esparsos por evento (search_term, process_id, etc.) |
| created_at | TIMESTAMPTZ, default NOW | Timestamp do servidor, nunca do client |

**Indices:** `session_id`, `event_name`, `created_at DESC`

**Arquitetura de ingestao:** Edge Function dedicada (`funnel-event`). Frontend faz POST fire-and-forget. A Edge Function:
- Le IP dos headers e anonimiza server-side
- Valida event_name contra whitelist
- Filtra campos do context por evento
- Insere via service role

**Acesso:** Zero acesso client. Somente via Edge Function com service role.

### 5. Seguranca (transversal)

**Criptografia:**
- At-rest padrao do Supabase (AES-256) e suficiente para MVP
- Sem pgcrypto column-level — evita complexidade de key management e perda de query flexibility
- Suficiente para LGPD Art. 46 no estagio MVP

**RLS (Row Level Security):**

```sql
-- Habilitar RLS em TODAS as tabelas
ALTER TABLE precatorios ENABLE ROW LEVEL SECURITY;
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
ALTER TABLE tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE funnel_events ENABLE ROW LEVEL SECURITY;

-- precatorios: leitura publica, sem escrita pelo client
CREATE POLICY "public_read_precatorios"
  ON precatorios FOR SELECT
  TO anon, authenticated
  USING (true);

REVOKE INSERT, UPDATE, DELETE ON precatorios FROM anon, authenticated;

-- leads, tokens, funnel_events: ZERO policies para anon/authenticated
-- Service role bypassa RLS automaticamente
```

**Verificacao pos-deploy obrigatoria:** testar que anon key NAO retorna dados de `leads`, `tokens`, `funnel_events`.

## USER STORIES

**US1 — Importacao da base DEPRE**
Como script de importacao, preciso inserir ~200K registros da planilha `precatorios_depre_completo.xlsx` no Supabase para que a base esteja consultavel pelo portal.

**US2 — Busca de precatorio**
Como visitante do portal, preciso buscar por Nº Processo DEPRE ou Nº de Autos para ver o saldo do meu precatorio em menos de 2 segundos.

**US3 — Persistencia de lead validado**
Como visitante que encontrou resultado positivo, preciso fornecer meus dados e validar e-mail + telefone sequencialmente para que meu lead seja salvo e eu receba os detalhes completos.

**US4 — Tracking do funil**
Como sistema, preciso registrar cada evento do funil (visited, searched, result_found, etc.) com session_id e IP anonimizado para analise posterior de conversao.

**US5 — Usuario recorrente**
Como visitante que ja validou meus dados anteriormente, preciso ser reconhecido pelo portal para consultar novos processos sem revalidar e-mail e telefone.

**US6 — Consentimento LGPD**
Como visitante, preciso dar consentimento explicito para comunicacoes e marketing, com registro de data/hora e IP, para que o portal esteja em conformidade com a LGPD.

---

## CRITERIOS DE ACEITE

### Base DEPRE
- [ ] Script Node.js importa 199.767 registros com sucesso (UPSERT idempotente)
- [ ] Busca por `processo_depre` retorna resultado com query pura < 200ms
- [ ] Busca por `autos` retorna resultado com query pura < 200ms
- [ ] Round-trip completo (frontend → Supabase → resposta) < 2s
- [ ] Registros com saldo exibem valor formatado corretamente (centavos → R$)
- [ ] Coluna `cpf` existe como nullable (sem dados no MVP)

### Leads
- [ ] Lead salvo somente apos validacao sequencial de AMBOS os canais (e-mail → telefone)
- [ ] Lead duplicado (mesmo email + mesmo processo) atualiza registro existente
- [ ] Campos de consentimento LGPD (`consent_comunicacao`, `consent_marketing`, `consent_ip`, `consent_at`) registrados corretamente
- [ ] `last_interaction_at` atualizado a cada nova interacao do usuario
- [ ] Usuario recorrente (email/telefone ja validado) reconhecido via localStorage e nao revalida

### Tokens
- [ ] Token armazenado como hash (nunca plain text)
- [ ] Campo `canal` aceita apenas `email` ou `telefone`
- [ ] Tentativas limitadas a 3 por token
- [ ] Token expira em 10 minutos

### Funnel Events
- [ ] 10 eventos tipados registrados corretamente via Edge Function
- [ ] IP anonimizado server-side (ultimo octeto IPv4 zerado)
- [ ] `session_id` gerado no frontend e persistido em `sessionStorage`
- [ ] Eventos com payload invalido rejeitados pela Edge Function

### Seguranca
- [ ] RLS habilitado em TODAS as 4 tabelas
- [ ] `precatorios`: anon pode SELECT, nao pode INSERT/UPDATE/DELETE
- [ ] `leads`, `tokens`, `funnel_events`: anon NAO retorna dados (verificacao com anon key)
- [ ] Service role key presente SOMENTE em Edge Functions (nunca no frontend)

---

## RISCOS E MITIGACOES

| Risco | Probabilidade | Impacto | Mitigacao |
|-------|--------------|---------|-----------|
| Dados sujos/inconsistentes na planilha Excel | Media | Medio | Script de importacao com validacao e log de registros rejeitados |
| Lovable nao configurar Supabase como esperado | Baixa | Alto | Documentar configuracao manual como fallback |
| Performance de busca degradada com ~200K registros | Baixa | Alto | Indices em `processo_depre` e `autos`, testar com volume real |
| Edge Functions (issue separada) atrasam, bloqueando fluxo end-to-end | Media | Alto | Modelagem de dados pode ser entregue independentemente; fluxo de lead depende das Edge Functions |
| localStorage limpo pelo usuario, perde sessao persistente | Media | Baixo | Fallback: re-identificar pelo email/telefone no formulario |

---

## DEPENDENCIAS

| Dependencia | Tipo | Status | Impacto |
|-------------|------|--------|---------|
| Projeto Lovable criado (provisiona Supabase) | Ambiente | Pendente | Bloqueante — sem Supabase nao ha banco |
| Arquivo `precatorios_depre_completo.xlsx` disponivel | Dados | Disponivel | Bloqueante — sem planilha nao ha importacao |
| Edge Functions de envio de token (issue separada) | Feature | Pendente | Nao-bloqueante para modelagem; bloqueante para fluxo de lead end-to-end |
| Edge Function de funnel-event (issue separada) | Feature | Pendente | Nao-bloqueante para modelagem; bloqueante para tracking funcional |

---

## CRITERIOS DE LANCAMENTO

Esta issue e considerada **done** quando:

1. **Banco criado**: Todas as 4 tabelas (`precatorios`, `leads`, `tokens`, `funnel_events`) criadas no Supabase com tipos, indices e constraints corretos
2. **RLS configurado**: Policies aplicadas e verificadas (teste com anon key confirma acesso apenas a `precatorios` SELECT)
3. **Base importada**: Script Node.js executado com sucesso — 199.767 registros acessiveis e consultaveis
4. **Performance validada**: Query por `processo_depre` e `autos` < 200ms comprovada com dados reais
5. **Schema de leads completo**: Tabela `leads` com todos os campos incluindo consentimento LGPD e `last_interaction_at`
6. **Tokens hasheados**: Tabela `tokens` criada com canal restrito a `email`/`telefone`
7. **Funnel events pronto**: Tabela `funnel_events` criada com indices, pronta para receber dados da Edge Function

> **Nota**: O fluxo end-to-end (formulario → token → lead salvo → tracking) depende de Edge Functions que sao escopo de issue separada. Esta issue entrega a **camada de dados completa e validada**.

---

## COMO

### Ambiente
- O banco Supabase sera criado automaticamente pelo Lovable ao criar o projeto
- Nao ha projeto Supabase pre-existente

### Importacao da base DEPRE
- Script Node.js standalone que le `precatorios_depre_completo.xlsx` e faz bulk insert via Supabase client (service role)
- O campo `saldo_depre` esta em centavos (inteiro) na planilha — armazenar como BIGINT
- Script idempotente: pode ser re-executado (UPSERT por `processo_depre`)

### Sessao persistente (usuario recorrente)
- Apos validacao bem-sucedida de ambos os canais, salvar no localStorage: `{ email, telefone, validated: true }`
- No retorno ao portal, quando usuario informa e-mail ou telefone, verificar no banco se ja foi validado
- Se ja validado: pular fluxo de token, permitir consulta direta

### Funnel tracking no frontend
- `session_id` gerado com `crypto.randomUUID()` e persistido em `sessionStorage` (nova aba = nova sessao)
- Funcao `trackEvent()` faz POST fire-and-forget para Edge Function — nunca bloqueia o fluxo do usuario
- Tipagem dos eventos com union types para garantir campos obrigatorios por evento em compile time

### Fora de escopo desta issue
- Edge Functions de envio de token (issue separada)
- Dashboard administrativo (issue 002)
- Crawler TJSP por CPF (issue 003)
- Importacao automatizada via PDF (Fase 2)
