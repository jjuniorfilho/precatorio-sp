# Context: FOR-25 — Busca de Precatório por CPF/CNPJ via TJSP

## ⚠️ Regras Críticas do Projeto

### Segurança de dados
- NUNCA expor CPF completo — sempre mascarar (`123.***.***-00`)
- NUNCA expor dados de um lead para outro usuário
- SEMPRE usar RLS no Supabase
- Tabela `precatorios` é pública mas `cpf_titular`/`cnpj_titular` ficam FORA da view pública (`precatorios_publico`) por LGPD
- Tabelas `leads`, `tokens`, `funnel_events` são privadas (admin only)

### Busca tolerante a formato
- SEMPRE normalizar input antes de buscar: remover `.`, `-`, `/`, espaços
- Aceitar CPF com e sem máscara: `123.456.789-00` = `12345678900`
- Aceitar CNPJ com e sem máscara

### Valores monetários
- SEMPRE armazenar saldo em centavos (integer)
- SEMPRE exibir como `R$ X.XXX,XX` via `Intl.NumberFormat('pt-BR')`

### Checklist antes de qualquer endpoint
- [ ] Input normalizado antes de query?
- [ ] CPF/CNPJ mascarado nas respostas públicas?
- [ ] Evento registrado em `funnel_events`?

---

## Motivação (POR QUÊ)

A UI já exibe rotas `/resultado/cpf/:cpf` e `/resultado/cnpj/:cnpj` mas ambas usam `mockPrecatorios` com dados hardcoded. Titulares de precatório frequentemente só sabem seu CPF/CNPJ — não o número DEPRE. Habilitar essa busca real reduz fricção no funil e aumenta conversão de leads.

Problema estrutural: a tabela `precatorios` tem colunas `cpf_titular` e `cnpj_titular`, mas a maioria dos registros tem esses campos NULL (dados importados do PDF DEPRE nem sempre incluem o documento). A view pública `precatorios_publico` também não expõe esses campos por LGPD. Portanto, é necessário consultar o TJSP para enriquecer os dados.

---

## Meta (O QUÊ)

1. **Edge Function `search-by-document`**: recebe CPF ou CNPJ, implementa lógica DB-first + fallback TJSP
2. **Frontend**: substituir `mockPrecatorios` nos componentes CPF e CNPJ por chamada à nova edge function, com loading state
3. **Enriquecimento de dados**: quando TJSP retornar um DEPRE existente na nossa base, atualizar `cpf_titular`/`cnpj_titular` + `autor` (beneficia futuras buscas — fast path DB)

---

## Fluxo Completo

```
Usuário digita CPF/CNPJ
       ↓
Frontend → POST edge function search-by-document { documento: "12345678900" }
       ↓
[DB-FIRST] Busca precatorios WHERE cpf_titular = ? OR cnpj_titular = ?
       ↓ encontrou?
    SIM → retorna array de precatórios (dados da precatorios_publico view)
    NÃO ↓
[TJSP] GET abrirConsultaDeRequisitorios.do?cbPesquisa=DOCPARTE&...
       ↓ TJSP retornou DEPREs?
    NÃO → { flag: "not_found" }
    TJSP_DOWN → { flag: "tjsp_unavailable" }
    SIM ↓
[CROSS-REF] SELECT * FROM precatorios WHERE processo_depre IN (depres_encontrados)
       ↓ match no nosso banco?
    NÃO → { flag: "not_found" }
    SIM ↓
[UPDATE] UPDATE precatorios SET cpf_titular/cnpj_titular, autor WHERE processo_depre IN (...)
       ↓
Retorna array de precatórios encontrados
```

---

## Estratégia Técnica

- **Edge Function**: TypeScript/Deno (mesmo padrão de `send-token`/`verify-token`)
- **HTTP para TJSP**: `fetch()` nativo do Deno com headers de browser
- **Parse HTML**: regex direta para extrair DEPRE (`\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.0500`) e nome do beneficiário
- **DB access**: Supabase service_role (necessário para ler/escrever `cpf_titular`/`cnpj_titular`)
- **Resposta ao frontend**: array de `PrecatorioRow[]` (mesma interface existente) ou flags `not_found`/`tjsp_unavailable`
- **Timeout TJSP**: 15s máximo; se estourar → flag `tjsp_unavailable`

---

## Dependências

- Supabase projeto: `nxkvfcrnocdxysqsuozj.supabase.co`
- Tabela `precatorios` com colunas `cpf_titular`, `cnpj_titular`, `autor` (existem, sem migration necessária)
- View `precatorios_publico` para retornar dados seguros ao frontend
- TJSP endpoint: `https://esaj.tjsp.jus.br/cpopg/abrirConsultaDeRequisitorios.do`

---

## Limitações e Premissas

- TJSP pode estar fora ou retornar CAPTCHA → tratar como `tjsp_unavailable`
- CPF/CNPJ nunca são retornados ao frontend (ficam no service_role)
- A busca TJSP retorna apenas precatórios estaduais do TJSP (nossa base também é só estadual SP)
- `funnel_events` deve registrar `busca_realizada` com `{ tipo: "cpf" | "cnpj" }` (sem o número do documento)

---

## Validação

1. Busca CPF com dados já no banco → retorna instantâneo (DB-first)
2. Busca CPF sem dados no banco → vai ao TJSP → retorna e persiste
3. CPF sem precatório no TJSP → `not_found`
4. TJSP fora → `tjsp_unavailable`
5. CPF com múltiplos DEPREs → retorna array → `GroupedResults` lista todos
