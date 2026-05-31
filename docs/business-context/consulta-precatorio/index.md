# Business Context — Portal de Consulta de Precatórios SP

## Perfil do Projeto

| Campo | Valor |
|-------|-------|
| **Produto** | Portal Web de Consulta Gratuita de Precatórios e RPVs |
| **Organização** | PX Ativos Judiciais |
| **Workspace Linear** | Forjuris |
| **Team Linear** | FOR |
| **Project Linear** | Busca precatorio SP |
| **Repositório** | git@github.com:jjuniorfilho/precatorio-sp.git |
| **Modelo de Negócio** | Lead Generation → Compra de Precatórios/RPVs (cessão de crédito) |
| **Mercado** | Precatórios e RPVs do Estado de São Paulo — estado + municípios + autarquias |
| **Público-Alvo** | Servidores públicos, titulares de precatórios, herdeiros, advogados |
| **Canal Principal** | Busca orgânica (Google SEO) |
| **Base de Dados** | MVP: 199.767 processos DEPRE · Expansão: 500K+ (todas as cidades SP) |
| **Stack Técnica** | Lovable + Supabase (MVP) → VPS (escala) |
| **Meta Inicial** | 100 leads qualificados/mês |

## Proposta de Valor

Oferecer **consulta gratuita e imediata do saldo de precatórios** como isca de valor para capturar leads qualificados com saldo positivo confirmado. Diferente dos concorrentes que apenas capturam dados sem entregar nada em troca, este portal entrega valor real antes de solicitar informações de contato. **Nenhum concorrente cobre precatórios municipais** — first-mover advantage.

---

## Fases do Produto

### Fase 1 — MVP
- Busca por Nº Processo DEPRE ou Nº de Autos
- Consulta em base de ~200K registros (estadual)
- Exibição de resumo com saldo DEPRE (sem atualização monetária)
- Captura de lead com validação sequencial por token (e-mail → telefone)
- CRM simplificado com 8 status no painel admin
- Estrutura robusta de SEO em todo o site

### Fase 2 — Expansão
- Base completa: 500K+ processos (estado + 645 municípios + autarquias)
- Busca por CPF via VPS + Playwright no TJSP
- Crawler/RPA automatizado para captura de PDFs
- Pipeline DEPRE: extração mensal automatizada
- Blog com conteúdo gerado por IA para tráfego orgânico
- Páginas SEO por município/devedora

### Fase 3 — Jornada Completa
- Proposta digital de compra
- Aceite e assinatura digital
- Gestão documental
- Acompanhamento do pagamento

---

## Issues no Linear (FOR-5 a FOR-13)

### MVP — Fase 1
| Issue | Título | Prioridade | Status |
|-------|--------|------------|--------|
| [FOR-10](issues/001-persistencia-dados-supabase.md) | Modelagem e Persistência Supabase | P0 Urgent | Backlog |
| [FOR-5](features/consulta-precatorios.md) | Consulta de Precatórios | P0 Urgent | Backlog |
| [FOR-6](features/lead-capture.md) | Captura de Lead | P0 Urgent | Backlog |
| [FOR-7](features/token-validation.md) | Validação por Token | P0 Urgent | Backlog |
| [FOR-8](features/seo-performance.md) | SEO e Performance | P0 Urgent | Backlog |
| [FOR-11](issues/002-dashboard-administrativo.md) | Painel Admin + CRM | P1 High | Backlog |

### Fase 2 — Expansão
| Issue | Título | Prioridade | Status |
|-------|--------|------------|--------|
| [FOR-13](issues/004-pipeline-extracao-depre.md) | Pipeline Extração DEPRE | P1 High | Backlog |
| [FOR-12](issues/003-crawler-tjsp-cpf-vps.md) | Crawler TJSP por CPF | P1 High | Backlog |
| [FOR-9](features/blog-ia.md) | Blog com IA | P1 High | Backlog |

---

## Arquitetura de Contexto de Negócio

### Layer 1: Contexto do Cliente
- [Personas de Clientes](CUSTOMER_PERSONAS.md) — Dona Maria (titular), Carlos (herdeiro), Dr. Fernandes (advogado)
- [Jornada do Cliente](CUSTOMER_JOURNEY.md) — Descoberta → Consulta → Cadastro → Validação → Relacionamento
- [Voz do Cliente](VOICE_OF_CUSTOMER.md) — Feedback, dores, linguagem

### Layer 2: Contexto do Produto
- [Estratégia de Produto](PRODUCT_STRATEGY.md) — Visão, princípios, trade-offs, fases
- Catálogo de Features:
  - [Consulta de Precatórios](features/consulta-precatorios.md) — Busca instantânea na base DEPRE
  - [Captura de Lead](features/lead-capture.md) — Formulário + validação dupla
  - [Validação por Token](features/token-validation.md) — Token 6 dígitos sequencial (email → telefone)
  - [SEO e Performance](features/seo-performance.md) — URLs, schema markup, Core Web Vitals
  - [Blog com IA](features/blog-ia.md) — Conteúdo gerado por IA para tráfego orgânico
- [Métricas de Produto](PRODUCT_METRICS.md) — KPIs por camada do funil

### Layer 3: Contexto de Mercado e Competição
- [Panorama Competitivo](COMPETITIVE_LANDSCAPE.md) — Análise de concorrentes
- [Tendências do Setor](INDUSTRY_TRENDS.md) — Evolução do mercado de precatórios

### Layer 4: Contexto Operacional de Negócio
- [Processo de Vendas](SALES_PROCESS.md) — Funil comercial, scripts, automações
- [Framework de Mensagens](MESSAGING_FRAMEWORK.md) — Tom de voz, posicionamento
- [Diretrizes de Comunicação](CUSTOMER_COMMUNICATION.md) — LGPD, canais, escalação

---

## Issues e PRDs

| Issue | Título | Fase | PRD |
|-------|--------|------|-----|
| [001](issues/001-persistencia-dados-supabase.md) | Modelagem Supabase | MVP | Completo (user stories, critérios, riscos) |
| [002](issues/002-dashboard-administrativo.md) | Painel Admin + CRM | MVP | Completo (CRM 8 status, funil dual-view) |
| [003](issues/003-crawler-tjsp-cpf-vps.md) | Crawler TJSP por CPF | Fase 2 | Inicial |
| [004](issues/004-pipeline-extracao-depre.md) | Pipeline DEPRE | Fase 2 | Inicial |

---

## Brainstorms

- [Base Completa SP — 2026-05-03](../brainstorm/base-completa-precatorios-sp-2026-05-03.md) — Expansão para 500K+ processos, crawler batch + incremental, RPVs municipais

---

## Dados da Base DEPRE (atual)

| Métrica | Valor |
|---------|-------|
| Total de registros | 199.767 |
| Registros com saldo | 124.071 |
| Saldo total | R$ 2.137.378.299,00 |
| Saldo médio | R$ 17.227,06 |
| Processos suspensos | 2.095 (1,05%) |
| Natureza Alimentar | 94,8% dos com saldo |
| Top devedora | Fazenda do Estado de SP (79%) |

### Estrutura dos Dados
| Coluna | Descrição | Preenchimento |
|--------|-----------|---------------|
| Ordem Pagamento | Identificador sequencial | 100% |
| Nº Processo DEPRE | Número do processo no DEPRE | 100% |
| Natureza | Natureza do processo | 1,7% |
| ES/EP | Classificação ES ou EP | 1,7% |
| Nº de Autos | Número dos autos originais | 99,97% |
| Ordem Orçamentária | Código orçamentário | 100% |
| Suspenso? | S ou N | 100% |
| Data Protocolo | Data de entrada | 100% |
| Nº Protocolo Geral | Número de protocolo | 1,7% |
| Nº Autos Antigos | Numeração anterior | 1,3% |
| Advogado(s) | Nome do advogado | 99,8% |
| Devedora | Entidade devedora | 100% |
| Natureza (Saldo) | A (Alimentar) ou O (Outras) | 62,1% |
| Saldo DEPRE (R$) | Saldo em centavos | 62,1% |

---

## Artefatos

| Artefato | Localização |
|----------|-------------|
| PRD Visual (HTML) | [reports/prd-precatorio-sp.html](../../reports/prd-precatorio-sp.html) |
| Scripts de extração | [bin/extract_depre.py](../../bin/extract_depre.py), [bin/match_depre_csv.py](../../bin/match_depre_csv.py), [bin/collect_homologacoes.py](../../bin/collect_homologacoes.py) |
| Base Excel | precatorios_depre_completo.xlsx (16MB, não versionado) |
