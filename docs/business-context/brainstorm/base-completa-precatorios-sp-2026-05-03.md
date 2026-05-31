# Brainstorm: Base Completa de Precatorios do Estado de SP

**Data:** 2026-05-03
**Participantes:** Jose Oliveira + Claude
**Linear:** Relacionado a FOR-13 (Pipeline DEPRE)

## Contexto

**Problema:** O portal atual cobre apenas ~200K precatorios da Fazenda do Estado de SP e autarquias estaduais. Existem 500K+ processos distribuidos entre todas as cidades e autarquias do estado que nao estao cobertos.

**Gatilho:** Oportunidade de first-mover — ninguem tem uma base completa de todos os precatorios de SP. Quem tiver primeiro ganha SEO, confianca e fluxo de leads.

**Modelo de negocio expandido:** A empresa compra precatorios de municipios tambem, principalmente RPVs (Requisicoes de Pequeno Valor), que sao menores mas com pagamento mais rapido.

**Fontes de dados (TJSP):**
1. `https://www.tjsp.jus.br/cac/scp/webRelPublicLstPagPrecatPendentes.aspx` — Lista de processos com numero DEPRE (dados do processo)
2. `https://www.tjsp.jus.br/cac/scp/webrelconsultapublicacoesweb.aspx` — ZIP com PDF contendo saldo do precatorio (numero DEPRE + saldo)

**Restricoes conhecidas:**
- CAPTCHA simples nos endpoints (resolvivel com 2captcha)
- PDFs de todas as entidades seguem o mesmo formato DEPRE
- Scripts Python de extracao (`extract_depre.py`, `match_depre_csv.py`) ja existem e funcionam
- PDFs podem ser descartados apos ingestao (sem custo de storage permanente)

## Alternativas Exploradas

### Alternativa A: Crawler Incremental (VPS dedicada)

- **Descricao:** VPS dedicada com Node.js + Playwright navegando ambos endpoints, resolvendo CAPTCHA, baixando PDFs, extraindo com Python, e fazendo UPSERT no Supabase. Job agendado via cron.
- **Vantagens:**
  - Reutiliza scripts Python existentes
  - Controle total sobre rate limiting e retry
  - Custo baixo (~$6-12/mes VPS)
  - Incremental: processa por entidade, pode parar e retomar
- **Desvantagens:**
  - CAPTCHA precisa de servico externo ($3/1000 resolucoes)
  - Risco de bloqueio por IP
  - Primeira carga pode levar dias
  - Manutencao se TJSP mudar layout
- **Esforco:** Medio (2-3 semanas)
- **Impacto:** Alto
- **Riscos:** Bloqueio TJSP, mudanca de layout, CAPTCHA mais complexo

### Alternativa B: Pipeline Distribuido (multiplas VPS + fila)

- **Descricao:** Arquitetura com fila (Redis/BullMQ), orquestrador + workers em VPS diferentes. Paralelismo de downloads.
- **Vantagens:**
  - Ingestao inicial em horas
  - Resiliencia e escalabilidade
  - IPs distribuidos
- **Desvantagens:**
  - Complexidade de infra muito maior
  - Custo mais alto
  - Overengineering para 500K registros
- **Esforco:** Alto (4-6 semanas)
- **Impacto:** Alto
- **Riscos:** Complexidade desnecessaria, custo operacional

### Alternativa C: Crawler Batch + Processamento Separado

- **Descricao:** Script Python unico que navega endpoints sequencialmente, baixa PDFs para disco, depois processa em batch. Download separado do processamento. Checkpointing para retomada.
- **Vantagens:**
  - Mais simples de construir e debugar
  - Retoma de onde parou se falhar
  - Scripts de processamento ja existem
  - Pode rodar localmente para primeira carga
- **Desvantagens:**
  - Sequencial (mais lento)
  - Storage temporario para PDFs (~10-50GB)
  - Nao e tempo real
- **Esforco:** Baixo (1-2 semanas)
- **Impacto:** Alto
- **Riscos:** Lentidao, storage temporario

## Analise de Trade-offs

| Criterio | A: Incremental | B: Distribuido | C: Batch |
|----------|:-:|:-:|:-:|
| Velocidade de entrega | Medio | Lento | Rapido |
| Custo de infra | Baixo | Alto | Minimo |
| Complexidade | Media | Alta | Baixa |
| Resiliencia | Media | Alta | Media |
| Velocidade 1a carga | Lenta (dias) | Rapida (horas) | Media (1-2 dias) |
| Manutencao | Media | Alta | Baixa |
| Risco de bloqueio | Medio | Baixo | Medio |
| Alinhamento MVP | Alto | Baixo | Alto |

## Decisao/Recomendacao

**Recomendacao:** Abordagem hibrida — **Alternativa C (Batch) para primeira carga + Alternativa A (Incremental) para recorrencia mensal.**

**Justificativa:**
1. **MVP lanca com ~200K do Estado** (dados ja existentes) — sem bloqueio
2. **Primeira carga completa via batch** (1 semana): script Python com Playwright, checkpointing, CAPTCHA via 2captcha. Roda em VPS ou localmente.
3. **Recorrencia mensal via crawler incremental** na VPS: so busca atualizacoes (deltas), nao refaz tudo.
4. 500K registros nao justifica pipeline distribuido — batch simples resolve.
5. First-mover depende de velocidade de entrega, nao de elegancia.

**Premissas-chave:**
1. PDFs de todas as entidades seguem o mesmo formato (confirmado)
2. CAPTCHA e simples e resolvivel com 2captcha
3. TJSP nao bloqueia crawlers com delay razoavel (2-3s entre requests)
4. Scripts Python existentes parseiam corretamente todos os formatos

**Proximos Passos:**
- [ ] Criar issue no Linear para o crawler/RPA (Fase 2)
- [ ] Fazer download manual de 3-5 PDFs de municipios diferentes para validar que o parser funciona
- [ ] Estimar custo de 2captcha para 500K+ resolucoes
- [ ] Definir infraestrutura (VPS Hetzner/DO)
- [ ] Mapear todas as entidades devedoras disponiveis nos endpoints

## Aprendizados

1. **Base completa = moat competitivo real** — nenhum concorrente tem isso. SEO + confianca + leads de municipios/RPVs.
2. **RPVs de municipios sao mercado pouco explorado** — menor valor individual mas pagamento mais rapido e menor competicao.
3. **Simplicidade vence** — para 500K registros, batch com checkpointing e mais eficiente que arquitetura distribuida.
4. **Separar download de processamento** e chave — permite debugar cada etapa independentemente e retomar de onde parou.
