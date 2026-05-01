# Feature: Captura de Lead

## Resumo
Sistema de captura de dados de contato do titular do precatorio apos exibicao do resultado da consulta. O lead e qualificado por ter precatorio confirmado com saldo positivo e contato validado por token.

## Fase
**Fase 1 - MVP**

## Prioridade
**P0 - Critica** (principal objetivo de negocio)

---

## Descricao Funcional

### Trigger de Exibicao
O formulario de captura e apresentado APOS o usuario visualizar o resultado da consulta (saldo do precatorio). Nunca antes.

### Fluxo do Usuario
1. Usuario ve resultado da consulta (saldo DEPRE)
2. Sistema exibe CTA: "Receba os detalhes completos no seu e-mail"
3. Usuario preenche formulario
4. Sistema envia token de validacao
5. Usuario confirma token
6. Lead salvo no banco de dados
7. Detalhes completos enviados por e-mail e WhatsApp

### Formulario de Captura

**Campos Obrigatorios**:
| Campo | Tipo | Validacao | Placeholder |
|-------|------|-----------|-------------|
| Nome completo | Text | Min 2 palavras | "Seu nome completo" |
| E-mail | Email | Formato valido | "seu@email.com" |
| Telefone/WhatsApp | Tel | Formato BR (11 digitos) | "(11) 99999-9999" |
| Relacao com processo | Select | Opcao selecionada | "Sou o titular / Sou herdeiro / Sou advogado" |

**Campos Opcionais**:
| Campo | Tipo | Motivo |
|-------|------|--------|
| CPF | CPF mask | Preparacao para busca TJSP (Fase 2) |
| Como conheceu o site | Select | Atribuicao de canal |

### Dados do Lead Salvo
| Campo | Fonte |
|-------|-------|
| Nome, e-mail, telefone | Formulario |
| Relacao com processo | Formulario |
| Nº Processo consultado | Sessao de busca |
| Saldo do precatorio | Base DEPRE |
| Devedora | Base DEPRE |
| Data/hora da consulta | Sistema |
| Token e-mail validado | Sistema de validacao (obrigatorio) |
| Token telefone validado | Sistema de validacao (obrigatorio - SMS ou WhatsApp) |
| Origem/UTM | URL parameters |
| Dispositivo | User agent |

---

## Requisitos Tecnicos

### Banco de Dados (Supabase)
```
Tabela: leads
- id (UUID, PK)
- nome (VARCHAR)
- email (VARCHAR, UNIQUE por processo)
- telefone (VARCHAR)
- whatsapp (VARCHAR)
- cpf (VARCHAR, nullable)
- relacao (ENUM: titular, herdeiro, advogado)
- processo_depre (VARCHAR, FK)
- saldo_consultado (NUMERIC)
- devedora (VARCHAR)
- token_email_validado (BOOLEAN)
- token_sms_validado (BOOLEAN)
- token_whatsapp_validado (BOOLEAN)
- origem (VARCHAR)
- utm_source (VARCHAR)
- utm_medium (VARCHAR)
- utm_campaign (VARCHAR)
- dispositivo (VARCHAR)
- created_at (TIMESTAMP)
- updated_at (TIMESTAMP)
```

### Regras de Negocio
- Um e-mail pode consultar multiplos processos (gera multiplos leads)
- Mesmo processo pode ser consultado por diferentes pessoas
- Lead duplicado (mesmo email + mesmo processo) = atualiza dados
- Lead so e salvo apos validacao de AMBOS os canais (e-mail + telefone via SMS ou WhatsApp)
- Dados sensiveis criptografados (CPF, telefone)
- **Sessao persistente**: e-mail e telefone validados ficam salvos no banco. Se o usuario retornar ao portal e informar o mesmo e-mail ou telefone, o sistema reconhece e **nao exige nova validacao por token**. O usuario pode consultar novos processos diretamente, e os dados sao enviados para os canais ja validados

### Envio de Dados ao Usuario (pos-validacao)
Dados so sao enviados apos validacao de ambos os canais (e-mail + telefone):

| Destinatario | Canal | Conteudo | Timing | Pre-requisito |
|-------------|-------|----------|--------|---------------|
| Usuario | **E-mail** | Detalhes completos do precatorio | Imediato | Token e-mail validado |
| Usuario | **WhatsApp** | Resumo + link para detalhes | Imediato | Token telefone validado (SMS ou WhatsApp) |
| Equipe comercial | Sistema/E-mail | Novo lead qualificado | Imediato | Ambos validados |

---

## Metricas de Sucesso
| Metrica | Meta |
|---------|------|
| Taxa de conversao resultado→cadastro | > 40% |
| Taxa de preenchimento completo | > 80% |
| Taxa de validacao de token | > 80% |
| Leads capturados/mes | 100 |
| Custo por lead | < R$ 10 |

---

## Consideracoes de UX
- Formulario curto (4 campos obrigatorios max)
- Justificativa clara: "Para enviar os detalhes completos"
- Nenhuma mencao a "venda" ou "compra" neste momento
- Progress indicator durante validacao de token
- Mensagem de sucesso clara e proximos passos
- Opcao de "nao quero cadastrar" visivel (sem dark patterns)
- LGPD: checkbox de consentimento + link para politica de privacidade
