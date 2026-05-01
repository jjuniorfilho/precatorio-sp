# Feature: Validacao por Token

## Resumo
Sistema de validacao de dados de contato por token numerico enviado por e-mail, SMS e WhatsApp. Garante que os leads capturados possuem dados de contato validos e funcionais.

## Fase
**Fase 1 - MVP**

## Prioridade
**P0 - Critica** (garante qualidade do lead)

---

## Descricao Funcional

### Fluxo de Validacao
1. Usuario preenche formulario de captura (e-mail + telefone obrigatorios)
2. **Etapa 1 - Validacao de e-mail**: Sistema envia token de 6 digitos para o e-mail
3. Usuario confirma token de e-mail
4. **Etapa 2 - Validacao de telefone**: Sistema envia token de 6 digitos por SMS ou WhatsApp (usuario escolhe)
5. Usuario confirma token de telefone
6. **Ambos validados** = lead aceito e dados enviados por e-mail + WhatsApp

### Regra Obrigatoria
Os dados do precatorio sao enviados ao usuario por **e-mail** e **WhatsApp**. Por isso, ambos os canais devem ser validados antes do envio:
- **E-mail**: validacao obrigatoria (token por e-mail)
- **Telefone**: validacao obrigatoria (token por SMS ou WhatsApp, a escolha do usuario)

### Canais de Envio
| Canal | Prioridade | Custo | Confiabilidade |
|-------|-----------|-------|----------------|
| E-mail | Alta | Baixo | Media (spam) |
| SMS | Media | Medio | Alta |
| WhatsApp | Alta | Medio | Muito alta |

### Regras de Token
| Regra | Valor |
|-------|-------|
| Formato | 6 digitos numericos |
| Validade | 10 minutos |
| Tentativas maximas | 3 por token |
| Cooldown para re-envio | 60 segundos |
| Tokens por sessao | Maximo 5 (anti-abuse) |
| Canais minimos validados | 2 (e-mail + telefone) |

### Cenarios
| Cenario | Comportamento |
|---------|---------------|
| Token correto no prazo | Sucesso → lead salvo |
| Token expirado | Mensagem + opcao re-envio |
| 3 tentativas erradas | Novo token gerado automaticamente |
| 5 tokens na sessao | Bloqueio temporario (30 min) |
| E-mail vai para spam | Instrucao para verificar spam + opcao SMS/WhatsApp |
| SMS nao chega | Opcao de re-envio + alternativa WhatsApp |
| **Usuario retorna ao portal** | Sistema reconhece e-mail ou telefone ja validado → **pula validacao por token** e permite consulta direta |

### Sessao Persistente (Usuario Recorrente)
- E-mail e telefone validados sao persistidos no Supabase
- Quando usuario informa e-mail ou telefone ja cadastrado e validado, o sistema o reconhece automaticamente
- Nao e necessario revalidar por token em visitas futuras
- Novas consultas geram novos registros de lead vinculados ao usuario existente
- Dados do precatorio sao enviados diretamente para os canais ja validados

---

## Requisitos Tecnicos

### Banco de Dados
```
Tabela: tokens
- id (UUID, PK)
- lead_id (UUID, FK)
- codigo (VARCHAR, 6 digitos)
- canal (ENUM: email, sms, whatsapp)
- enviado_em (TIMESTAMP)
- expira_em (TIMESTAMP)
- tentativas (INT, default 0)
- validado (BOOLEAN, default false)
- validado_em (TIMESTAMP, nullable)
```

### Servicos de Envio
| Canal | Servico Sugerido | Alternativa |
|-------|-----------------|-------------|
| E-mail | Resend / SendGrid | Supabase Auth email |
| SMS | Twilio | Zenvia |
| WhatsApp | Twilio WhatsApp / Z-API | Evolution API |

### Seguranca
- Tokens hasheados no banco (nao armazenar plain text)
- Rate limiting por IP e por telefone/email
- Logs de tentativas para deteccao de abuso
- CAPTCHA apos 2 re-envios (anti-bot)

---

## Metricas de Sucesso
| Metrica | Meta |
|---------|------|
| Taxa de validacao (ambos canais) | > 70% |
| Tempo medio ate validacao | < 2 minutos |
| Taxa de abandono no token | < 20% |
| Canal mais usado | WhatsApp (estimativa) |

---

## Consideracoes de UX
- Campo de input com 6 caixas individuais (estilo PIN)
- Auto-focus no proximo digito
- Countdown visivel para expiracao
- Botao "Reenviar codigo" com timer de cooldown
- Indicacao clara de qual canal foi enviado
- Opcao de trocar canal se nao recebeu
- Mensagem de sucesso animada apos validacao
