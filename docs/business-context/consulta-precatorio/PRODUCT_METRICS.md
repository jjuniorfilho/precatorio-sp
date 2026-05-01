# Metricas de Produto

## Dashboard de KPIs

### Metricas Primarias (North Star)

| Metrica | Definicao | Meta Fase 1 | Meta Fase 2 |
|---------|-----------|-------------|-------------|
| **Leads qualificados/mes** | Leads com saldo positivo + contato validado | 100 | 500 |
| **Custo por lead (CPL)** | Custo total / leads capturados | < R$ 10 | < R$ 5 |
| **Taxa de conversao visitante→lead** | Leads / visitantes unicos | 2% | 2.5% |

---

## Metricas por Camada do Funil

### 1. Aquisicao (Topo do Funil)
| Metrica | Definicao | Meta Fase 1 | Meta Fase 2 |
|---------|-----------|-------------|-------------|
| Visitantes unicos/mes | Sessoes unicas | 5.000 | 20.000 |
| Trafego organico (%) | Visitas via Google / total | > 70% | > 80% |
| Posicao media Google | Media dos termos prioritarios | Top 10 | Top 5 |
| Impressoes Search Console | Vezes que apareceu nos resultados | 50.000 | 200.000 |
| CTR medio Google | Cliques / impressoes | > 5% | > 8% |
| Taxa de bounce | Saidas sem interacao / visitas | < 40% | < 35% |
| Paginas/sessao | Media de paginas vistas | > 2 | > 3 |

### 2. Engajamento (Meio do Funil)
| Metrica | Definicao | Meta |
|---------|-----------|------|
| Taxa de busca | Buscas realizadas / visitantes | > 50% |
| Taxa de resultado encontrado | Resultados positivos / buscas | > 60% |
| Tempo ate resultado | Tempo entre busca e exibicao | < 3 segundos |
| Taxa de resultado com saldo | Resultados com saldo > 0 / resultados | > 62% |

### 3. Conversao (Fundo do Funil)
| Metrica | Definicao | Meta |
|---------|-----------|------|
| Taxa resultado→formulario | Cliques em "Ver detalhes" / resultados | > 40% |
| Taxa preenchimento formulario | Formularios enviados / iniciados | > 80% |
| Taxa validacao token | Tokens validados / enviados | > 80% |
| Taxa abandono token | Desistencias no token / tokens enviados | < 20% |
| Canal de validacao preferido | Distribuicao por canal | Monitorar |

### 4. Qualidade do Lead
| Metrica | Definicao | Meta |
|---------|-----------|------|
| Saldo medio dos leads | Media de saldo DEPRE dos leads | Monitorar |
| % leads titulares vs herdeiros vs advogados | Distribuicao por tipo | Monitorar |
| % leads com token multi-canal | Leads com 2+ canais validados | > 50% |
| Taxa de e-mail bounce | E-mails invalidos pos-validacao | < 5% |
| Taxa de telefone invalido | Telefones que nao completam | < 10% |

### 5. Pos-Lead (Comercial)
| Metrica | Definicao | Meta |
|---------|-----------|------|
| Taxa de contato efetivo | Leads contatados / leads capturados | > 80% |
| Taxa de resposta | Leads que responderam / contatados | > 40% |
| Taxa lead→proposta | Propostas enviadas / leads | > 20% |
| Taxa proposta→cessao | Cessoes fechadas / propostas | > 15% |
| Ticket medio de cessao | Valor medio das cessoes | Monitorar |
| Ciclo de venda medio | Dias do lead ate cessao | Monitorar |

---

## Metricas Tecnicas

### Performance do Site
| Metrica | Meta | Ferramenta |
|---------|------|-----------|
| LCP | < 2.5s | Lighthouse |
| FID | < 100ms | Lighthouse |
| CLS | < 0.1 | Lighthouse |
| Uptime | > 99.5% | Monitoramento |
| Tempo de resposta API | < 500ms (p95) | Supabase |

### Base de Dados
| Metrica | Valor Atual | Monitoramento |
|---------|-------------|---------------|
| Total de registros | 199.767 | Estatico (Fase 1) |
| Registros com saldo | 124.071 | Estatico (Fase 1) |
| Tempo de query busca | < 200ms | Supabase |
| Storage utilizado | Monitorar | Supabase |

---

## Segmentacao de Analise

### Por Devedora
Acompanhar metricas segmentadas por devedora para identificar oportunidades:
- Fazenda do Estado (79% da base)
- SPPREV (11%)
- CBPM (3.6%)
- Outros

### Por Faixa de Saldo
| Faixa | Registros | Estrategia |
|-------|-----------|-----------|
| < R$ 1.000 | ~50% | Volume, menor desagio |
| R$ 1.000 - R$ 10.000 | ~30% | Sweet spot |
| R$ 10.000 - R$ 100.000 | ~15% | Alto valor, negociacao |
| > R$ 100.000 | ~5% | Premium, dedicado |

### Por Dispositivo
| Dispositivo | % Esperado | Otimizacao |
|-----------|-----------|-----------|
| Mobile | 70-80% | Prioridade maxima |
| Desktop | 15-25% | Funcional |
| Tablet | 5% | Responsivo |

---

## Cadencia de Revisao

| Frequencia | Metricas | Responsavel |
|-----------|---------|-------------|
| Diaria | Leads capturados, buscas realizadas | Automatico (dashboard) |
| Semanal | Funil completo, trafego, conversao | Equipe |
| Mensal | KPIs primarios, SEO, qualidade de leads | Gestao |
| Trimestral | Estrategia, ROI, roadmap | Diretoria |
