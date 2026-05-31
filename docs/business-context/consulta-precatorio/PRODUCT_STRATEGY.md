# Estrategia de Produto

## Visao

Ser a plataforma digital de referencia para titulares de precatorios do Estado de Sao Paulo consultarem seus creditos e, quando desejarem, cede-los de forma transparente, segura e 100% digital.

## Missao

Democratizar o acesso a informacao sobre precatorios, eliminando a assimetria de informacao entre titulares e compradores, enquanto geramos leads qualificados para operacao de compra de creditos judiciais.

---

## Posicionamento de Mercado

### Proposta de Valor Unica (UVP)
**"Consulte gratis o valor do seu precatorio em segundos"**

Enquanto concorrentes pedem dados de contato antes de oferecer qualquer informacao, nosso portal entrega valor real (saldo DEPRE) antes de solicitar qualquer coisa. Isso cria confianca e gera leads com intencao genuina.

### Posicionamento Competitivo

```
                    ENTREGA VALOR ANTES
                         |
            [NOS]        |     [Futuro ideal]
         Consulta real   |     Jornada completa
         + Lead capture  |     + Cessao digital
                         |
  SEM DIGITAL ───────────┼──────────── 100% DIGITAL
                         |
        [Concorrentes]   |     [Escritorios]
        Formulario cego  |     Atendimento manual
        + Cold call      |     + Processo presencial
                         |
                    NAO ENTREGA VALOR
```

---

## Principios de Produto

### 1. Valor Primeiro, Dados Depois
Sempre entregar algo util ao usuario antes de pedir informacoes pessoais. O saldo do precatorio e a moeda de troca pela atencao do usuario.

### 2. Simplicidade Extrema
O titular medio tem baixa familiaridade digital. Cada tela deve ter um unico objetivo claro. Maximo 2 cliques ate ver o resultado.

### 3. Mobile-First
Maioria dos usuarios acessa via smartphone. Todo o design e fluxo devem priorizar a experiencia mobile.

### 4. SEO como DNA
SEO nao e uma camada adicional - e parte da arquitetura. Cada pagina, cada URL, cada conteudo e otimizado para busca organica desde a concepcao.

### 5. Confianca como Diferencial
Em um mercado com historico de desconfianca, cada elemento do portal deve transmitir seguranca: dados publicos, CNPJ visivel, linguagem transparente, sem pressao.

### 6. Dados como Ativo
Cada interacao gera dados valiosos: quem consulta, quanto vale, quando consulta, de onde vem. Esses dados alimentam a estrategia comercial e de conteudo.

---

## Estrategia de Fases

### Fase 1 - MVP: Consulta + Lead Capture
**Objetivo**: Validar o modelo de lead generation via consulta gratuita
**Meta**: 100 leads/mes
**Escopo**:
- Landing page otimizada para SEO
- Busca por Nº Processo DEPRE, Nº de Autos, CPF e CNPJ do titular
- Deteccao automatica do tipo de input (processo, CPF ou CNPJ)
- Resultado unico para busca por processo; lista de precatorios para CPF/CNPJ
- Base de dados com ~200K registros importados (indexados por processo, CPF e CNPJ)
- Exibicao de resumo (saldo DEPRE sem atualizacao)
- Formulario de captura com validacao por token (e-mail, SMS, WhatsApp)
- Paginas institucionais com SEO (sobre, FAQ, como funciona)
- Estrutura SEO robusta (meta tags, schema markup, sitemap, paginas otimizadas)

**Stack**: Lovable + Supabase (banco de dados integrado)

### Fase 2 - Expansao: Blog IA + Atualizacao Monetaria
**Objetivo**: Multiplicar trafego organico e enriquecer dados
**Escopo**:
- Blog com conteudo gerado por IA (SEO content)
- Atualizacao monetaria dos valores
- Simulacao basica de venda
- Dashboard do usuario (historico de consultas)
- Integracao com Google Analytics e Search Console

### Fase 3 - Jornada Completa: Cessao Digital
**Objetivo**: Digitalizar 100% da jornada de compra de precatorio
**Escopo**:
- Proposta digital personalizada
- Negociacao online
- Assinatura digital de contrato
- Upload e validacao de documentos
- Acompanhamento de pagamento
- CRM integrado para gestao de leads e negociacoes

---

## Decisoes Estrategicas de Trade-off

| Decisao | Escolhemos | Em vez de | Motivo |
|---------|-----------|-----------|--------|
| Canal de aquisicao | SEO organico | Paid ads | Custo por lead menor a longo prazo, sustentabilidade |
| Primeiro valor | Mostrar saldo gratis | Pedir dados primeiro | Diferencial competitivo, confianca |
| Stack MVP | Lovable | Codigo custom | Velocidade de lancamento, validacao rapida |
| Validacao de contato | Token multi-canal | Sem validacao | Qualidade do lead justifica friccao |
| Dados exibidos | Saldo DEPRE sem atualizacao | Valor atualizado | Simplicidade do MVP, atualizacao na Fase 2 |
| Mobile vs Desktop | Mobile-first | Desktop-first | Perfil do publico-alvo |

---

## Riscos e Mitigacoes

| Risco | Probabilidade | Impacto | Mitigacao |
|-------|--------------|---------|-----------|
| TJSP bloquear crawler (Fase 2) | Media | Alto | Rate limiting, proxies, backup manual |
| Dados DEPRE desatualizados | Baixa | Medio | Atualizacao periodica da base, disclaimer claro |
| Concorrentes copiarem modelo | Alta | Medio | First-mover advantage, SEO consolidado, experiencia superior |
| Baixa conversao de lead | Media | Alto | Otimizacao continua do funil, A/B testing |
| Lovable nao escalar | Baixa | Medio | Migrar para VPS quando necessario |
| LGPD/compliance | Baixa | Alto | Termos de uso claros, dados publicos, consentimento explicito |

---

## Metricas de Sucesso por Fase

### Fase 1
| Metrica | Meta | Prazo |
|---------|------|-------|
| Visitantes unicos/mes | 5.000 | 3 meses |
| Consultas realizadas/mes | 2.500 | 3 meses |
| Leads capturados/mes | 100 | 3 meses |
| Taxa de conversao visitante→consulta | 50% | Contínuo |
| Taxa de conversao consulta→lead | 4% | Contínuo |
| Custo por lead | < R$ 10 (organico) | Contínuo |

### Fase 2
| Metrica | Meta | Prazo |
|---------|------|-------|
| Visitantes unicos/mes | 20.000 | 6 meses |
| Leads capturados/mes | 500 | 6 meses |
| Artigos blog publicados | 50+ | 6 meses |
| Posicao media Google (termos-chave) | Top 5 | 6 meses |
