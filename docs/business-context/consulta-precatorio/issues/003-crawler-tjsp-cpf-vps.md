# Issue 003: Busca por CPF no TJSP via VPS + Playwright

**Tipo**: Feature
**Prioridade**: P1 - Alta
**Fase**: Fase 2
**Status**: Backlog

---

## Descricao

Quando o usuario informar o CPF no portal, o sistema realiza busca automatizada no site do TJSP (esaj.tjsp.jus.br), extrai os processos vinculados ao CPF e cruza os resultados com a base DEPRE no Supabase.

## Fluxo

1. Usuario informa CPF no campo de busca do portal
2. Portal (Supabase Edge Function) envia CPF para servico REST na VPS
3. VPS roda Playwright (Chromium headless) no esaj.tjsp.jus.br
4. Busca processos vinculados ao CPF no TJSP
5. Resultados retornados para o Supabase
6. Sistema cruza resultados do TJSP com a base DEPRE
7. Processos encontrados em ambas as bases sao exibidos ao usuario
8. CPF e armazenado no banco mesmo que usuario nao complete o cadastro (lead incompleto)

## Arquitetura Tecnica

| Componente | Tecnologia |
|-----------|-----------|
| Servico de busca | Node.js + Playwright + Chromium headless |
| Infraestrutura | VPS Hetzner/DigitalOcean (~$6/mes, 2GB RAM) |
| API | REST endpoint (POST /search-cpf) |
| Integracao | Supabase Edge Function → HTTP call → VPS |
| Anti-bloqueio | Delay 2-3s entre requests |
| CAPTCHA | 2captcha (~$3/1000 solves) se necessario |
| Referencia | Scrapers open source: courtsbr/tjsp, jjesusfilho/tjsp |

## Seguranca e Compliance
- CPF trafega criptografado (HTTPS)
- CPF armazenado criptografado no Supabase
- Dados judiciais do TJSP sao publicos (sem restricao legal)
- LGPD: base legal = interesse legitimo + consentimento do titular
- Rate limiting para evitar bloqueio pelo TJSP

## Criterios de Aceite
- [ ] Servico REST na VPS recebe CPF e retorna processos do TJSP
- [ ] Cruzamento automatico com base DEPRE
- [ ] Resultados exibidos ao usuario em < 15 segundos
- [ ] CPF armazenado mesmo sem cadastro completo
- [ ] Anti-bloqueio funcional (delay + retry)
- [ ] Logs de busca para monitoramento
