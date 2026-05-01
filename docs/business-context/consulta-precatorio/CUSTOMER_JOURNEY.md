# Jornada do Cliente

## Visao Geral

A jornada do cliente e desenhada como um funil de valor progressivo: o usuario recebe valor (consulta gratuita) antes de ser solicitado a fornecer dados de contato. Isso inverte a logica dos concorrentes que pedem dados primeiro.

```
[Busca Google] → [Landing Page] → [Consulta Processo] → [Ve Resumo]
     → [Fornece Contato] → [Valida Token] → [Recebe Detalhes]
     → [Contato Comercial] → [Proposta] → [Cessao de Credito]
```

---

## Fase 1: Descoberta (Awareness)

### Trigger Events
- Titular recebe notificacao do tribunal sobre precatorio
- Herdeiro descobre precatorio durante inventario
- Advogado precisa consultar saldo atualizado
- Titular ouve falar que precatorios estao sendo pagos
- Noticia na midia sobre pagamento de precatorios pelo Estado de SP

### Canais de Descoberta
| Canal | Estrategia | Fase |
|-------|-----------|------|
| **Google Organico** | SEO robusto com paginas otimizadas por termo de busca | Fase 1 |
| **Blog IA** | Conteudo educativo sobre precatorios gerado por IA | Fase 2 |
| **Google Ads** | Campanhas PPC para termos de alta intencao | Futuro |
| **Indicacao** | Programa de indicacao entre titulares/advogados | Futuro |

### Keywords de Busca Prioritarias
**Alta Intencao (transacionais)**:
- "consultar precatorio SP"
- "valor precatorio depre"
- "saldo precatorio estado sao paulo"
- "consulta precatorio pelo numero do processo"

**Media Intencao (informacionais)**:
- "como saber valor do meu precatorio"
- "quando vou receber meu precatorio SP"
- "precatorio alimentar SP pagamento"
- "vender precatorio vale a pena"

**Cauda Longa (especificas)**:
- "consultar precatorio fazenda estado sao paulo"
- "precatorio SPPREV valor atualizado"
- "herdeiro precatorio como consultar"
- "cessao de credito precatorio SP"

---

## Fase 2: Consideracao (Evaluation)

### Etapa 2.1: Landing Page
**Objetivo**: Converter visitante em usuario que faz consulta

| Elemento | Descricao |
|----------|-----------|
| **Headline** | Foco em beneficio: "Consulte gratis o valor do seu precatorio" |
| **Subheadline** | Credibilidade: base com 200mil+ processos do DEPRE |
| **Campo de busca** | Destaque visual, busca por Nº Processo DEPRE ou Nº de Autos |
| **Prova social** | Numero de consultas realizadas, depoimentos |
| **FAQ** | Perguntas frequentes sobre precatorios (SEO) |
| **Trust signals** | Dados publicos, seguranca, LGPD |

**Metricas desta etapa**:
- Taxa de bounce < 40%
- Taxa de busca realizada > 50% dos visitantes

### Etapa 2.2: Resultado da Consulta (Resumo)
**Objetivo**: Gerar interesse e motivar cadastro

**Informacoes exibidas (sem cadastro)**:
- Nº Processo DEPRE
- Devedora (ex: Fazenda do Estado de SP)
- Saldo DEPRE (valor sem atualizacao monetaria)
- Status (Ativo/Suspenso)
- Natureza (Alimentar/Outras)

**Informacoes bloqueadas (requer cadastro)**:
- Detalhes completos do processo
- Orientacao sobre proximo passo
- Estimativa de prazo de pagamento
- Opcao de simulacao de venda (futuro)

**Metricas desta etapa**:
- Taxa de resultado encontrado > 60% das buscas
- Taxa de clique em "Ver detalhes" > 40%

---

## Fase 3: Captura do Lead (Conversion)

### Etapa 3.1: Formulario de Contato
**Objetivo**: Capturar dados verificados do titular

**Campos obrigatorios**:
| Campo | Validacao | Motivo |
|-------|-----------|--------|
| Nome completo | Min 2 palavras | Identificacao |
| E-mail | Formato valido + token | Comunicacao formal |
| Telefone/WhatsApp | Formato valido + token | Comunicacao direta |
| Relacao com processo | Titular / Herdeiro / Advogado | Segmentacao |

**Campos opcionais**:
| Campo | Motivo |
|-------|--------|
| CPF | Preparacao para Fase 2 (busca TJSP) |
| Preferencia de contato | Personalizacao |

### Etapa 3.2: Validacao por Token
**Objetivo**: Garantir dados de contato validos

**Fluxo sequencial**:
1. Envio de token de 6 digitos por e-mail
2. Usuario confirma token de e-mail
3. Envio de token de 6 digitos por telefone
4. Usuario confirma token de telefone
5. Ambos validados → lead salvo no banco

**Regras**:
- Token expira em 10 minutos
- Maximo 3 tentativas por canal
- Re-envio disponivel apos 60 segundos
- AMBOS os canais devem ser validados (e-mail + telefone) — sequencialmente

**Metricas desta etapa**:
- Taxa de preenchimento do formulario > 60% (de quem viu resultado)
- Taxa de validacao de token > 80%
- Taxa de abandono no token < 20%

---

## Fase 4: Relacionamento (Nurturing)

### Pos-captura Imediata
| Acao | Canal | Timing |
|------|-------|--------|
| E-mail de boas-vindas com detalhes do precatorio | E-mail | Imediato |
| Mensagem WhatsApp com resumo | WhatsApp | Imediato |
| Notificacao interna para equipe comercial | Sistema | Imediato |

### Follow-up Automatizado
| Dia | Acao | Canal |
|-----|------|-------|
| D+0 | Detalhes do precatorio + explicacao | E-mail + WhatsApp |
| D+2 | Conteudo educativo: "Como funciona a venda de precatorio" | E-mail |
| D+5 | Contato comercial consultivo | WhatsApp/Telefone |
| D+10 | Oferta personalizada | E-mail + WhatsApp |
| D+15 | Follow-up se nao respondeu | WhatsApp |
| D+30 | Reengajamento com atualizacao de valor | E-mail |

---

## Fase 5: Conversao Comercial (Purchase)

### Processo de Venda (Futuro - Fase 3)
1. **Proposta digital**: Simulacao de valor com desagio
2. **Negociacao**: Ajuste de termos via WhatsApp/telefone
3. **Aceite**: Assinatura digital do contrato de cessao
4. **Documentacao**: Upload e validacao de documentos
5. **Pagamento**: Transferencia ao titular
6. **Acompanhamento**: Dashboard de status

---

## Fase 6: Pos-Venda e Advocacia

### Acoes de Retencao e Indicacao
- Pesquisa de satisfacao apos cessao
- Programa de indicacao (titular indica outros titulares)
- Conteudo continuo sobre precatorios
- Notificacao sobre novos precatorios (se houver)

---

## Mapa de Emocoes por Fase

| Fase | Emocao Dominante | Acao do Sistema |
|------|-----------------|-----------------|
| Descoberta | Curiosidade + Desconfianca | Transmitir credibilidade e valor gratuito |
| Consulta | Ansiedade + Esperanca | Mostrar dados concretos rapidamente |
| Resultado | Surpresa + Validacao | Confirmar que o precatorio existe e tem valor |
| Cadastro | Hesitacao | Justificar pedido de dados, reforcar seguranca |
| Validacao | Impaciencia | Processo rapido e claro |
| Relacionamento | Confianca crescente | Entregar valor antes de vender |
| Conversao | Decisao + Medo | Transparencia total nos termos |
| Pos-venda | Alivio + Satisfacao | Acompanhamento proativo |
