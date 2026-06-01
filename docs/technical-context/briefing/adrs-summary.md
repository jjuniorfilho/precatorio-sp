# ADRs — Consulta Precatório SP

> Nenhuma ADR formal encontrada em `/discover` de 2026-05-31.
> Decisões arquiteturais relevantes estão documentadas abaixo como referência.

---

## Decisões Tomadas (sem ADR formal)

| Decisão | Escolha | Motivo |
|---------|---------|--------|
| Frontend | Lovable + TanStack Router | Velocidade de geração e iteração |
| Backend | Supabase (BaaS) | Sem servidor próprio no MVP, RLS nativo, realtime |
| Database | PostgreSQL via Supabase | Já incluído no Supabase |
| Auth | Supabase Auth | Nativo, sem custo adicional |
| Busca | Índice PostgreSQL | Base de 200K é pequena para FTS completo |
| Valores | Centavos (BIGINT) | Evitar float em dinheiro |
| Tokens | 6 dígitos OTP, TTL 10min | Padrão da indústria |
| Crawlers | Python na VPS | Flexibilidade, sem restrição de tempo de execução |
| Stack CSS | Tailwind + shadcn/ui | Já gerado pelo Lovable |
| Tipografia | Sora (heading) + Inter (body) | Referência BTG Pactual |

---

💡 **Recomendação**: Ao tomar decisões arquiteturais importantes, criar ADRs em `docs/technical-context/adr/` seguindo o formato:

```markdown
# ADR-001: Título

**Status**: Aceito
**Data**: YYYY-MM-DD

## Contexto
...

## Decisão
...

## Consequências
...
```
