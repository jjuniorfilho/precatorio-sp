# Regras Críticas — Consulta Precatório SP

> ⚠️ Copiar este arquivo integralmente para todo context.md antes de iniciar qualquer feature.

---

## 🔴 Regras Não-Negociáveis

### 1. Multi-tenancy / Segurança de dados
- **NUNCA** expor CPF completo — sempre mascarar (`123.***.***-00`) *(única exceção aprovada: o painel do operador admin autenticado no lead avulso — ver "Exceções aprovadas" abaixo)*
- **NUNCA** expor dados de um lead para outro usuário
- **SEMPRE** usar RLS (Row Level Security) no Supabase para proteger tabelas de leads
- Tabela `precatorios` é pública (dados DEPRE são públicos)
- Tabelas `leads`, `tokens`, `funnel_events` são privadas: leitura e alteração só admin. Exceção estreita: o `anon` pode apenas **inserir** em `leads` (cadastro do site, com `lgpd_consent = true`; a policy `anon_insert_leads` bloqueia `origem = 'avulso'`, `criado_por` e `documento`) e em `funnel_events` (tracking)

### 2. Busca tolerante a formato
- **SEMPRE** normalizar input antes de buscar: remover `.`, `-`, `/`, espaços
- Aceitar processo com e sem pontuação: `0122089-09.2025.8.26.0500` = `01220890920258260500`
- Aceitar CPF com e sem máscara: `123.456.789-00` = `12345678900`
- Aceitar CNPJ com e sem máscara

### 3. Valores monetários
- **SEMPRE** armazenar saldo em **centavos** (integer) no banco
- **SEMPRE** exibir como `R$ X.XXX,XX` usando `Intl.NumberFormat('pt-BR')`
- Nunca usar `float` para valores monetários

### 4. Fluxo de captura de lead
- Lead do site só é completo após validar **dois canais**: e-mail E WhatsApp *(exceção aprovada: lead avulso — ver "Exceções aprovadas" abaixo)*
- Token expira em 10 minutos
- Limite de 3 tentativas por token antes de bloquear 30 min
- Registrar cada etapa em `funnel_events` para analytics

### 5. Performance
- Busca de precatório: < 2 segundos (índice por processo_depre, autos, cpf_titular, cnpj_titular)
- Base com ~200K registros — indexar corretamente
- Cache de consultas frequentes no Supabase

---

## 🟡 Convenções Obrigatórias

### Nomenclatura de tabelas (snake_case)
```
precatorios         — base DEPRE importada
leads               — leads do site (2 canais validados), leads só com e-mail (`capturar-lead-publico`) e leads avulsos (`origem = 'avulso'`, cadastrados pelo operador)
tokens              — tokens OTP gerados
funnel_events       — eventos do funil (busca, cadastro, token, etc.)
lead_status_history — histórico de mudança de CRM status
```

### Enums de status CRM
```
novo → contatado → qualificado → interessado → proposta → negociacao → fechado | descartado
```

### Tipos de relação do lead
```
titular | herdeiro | advogado   (opcional: NULL em lead avulso e em lead só com e-mail)
```

### Canais de token
```
email | whatsapp
```

### Etapas do funil (funnel_events.event_type)
```
busca_realizada
resultado_exibido
cadastro_iniciado
token_email_enviado
token_email_validado
token_whatsapp_enviado
token_whatsapp_validado
lead_completo
```

---

## 🟠 Exceções aprovadas (FOR-172 / FOR-173 — decididas pelo humano em 2026-09-28)

O **lead avulso** é um lead cadastrado pelo operador no admin (`/admin/leads` → "Novo lead avulso"), sem passar pelo fluxo público. Ele abre duas exceções **conscientes e limitadas**. Fora delas, as regras 1 e 4 continuam valendo integralmente.

1. **Regra 4 (2 canais validados):** lead avulso **não** valida e-mail nem WhatsApp. Ele é sempre identificado por `leads.origem = 'avulso'` e:
   - fica **fora das métricas do funil público** (filtro `origem IS DISTINCT FROM 'avulso'`; `funnel_events` não recebe eventos dele);
   - tem `lgpd_consent = false` (não há consentimento do titular) → **nenhuma comunicação automática pode partir dele** (relatório, e-mail de andamentos, WhatsApp);
   - `email`, `telefone`, `nome` e `relacao` são opcionais (NULL quando o operador não digitou).
2. **Regra 1 (CPF completo):** o admin **autenticado** (server function com `requireSupabaseAuth` + `ensureAdmin` + `service_role`) vê o titular do DEPRE sem máscara no painel do lead avulso. **Nunca** via `anon`, **nunca** em log, **nunca** em RPC anônima. O CPF/CNPJ pesquisado é guardado em `leads.documento` (só dígitos; PII protegida por `leads_admin_only`).

---

## ✅ Checklist antes de implementar qualquer endpoint

- [ ] Endpoint protegido por RLS ou autenticação admin?
- [ ] Input normalizado antes de query?
- [ ] Valores monetários em centavos?
- [ ] CPF/CNPJ mascarado nas respostas públicas?
- [ ] Evento registrado em `funnel_events`?
- [ ] Índice de banco necessário criado?
