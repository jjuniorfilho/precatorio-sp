# Processo de Vendas

## Visao Geral

O processo de vendas segue um modelo de inbound marketing: o lead chega qualificado pelo portal (saldo positivo + contato validado) e e abordado por equipe comercial com contexto completo sobre o precatorio. O objetivo e converter o lead em cessao de credito.

---

## Funil de Vendas

```
[Visitante] → 5.000/mes
    ↓ (50% buscam)
[Busca Realizada] → 2.500/mes
    ↓ (60% encontram resultado)
[Resultado Encontrado] → 1.500/mes
    ↓ (40% preenchem formulario)
[Lead Capturado] → 600/mes (meta: 100 validados)
    ↓ (80% validam token)
[Lead Validado] → ~100/mes
    ↓ (80% contatados)
[Contato Efetivo] → 80/mes
    ↓ (40% respondem)
[Lead Qualificado] → 32/mes
    ↓ (50% recebem proposta)
[Proposta Enviada] → 16/mes
    ↓ (30% fecham)
[Cessao Realizada] → 5/mes
```

---

## Etapas do Processo Comercial

### Etapa 1: Notificacao de Novo Lead
**Timing**: Imediato apos validacao do token
**Dados disponiveis para o comercial**:
- Nome, e-mail, telefone/WhatsApp
- Relacao com processo (titular/herdeiro/advogado)
- Nº do processo consultado
- Saldo DEPRE
- Devedora
- Data/hora da consulta
- Dispositivo e origem

### Etapa 2: Primeiro Contato
**Timing**: Ate 2 horas apos lead (horario comercial)
**Canal**: WhatsApp (prioridade) → Telefone → E-mail
**Abordagem**:
- Tom consultivo, NAO vendedor
- Referenciar a consulta que o lead fez
- Oferecer informacoes adicionais sobre o precatorio
- Perguntar se tem duvidas
- NAO mencionar compra/cessao no primeiro contato

**Script sugerido (WhatsApp)**:
> "Ola [Nome], tudo bem? Vi que voce consultou o precatorio [Nº Processo] 
> no nosso portal. Sou [Nome] da [Empresa]. Se tiver qualquer duvida 
> sobre seu precatorio, estou a disposicao para ajudar!"

### Etapa 3: Qualificacao
**Timing**: D+2 a D+5
**Objetivo**: Entender situacao e intencao do lead

**Perguntas de qualificacao**:
1. Voce e o titular do precatorio ou herdeiro?
2. Sabe ha quanto tempo o precatorio foi expedido?
3. Tem advogado acompanhando o processo?
4. Ja pensou em antecipar o recebimento?
5. Tem alguma urgencia financeira?

**Classificacao do lead**:
| Score | Criterio | Acao |
|-------|---------|------|
| **Quente** | Quer vender, saldo > R$ 5.000, titular direto | Proposta imediata |
| **Morno** | Interessado mas comparando, ou herdeiro sem docs | Nurturing + proposta |
| **Frio** | So queria consultar, sem intencao de venda | Nurturing automatico |

### Etapa 4: Proposta
**Timing**: D+5 a D+10 (para leads quentes)
**Conteudo da proposta**:
- Valor do precatorio (saldo DEPRE)
- Percentual de desagio oferecido
- Valor liquido para o titular
- Documentos necessarios
- Prazo para pagamento apos cessao
- Termos e condicoes

### Etapa 5: Negociacao
**Canal**: WhatsApp + Telefone
**Pontos de negociacao**:
- Percentual de desagio
- Prazo de pagamento
- Forma de pagamento (PIX, TED)
- Divisao de custos cartorarios

### Etapa 6: Fechamento (Fase 3 - Digital)
1. Aceite digital da proposta
2. Upload de documentos (RG, CPF, comprovante endereco, procuracao se herdeiro)
3. Minuta do contrato de cessao
4. Assinatura digital
5. Registro em cartorio
6. Pagamento ao titular

---

## Objecoes Comuns e Respostas

| Objecao | Resposta |
|---------|---------|
| "O desagio e muito alto" | "Vamos comparar: se esperar o Estado pagar, pode levar X anos. Recebendo agora, voce tem R$ Y para usar imediatamente" |
| "Meu advogado disse para nao vender" | "Entendemos e respeitamos. Se mudar de ideia, estamos aqui. Enquanto isso, a consulta do saldo e sempre gratuita" |
| "Preciso pensar" | "Sem pressa! Vou enviar um resumo por e-mail para voce avaliar com calma" |
| "Outra empresa ofereceu mais" | "Posso revisar a proposta. Alem do valor, compare: prazo de pagamento, seguranca juridica e transparencia" |
| "Nao confio em empresas de precatorio" | "Entendo a preocupacao. Nosso CNPJ e [X], temos [Y] cessoes realizadas. Posso enviar referencias?" |
| "Preciso consultar meu advogado" | "Otimo! Posso enviar os detalhes para ele tambem?" |

---

## Automacoes de Vendas

### Nurturing Automatizado
| Dia | Canal | Conteudo | Segmento |
|-----|-------|---------|----------|
| D+0 | E-mail + WhatsApp | Detalhes do precatorio | Todos |
| D+2 | E-mail | "Como funciona a venda de precatorio" | Todos |
| D+5 | WhatsApp | Contato consultivo | Quente + Morno |
| D+10 | E-mail | "3 motivos para antecipar seu precatorio" | Morno + Frio |
| D+15 | WhatsApp | Follow-up | Morno |
| D+30 | E-mail | Atualizacao de valor/noticias | Frio |
| D+60 | E-mail | Re-engajamento | Frio |

### Triggers de Reativacao
- Lead consulta novo processo no portal
- Noticia sobre pagamento de precatorios SP
- Atualizacao de valor na base DEPRE
- Aniversario da consulta (anual)

---

## KPIs Comerciais

| Metrica | Meta |
|---------|------|
| Tempo ate primeiro contato | < 2 horas |
| Taxa de resposta ao primeiro contato | > 40% |
| Taxa de qualificacao | > 50% |
| Taxa de proposta (sobre qualificados) | > 50% |
| Taxa de fechamento (sobre propostas) | > 30% |
| Ciclo de venda medio | < 30 dias |
| NPS pos-cessao | > 50 |
