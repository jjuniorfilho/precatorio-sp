# Regras Críticas — Consulta Precatório SP

> ⚠️ Copiar este arquivo integralmente para todo context.md antes de iniciar qualquer feature.

---

## 🔴 Regras Não-Negociáveis

### 1. Multi-tenancy / Segurança de dados
- **NUNCA** expor CPF completo — sempre mascarar (`123.***.***-00`)
- **NUNCA** expor dados de um lead para outro usuário
- **SEMPRE** usar RLS (Row Level Security) no Supabase para proteger tabelas de leads
- Tabela `precatorios` é pública (dados DEPRE são públicos)
- Tabelas `leads`, `tokens`, `funnel_events` são privadas (admin only)

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
- Lead só é completo após validar **dois canais**: e-mail E WhatsApp
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
leads               — leads completos (2 canais validados)
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
titular | herdeiro | advogado
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

## ✅ Checklist antes de implementar qualquer endpoint

- [ ] Endpoint protegido por RLS ou autenticação admin?
- [ ] Input normalizado antes de query?
- [ ] Valores monetários em centavos?
- [ ] CPF/CNPJ mascarado nas respostas públicas?
- [ ] Evento registrado em `funnel_events`?
- [ ] Índice de banco necessário criado?
