# Business Context - Portal de Consulta de Precatorios

## Perfil do Negocio

| Campo | Valor |
|-------|-------|
| **Produto** | Portal Web de Consulta Gratuita de Precatorios |
| **Empresa** | [Nome a definir] - Empresa de compra de precatorios do Estado de SP |
| **Organizacao** | PX Ativos Judiciais |
| **Modelo de Negocio** | Lead Generation → Compra de Precatorios (cessao de credito) |
| **Mercado** | Precatorios estaduais de Sao Paulo |
| **Publico-Alvo** | Pessoas fisicas titulares de precatorios ou herdeiros |
| **Canal Principal** | Busca organica (Google SEO) |
| **Base de Dados** | 199.767 processos DEPRE | 124.071 com saldo positivo | R$ 2,13 bi total |
| **Stack Tecnica** | Lovable (MVP) → VPS (escala futura) |
| **Meta Inicial** | 100 leads qualificados/mes |

## Proposta de Valor

Oferecer **consulta gratuita e imediata do saldo de precatorios** como isca de valor para capturar leads qualificados com saldo positivo confirmado. Diferente dos concorrentes que apenas capturam dados sem entregar nada em troca, este portal entrega valor real antes de solicitar informacoes de contato.

## Fases do Produto

### Fase 1 - MVP (Atual)
- Busca por Nº Processo DEPRE ou Nº de Autos
- Consulta em base de ~200K registros importados da planilha DEPRE
- Exibicao de resumo com saldo DEPRE (sem atualizacao monetaria)
- Captura de e-mail, telefone e WhatsApp com validacao por token
- Estrutura robusta de SEO em todo o site
- Lead qualificado = saldo positivo + contato verificado

### Fase 2 - Expansao
- Busca por CPF via **VPS + Playwright** no TJSP (esaj.tjsp.jus.br) - servico REST separado que recebe CPF, faz busca headless no TJSP e cruza resultados com base DEPRE
- Arquitetura: Supabase Edge Function → API REST na VPS (Node.js + Playwright + Chromium headless)
- Infraestrutura: VPS pequena (~$6/mes Hetzner/DO, 2GB RAM), anti-bloqueio com delay 2-3s, 2captcha se necessario
- Referencia: scrapers open source (courtsbr/tjsp, jjesusfilho/tjsp)
- Blog com conteudo gerado por IA para trafego organico
- Atualizacao monetaria dos valores
- Simulacao de venda do precatorio
- Importacao automatizada da base a partir dos 2 PDFs que compoem a base DEPRE

### Fase 3 - Jornada Completa
- Proposta digital de compra
- Aceite e assinatura digital
- Gestao documental
- Acompanhamento do pagamento
- Jornada digital end-to-end do autor ate a cessao do credito

## Arquitetura de Contexto de Negocio

### Layer 1: Contexto do Cliente
- [Personas de Clientes](CUSTOMER_PERSONAS.md)
- [Jornada do Cliente](CUSTOMER_JOURNEY.md)
- [Voz do Cliente](VOICE_OF_CUSTOMER.md)

### Layer 2: Contexto do Produto
- [Estrategia de Produto](PRODUCT_STRATEGY.md)
- [Catalogo de Features](features/)
  - [Consulta de Precatorios](features/consulta-precatorios.md)
  - [Captura de Lead](features/lead-capture.md)
  - [Validacao por Token](features/token-validation.md)
  - [SEO e Performance](features/seo-performance.md)
  - [Blog com IA](features/blog-ia.md)
- [Metricas de Produto](PRODUCT_METRICS.md)

### Layer 3: Contexto de Mercado e Competicao
- [Panorama Competitivo](COMPETITIVE_LANDSCAPE.md)
- [Tendencias do Setor](INDUSTRY_TRENDS.md)

### Layer 4: Contexto Operacional de Negocio
- [Processo de Vendas](SALES_PROCESS.md)
- [Framework de Mensagens](MESSAGING_FRAMEWORK.md)
- [Diretrizes de Comunicacao](CUSTOMER_COMMUNICATION.md)

## Dados da Base DEPRE

### Estrutura dos Dados
| Coluna | Descricao | Preenchimento |
|--------|-----------|---------------|
| Ordem Pagamento | Identificador sequencial | 100% |
| Nº Processo DEPRE | Numero do processo no DEPRE (formato: NNNNNNN-NN.NNNN.8.26.0500) | 100% |
| Natureza | Natureza do processo | 1.7% |
| ES/EP | Classificacao ES ou EP | 1.7% |
| Nº de Autos | Numero dos autos originais | 99.97% |
| Ordem Orcamentaria | Codigo orcamentario (formato: NNNN/AAAA) | 100% |
| Suspenso? | S ou N | 100% |
| Data Protocolo | Data de entrada | 100% |
| Nº Protocolo Geral | Numero de protocolo | 1.7% |
| Nº Autos Antigos | Numeracao anterior | 1.3% |
| Advogado(s) | Nome do advogado | 99.8% |
| Devedora | Entidade devedora | 100% |
| Natureza (Saldo) | A (Alimentar) ou O (Outras) | 62.1% |
| Saldo DEPRE (R$) | Saldo em centavos | 62.1% |

### Distribuicao por Devedora (Top 5)
| Devedora | Processos | % |
|----------|-----------|---|
| Fazenda do Estado de SP | 157.888 | 79.0% |
| SPPREV | 22.296 | 11.2% |
| CBPM | 7.105 | 3.6% |
| IPESP | 4.953 | 2.5% |
| DER | 4.129 | 2.1% |

### Estatisticas de Saldo
| Metrica | Valor |
|---------|-------|
| Registros com saldo | 124.071 |
| Registros sem saldo | 75.696 |
| Saldo total | R$ 2.137.378.299,00 |
| Saldo medio | R$ 17.227,06 |
| Saldo mediano | R$ 800,14 |
| Maior saldo | R$ 55.773.906,82 |
| Processos suspensos | 2.095 (1.05%) |
| Natureza Alimentar | 117.680 (94.8% dos com saldo) |
| Natureza Outras | 6.391 (5.2% dos com saldo) |
