# Diretrizes de Comunicacao com o Cliente

## Principios de Comunicacao

### 1. Valor Antes de Pedido
Toda interacao deve entregar algo util antes de solicitar algo do usuario. Na landing page, o saldo e entregue antes do cadastro. No follow-up, informacao e entregue antes da proposta.

### 2. Transparencia Total
- Sempre informar a fonte dos dados ("Base publica do DEPRE")
- Nunca ocultar termos ou condicoes
- Explicar claramente o que e a empresa e como ganha dinheiro
- Usar linguagem que o titular entende, nao juridiquês

### 3. Respeito ao Tempo do Cliente
- Sem pressao para decisao imediata
- Sem ligacoes nao solicitadas (apenas resposta a contato)
- Frequencia de mensagens controlada
- Opcao clara de opt-out em todos os canais

### 4. Empatia Contextual
- Reconhecer que muitos titulares dependem desse dinheiro
- Entender que herdeiros lidam com perda familiar
- Nao trivializar a importancia do precatorio para o titular
- Adaptar tom conforme o perfil (titular vs herdeiro vs advogado)

---

## Diretrizes por Canal

### Site (Portal Web)

**Tom**: Informativo, direto, confiavel
**Regras**:
- Maximo 1 CTA por tela
- Sem pop-ups intrusivos
- Sem contadores falsos ("X pessoas consultando agora")
- Sem urgencia artificial
- FAQ acessivel em toda pagina
- Politica de privacidade e termos sempre visiveis

### E-mail

**Tom**: Profissional-amigavel
**Regras**:
- Assunto claro e descritivo (nao clickbait)
- Remetente identificavel: "[Nome] da [Empresa]"
- Unsubscribe em todo e-mail
- Maximo 2 e-mails/semana (exceto transacionais)
- Templates responsivos (mobile-first)
- Conteudo scannable (bullets, headers, destaque)

**Sequencia permitida**:
| Tipo | Frequencia Max | Consentimento |
|------|---------------|---------------|
| Transacional (token, confirmacao) | Ilimitado | Implicito |
| Informativo (detalhes precatorio) | 1x apos cadastro | Implicito |
| Educativo (blog, guias) | 1x/semana | Opt-in |
| Comercial (proposta, follow-up) | 1x/semana | Opt-in |

### WhatsApp

**Tom**: Pessoal, consultivo, respeitoso
**Regras**:
- Primeira mensagem sempre referencia a consulta feita
- Nao enviar mensagens fora do horario comercial (8h-18h)
- Responder em ate 2 horas durante horario comercial
- Usar nome do atendente real (nao generico)
- Nao enviar audios longos (max 30 segundos)
- Nao enviar correntes, memes ou conteudo nao relacionado
- Maximo 1 mensagem proativa por semana (exceto respostas)

**Horarios permitidos**:
| Dia | Horario |
|-----|---------|
| Segunda a Sexta | 8h - 18h |
| Sabado | 9h - 13h |
| Domingo/Feriado | Nao enviar |

### SMS

**Tom**: Ultra-conciso, funcional
**Regras**:
- Apenas para tokens de validacao
- Nao usar para marketing
- Identificacao do remetente sempre presente
- Maximo 160 caracteres

### Telefone

**Tom**: Consultivo, profissional
**Regras**:
- Apenas em resposta a solicitacao do lead
- Nao fazer cold calls
- Identificar-se imediatamente
- Perguntar se e bom momento para conversar
- Nao pressionar para decisao na ligacao
- Enviar resumo por WhatsApp apos a ligacao

---

## Cenarios de Comunicacao

### Cenario 1: Lead Acabou de se Cadastrar
```
Canal: E-mail + WhatsApp (simultaneo)
Timing: Imediato
Conteudo: Detalhes do precatorio consultado
Tom: Acolhedor, informativo
CTA: "Tem alguma duvida? Responda esta mensagem"
NAO fazer: Mencionar venda, cessao ou desagio
```

### Cenario 2: Lead Nao Respondeu em 5 Dias
```
Canal: WhatsApp
Timing: D+5
Conteudo: "Ola [Nome], enviamos os detalhes do seu precatorio. 
          Conseguiu visualizar? Se tiver duvidas, estamos aqui."
Tom: Gentil, sem pressao
CTA: Aberto para resposta
NAO fazer: Enviar proposta, ser insistente
```

### Cenario 3: Lead Interessado em Vender
```
Canal: WhatsApp + E-mail (proposta formal)
Timing: Imediato apos manifestacao de interesse
Conteudo: Explicacao do processo + proposta com valores
Tom: Profissional, detalhado, transparente
CTA: "Avalie com calma. Estamos a disposicao"
NAO fazer: Pressionar, criar urgencia falsa
```

### Cenario 4: Lead Diz Que Nao Quer Vender
```
Canal: WhatsApp (resposta)
Timing: Imediato
Conteudo: "Sem problema! A consulta do saldo e sempre gratuita. 
          Se mudar de ideia no futuro, estaremos aqui."
Tom: Respeitoso, sem insistencia
CTA: Nenhum
NAO fazer: Argumentar, enviar mais mensagens
```

### Cenario 5: Herdeiro Buscando Orientacao
```
Canal: WhatsApp + E-mail
Timing: Ate 2 horas
Conteudo: Explicacao sobre processo de habilitacao + documentos necessarios
Tom: Empatico, orientador
CTA: "Podemos ajudar a entender os proximos passos"
NAO fazer: Ser frio/protocolar, focar em venda
```

---

## LGPD e Compliance

### Consentimento
- Checkbox explicito no formulario: "Concordo em receber comunicacoes sobre meu precatorio"
- Consentimento separado para marketing: "Desejo receber novidades e conteudo educativo"
- Registrar data/hora/IP de cada consentimento
- Link para politica de privacidade em todos os formularios

### Direitos do Titular (LGPD)
| Direito | Como Atender |
|---------|-------------|
| Acesso | Fornecer dados armazenados em ate 15 dias |
| Correcao | Permitir atualizar dados via portal ou contato |
| Exclusao | Excluir dados em ate 15 dias apos solicitacao |
| Portabilidade | Exportar dados em formato padrao |
| Revogacao | Cancelar consentimento a qualquer momento |

### Dados Armazenados
| Dado | Base Legal | Retencao |
|------|-----------|----------|
| Nome, e-mail, telefone | Consentimento | Ate revogacao ou 2 anos sem interacao |
| CPF (quando informado) | Consentimento | Ate revogacao ou cessao concluida |
| Historico de consultas | Interesse legitimo | 2 anos |
| Dados do precatorio | Dados publicos | Indefinido |

---

## Escalacao de Situacoes

| Situacao | Acao | Responsavel |
|----------|------|-------------|
| Reclamacao sobre comunicacao | Pedir desculpas + reduzir frequencia | Atendente |
| Solicitacao LGPD | Encaminhar para responsavel | DPO/Juridico |
| Lead agressivo/insatisfeito | Encerrar contato educadamente | Supervisor |
| Suspeita de fraude | Bloquear + reportar | Seguranca |
| Duvida juridica complexa | Nao responder + encaminhar | Juridico |
