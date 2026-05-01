# Issue 002: Painel administrativo para gestao de leads e analytics

**Tipo**: Feature
**Prioridade**: P1 - Alta
**Fase**: MVP (Fase 1)
**Status**: Backlog

---

## Descricao

Criar area administrativa no Lovable (protegida por login) para gestao de leads capturados e visualizacao de metricas do funil de conversao.

## Escopo

### Autenticacao Admin
- Login protegido por usuario/senha (Supabase Auth)
- Acesso restrito a equipe interna

### Listagem de Leads
- Tabela com todos os leads capturados
- Filtros por: data, faixa de saldo, devedora, status de validacao, relacao (titular/herdeiro/advogado)
- Ordenacao por: data, saldo, nome
- Busca por: nome, e-mail, telefone, processo
- Detalhes do lead: todos os dados + historico de consultas + eventos do funil

### Leads Incompletos
- Listagem de usuarios que buscaram mas nao completaram cadastro
- Inclui CPF quando informado (mesmo sem cadastro completo)
- Informacoes disponiveis: processo buscado, saldo encontrado, data/hora, dispositivo

### Funil de Conversao
- Visualizacao dos marcos: visitantes → buscas → resultados → cadastros iniciados → tokens validados → leads completos
- Filtros por periodo (dia, semana, mes)
- Taxas de conversao entre cada etapa

### Exportacao
- Exportar leads em CSV/Excel
- Filtros aplicados na exportacao

## Criterios de Aceite
- [ ] Login admin funcional com Supabase Auth
- [ ] Listagem de leads com filtros e busca
- [ ] Visualizacao de leads incompletos
- [ ] Dashboard com funil de conversao por periodo
- [ ] Exportacao CSV funcional com filtros
