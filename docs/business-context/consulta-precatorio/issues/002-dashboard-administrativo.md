# Painel Administrativo para Gestao de Leads e Analytics

**Tipo**: Feature
**Prioridade**: P1 - Alta
**Fase**: MVP (Fase 1)
**Status**: Backlog
**Linear**: FOR-11

---

## POR QUE

- A equipe comercial precisa visualizar e gerenciar leads qualificados em tempo real para converter consultas em cessoes de credito
- Sem um CRM minimo, leads se perdem ou sao contatados fora do timing ideal (meta: < 2h para primeiro contato)
- O funil de conversao precisa ser visivel para identificar gargalos e otimizar a jornada
- Leads incompletos representam oportunidades perdidas — visibilidade sobre eles permite acao (ex: remarketing futuro)
- Notificacao de novos leads garante que nenhum lead qualificado fique sem atencao

## O QUE

### 1. Autenticacao Admin

- Login protegido via Supabase Auth (email + senha)
- 1 usuario admin (sem niveis de permissao no MVP)
- Sessao persistente (nao exigir login a cada visita)

### 2. CRM Simplificado — 8 Status

Pipeline do lead:

```
Novo → Contatado → Qualificado → Interessado → Proposta → Negociacao → Fechado → Descartado
```

| Status | Descricao | Cor sugerida |
|--------|-----------|--------------|
| Novo | Lead acabou de validar ambos os canais | Azul |
| Contatado | Primeiro contato realizado | Cyan |
| Qualificado | Lead confirmou interesse em saber mais | Amarelo |
| Interessado | Lead demonstrou intencao de venda | Laranja |
| Proposta | Proposta de cessao enviada | Roxo |
| Negociacao | Em negociacao de termos | Rosa |
| Fechado | Cessao de credito realizada | Verde |
| Descartado | Lead sem interesse ou invalido | Cinza |

**Acoes do admin sobre o lead:**
- Alterar status (dropdown ou drag-and-drop em kanban)
- Editar dados do lead (nome, telefone, email, relacao)
- Adicionar nota/comentario livre
- Ver timeline completa de eventos do funil

### 3. Listagem de Leads (completos)

**Tabela com colunas:**
- Nome, Email, Telefone, Relacao, Processo DEPRE, Saldo, Devedora, Status CRM, Data

**Filtros:**
| Filtro | Tipo | Opcoes |
|--------|------|--------|
| Periodo | Date range | Hoje, 7 dias, 30 dias, custom |
| Status CRM | Multi-select | 8 status |
| Faixa de saldo | Range | < R$1k, R$1k-10k, R$10k-100k, > R$100k |
| Devedora | Select | Fazenda SP, SPPREV, CBPM, IPESP, DER, Outros |
| Relacao | Select | Titular, Herdeiro, Advogado |

**Ordenacao:** Data (desc default), Saldo, Nome

**Busca:** Nome, email, telefone, numero do processo

**Detalhe do lead (modal ou pagina):**
- Todos os dados do lead
- Timeline de eventos do funil com timestamps (buscou → viu resultado → iniciou cadastro → validou email → validou telefone → lead completo)
- Historico de mudancas de status
- Campo de notas/comentarios

### 4. Leads Incompletos

Listagem de sessoes que buscaram mas nao completaram o cadastro.

| Coluna | Fonte |
|--------|-------|
| Processo buscado | funnel_events (context.process_id) |
| Saldo encontrado | funnel_events (context) / precatorios |
| Data/hora | funnel_events (created_at) |
| Dispositivo | funnel_events (user_agent) |
| Etapa de abandono | Ultimo evento da sessao |

**Identificacao:** Por `session_id` do funnel tracking (sem dados pessoais).

### 5. Funil de Conversao (dual view)

**Visao Funil (grafico):**
- Grafico de funil visual com barras decrescentes
- Etapas: Visitantes → Buscas → Resultados encontrados → Cadastros iniciados → Tokens validados → Leads completos
- Taxa de conversao entre cada etapa (%)
- Numeros absolutos em cada barra

**Visao Listagem (tabela):**
- Mesmos dados em formato tabular
- Colunas: Etapa, Total, % do anterior, % do topo

**Controles:**
- Toggle entre visao funil e visao listagem
- Filtro por periodo: Hoje, 7 dias, 30 dias, custom

### 6. Exportacao

- Botao "Exportar CSV" na listagem de leads
- Exporta conforme filtros aplicados no momento (leads completos e/ou incompletos, dependendo da view ativa)
- Inclui todas as colunas visiveis + status CRM

### 7. Notificacoes (tempo real)

- Badge no header do painel com contagem de leads novos desde ultimo acesso
- Atualiza em tempo real via Supabase Realtime (subscribe na tabela `leads`)
- Clicar no badge leva para listagem filtrada por status "Novo"
- Badge zera ao visualizar a listagem

## USER STORIES

**US1 — Login admin**
Como admin, preciso acessar o painel com email/senha para gerenciar leads de forma segura.

**US2 — Listar e filtrar leads**
Como admin, preciso visualizar todos os leads em tabela com filtros (periodo, status, saldo, devedora, relacao) para encontrar rapidamente leads por criterio.

**US3 — Gerenciar status CRM**
Como admin, preciso alterar o status do lead (Novo → Contatado → ... → Fechado/Descartado) para acompanhar o progresso comercial de cada lead.

**US4 — Detalhe do lead com timeline**
Como admin, preciso ver o detalhe completo do lead incluindo timeline de eventos do funil e historico de status para entender o contexto antes de fazer contato.

**US5 — Visualizar leads incompletos**
Como admin, preciso ver sessoes que buscaram mas nao completaram cadastro para entender o volume de oportunidades perdidas.

**US6 — Visualizar funil de conversao**
Como admin, preciso ver o funil em formato grafico ou tabela com filtro por periodo para identificar gargalos de conversao.

**US7 — Exportar dados**
Como admin, preciso exportar leads em CSV conforme filtros aplicados para usar em ferramentas externas.

**US8 — Receber notificacao de novos leads**
Como admin, preciso ser notificado em tempo real quando um novo lead chega para agir dentro de 2 horas.

---

## CRITERIOS DE ACEITE

### Autenticacao
- [ ] Login com email/senha funcional via Supabase Auth
- [ ] Sessao persistente (nao pede login a cada visita)
- [ ] Rota `/admin` inacessivel sem autenticacao (redirect para login)
- [ ] Acesso anon a qualquer endpoint admin retorna 401

### CRM e gestao de leads
- [ ] 8 status disponiveis para classificar leads
- [ ] Admin pode alterar status de qualquer lead
- [ ] Mudanca de status gera registro em `lead_status_history`
- [ ] Admin pode editar nome, telefone, email, relacao do lead
- [ ] Admin pode adicionar notas/comentarios livres
- [ ] Detalhe do lead exibe timeline de eventos do funil com timestamps
- [ ] Detalhe do lead exibe historico de mudancas de status

### Listagem e filtros
- [ ] Tabela exibe: Nome, Email, Telefone, Relacao, Processo, Saldo (R$), Devedora, Status CRM, Data
- [ ] Filtro por periodo (hoje, 7d, 30d, custom) funcional
- [ ] Filtro por status CRM (multi-select) funcional
- [ ] Filtro por faixa de saldo funcional
- [ ] Filtro por devedora funcional
- [ ] Filtro por relacao funcional
- [ ] Busca por nome, email, telefone, processo funcional
- [ ] Ordenacao por data, saldo, nome funcional

### Leads incompletos
- [ ] Listagem exibe: processo buscado, saldo, data/hora, dispositivo, etapa de abandono
- [ ] Dados agrupados por session_id
- [ ] Nenhum dado pessoal exposto (apenas dados de sessao)

### Funil de conversao
- [ ] Visao grafico de funil com barras e taxas de conversao entre etapas
- [ ] Visao tabela com colunas: Etapa, Total, % anterior, % topo
- [ ] Toggle entre visao funil e visao listagem funcional
- [ ] Filtro por periodo funcional

### Exportacao
- [ ] Botao "Exportar CSV" gera arquivo com dados filtrados
- [ ] CSV inclui todas as colunas visiveis + status CRM
- [ ] Funciona tanto para leads completos quanto incompletos

### Notificacao
- [ ] Badge no header exibe contagem de leads novos desde ultimo acesso
- [ ] Badge atualiza em tempo real (Supabase Realtime)
- [ ] Clicar no badge filtra listagem por status "Novo"
- [ ] Badge zera ao visualizar a listagem

---

## RISCOS E MITIGACOES

| Risco | Probabilidade | Impacto | Mitigacao |
|-------|--------------|---------|-----------|
| Supabase Realtime instavel com muitas conexoes | Baixa | Medio | Fallback: polling a cada 30s se Realtime falhar |
| Lovable nao suporta bem rotas protegidas (/admin) | Baixa | Alto | Verificar capacidade do Lovable para auth routing antes de iniciar |
| Query de funnel_events lenta com volume alto | Media | Medio | Indices ja definidos na issue 001; considerar views materializadas se necessario |
| Admin esquece de mudar status do lead | Media | Medio | Badge + ordenacao por "Novo" primeiro como lembrete visual |

---

## DEPENDENCIAS

| Dependencia | Tipo | Status | Impacto |
|-------------|------|--------|---------|
| FOR-10: Modelagem Supabase (tabelas leads, tokens, funnel_events) | Feature | Backlog | Bloqueante — sem tabelas nao ha dados |
| FOR-6: Captura de Lead (dados fluindo para tabela leads) | Feature | Backlog | Bloqueante para dados reais; pode testar com seed data |
| FOR-7: Validacao por Token (funnel events gerados) | Feature | Backlog | Bloqueante para timeline de eventos |
| Supabase Auth configurado com usuario admin | Infra | Pendente | Bloqueante para login |

---

## CRITERIOS DE LANCAMENTO

Esta issue e considerada **done** quando:

1. **Login funcional**: Admin acessa `/admin` com credenciais, sessao persiste
2. **Listagem completa**: Leads exibidos em tabela com todos os filtros operacionais
3. **CRM operacional**: Status alteravel, historico registrado, notas adicionaveis
4. **Timeline visivel**: Detalhe do lead mostra eventos do funil e historico de status
5. **Leads incompletos**: Listagem por sessao com dados de abandono
6. **Funil dual view**: Grafico e tabela alternando, filtro por periodo
7. **Exportacao**: CSV gerado com filtros aplicados
8. **Notificacao**: Badge em tempo real para novos leads
9. **Seguranca**: Rota `/admin` inacessivel sem auth, RLS verificado

---

## COMO

### Stack
- Frontend: Lovable (React) — mesma aplicacao do portal, rota `/admin`
- Auth: Supabase Auth (email + senha, 1 usuario pre-cadastrado)
- Dados: Supabase queries via service role (RLS protege de acesso anon)
- Realtime: Supabase Realtime para badge de notificacao

### Banco de dados — alteracoes necessarias

**Nova coluna na tabela `leads`:**
```sql
ALTER TABLE leads ADD COLUMN status_crm VARCHAR DEFAULT 'novo';
ALTER TABLE leads ADD COLUMN notas TEXT;
ALTER TABLE leads ADD COLUMN status_changed_at TIMESTAMPTZ;
```

**Nova tabela `lead_status_history` (timeline de mudancas):**
| Coluna | Tipo | Notas |
|--------|------|-------|
| id | UUID, PK | |
| lead_id | UUID, FK → leads | |
| status_anterior | VARCHAR | |
| status_novo | VARCHAR | |
| changed_at | TIMESTAMPTZ, default NOW | |
| changed_by | VARCHAR | Admin user |

**RLS para admin:**
```sql
-- Permitir SELECT/UPDATE para usuario autenticado com role admin
CREATE POLICY "admin_full_access_leads"
  ON leads FOR ALL
  TO authenticated
  USING (auth.jwt() ->> 'role' = 'admin');

CREATE POLICY "admin_full_access_lead_status_history"
  ON lead_status_history FOR ALL
  TO authenticated
  USING (auth.jwt() ->> 'role' = 'admin');
```

### Realtime (notificacao)
```javascript
// Subscribe para novos leads
supabase
  .channel('new-leads')
  .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'leads' }, 
    (payload) => { incrementBadge() })
  .subscribe()
```

### Fora de escopo
- Multi-usuario / niveis de permissao (futuro)
- Notificacao por email/WhatsApp (futuro)
- Automacao de follow-up (futuro)
- Dashboard de metricas SEO (futuro)
- Integracao com CRM externo (futuro)
