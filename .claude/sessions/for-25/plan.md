# FOR-25 — Busca de Precatório por CPF/CNPJ via TJSP

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

---

## FASE 1 — Edge Function `search-by-document` [Completada ✅]

Backend completo antes de tocar no frontend.

### 1.1 Criar estrutura da edge function [Completada ✅]

Criar `supabase/functions/search-by-document/index.ts` com:
- CORS headers (padrão de `send-token` e `verify-token`)
- Deno.serve + validação do body `{ documento: string }`
- Normalização: `digits = documento.replace(/\D/g, "")`
- Validação: CPF = 11 dígitos, CNPJ = 14 dígitos → 400 se inválido
- Supabase client com `SUPABASE_SERVICE_ROLE_KEY` (necessário para ler/escrever `cpf_titular`/`cnpj_titular`)

Função `json()` utilitária (copiar de `verify-token/index.ts`).

### 1.2 Implementar DB-first (fast path) [Completada ✅]

```typescript
const col = digits.length === 11 ? "cpf_titular" : "cnpj_titular"
const { data } = await supabase
  .from("precatorios")
  .select("id, processo_depre")          // só para cross-ref
  .eq(col, digits)

if (data && data.length > 0) {
  // buscar dados públicos (sem CPF/CNPJ) via precatorios_publico
  const processos = data.map(r => r.processo_depre)
  const { data: publicRows } = await supabase
    .from("precatorios_publico")
    .select("*")
    .in("processo_depre", processos)
  return json({ data: publicRows, source: "db" })
}
```

### 1.3 Implementar TJSP scraping [Completada ✅]

**Passo crítico antes de codar**: fazer uma request manual ao TJSP para confirmar os parâmetros corretos. Comparar com `claude_legacy/busca_cessao.py` linhas 60–80.

Parâmetros prováveis (a confirmar):
```
GET https://esaj.tjsp.jus.br/cpopg/abrirConsultaDeRequisitorios.do
  ?cbPesquisa=DOCPARTE
  &dadosConsulta.valorConsulta=<CPF_OU_CNPJ>
  &consultaDeRequisitorios=true
Headers:
  User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64)...
  Referer: https://esaj.tjsp.jus.br/cpopg/abrirConsultaDeRequisitorios.do
```

Implementar com `AbortSignal.timeout(15_000)` para controlar timeout.

```typescript
async function fetchTjsp(documento: string): Promise<string | null> {
  try {
    const url = new URL("https://esaj.tjsp.jus.br/cpopg/abrirConsultaDeRequisitorios.do")
    url.searchParams.set("cbPesquisa", "DOCPARTE")
    url.searchParams.set("dadosConsulta.valorConsulta", documento)
    url.searchParams.set("consultaDeRequisitorios", "true")
    const res = await fetch(url, {
      headers: { "User-Agent": "Mozilla/5.0...", "Referer": url.origin + url.pathname },
      signal: AbortSignal.timeout(15_000),
    })
    if (!res.ok) return null
    return res.text()
  } catch {
    return null   // timeout ou rede → null → flag tjsp_unavailable
  }
}
```

### 1.4 Implementar parse HTML + cross-reference + enriquecimento [Completada ✅]

```typescript
// Extrai DEPREs do HTML
const REGEX_DEPRE = /\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.0500/g
function extractDepres(html: string): string[] {
  return [...new Set([...html.matchAll(REGEX_DEPRE)].map(m => m[0]))]
}

// Extrai nome do beneficiário (heurística — validar com HTML real do TJSP)
function extractNome(html: string): string | null {
  const m = html.match(/(?:Exequente|Requerente|Parte Ativa)[^:]*:\s*<[^>]*>([^<]+)</)
  return m ? m[1].trim() : null
}
```

Cross-reference:
```typescript
const depres = extractDepres(html)
if (depres.length === 0) return json({ flag: "not_found" })

const { data: matches } = await supabase
  .from("precatorios").select("id, processo_depre").in("processo_depre", depres)
if (!matches || matches.length === 0) return json({ flag: "not_found" })
```

Enriquecimento (UPDATE):
```typescript
const col = digits.length === 11 ? "cpf_titular" : "cnpj_titular"
const nome = extractNome(html)
const updatePayload: Record<string, string | null> = { [col]: digits }
if (nome) updatePayload.autor = nome

await supabase.from("precatorios").update(updatePayload)
  .in("processo_depre", matches.map(r => r.processo_depre))
```

Retorno via view pública:
```typescript
const { data: publicRows } = await supabase
  .from("precatorios_publico").select("*")
  .in("processo_depre", matches.map(r => r.processo_depre))

return json({ data: publicRows, source: "tjsp" })
```

### 1.5 Registrar `funnel_events` [Completada ✅]

```typescript
await supabase.from("funnel_events").insert({
  session_id: crypto.randomUUID(),
  event_type: "busca_realizada",
  context: { tipo: digits.length === 11 ? "cpf" : "cnpj" }  // NÃO registrar o documento
})
```

Registrar após retornar resultado (não bloquear a resposta).

### Comentários da Fase 1:
- Params TJSP confirmados via curl: dois passos necessários — GET main page (CSRF + JSESSIONID) → GET search.do?cbPesquisa=DOCPARTE
- "Não encontrado" detectado via `id="mensagemRetorno"` com texto "Não existem informações disponíveis"
- Regex extractNome usa 4 padrões heurísticos; pode precisar de ajuste com HTML real
- CLI Supabase sem acesso ao projeto Lovable (403) — deploy via Lovable AI interface

---

## FASE 2 — Integração Frontend [Completada ✅]

### 2.1 Adicionar `fetchPrecatoriosByDoc()` em `src/lib/api/precatorios.ts` [Completada ✅]

Adicionar ao final do arquivo existente (não substituir o que existe):

```typescript
export interface DocSearchResult {
  data?: PrecatorioRow[]
  flag?: "not_found" | "tjsp_unavailable"
  source?: "db" | "tjsp"
}

export async function fetchPrecatoriosByDoc(documento: string): Promise<DocSearchResult> {
  const digits = documento.replace(/\D/g, "")
  const { data, error } = await supabase.functions.invoke("search-by-document", {
    body: { documento: digits },
  })
  if (error) return { flag: "tjsp_unavailable" }
  return data as DocSearchResult
}
```

### 2.2 Remover Mock #2 — `resultado.cpf.$cpf.tsx` [Completada ✅]

**Arquivo:** `frontend/src/routes/resultado.cpf.$cpf.tsx`

Mudanças:
- Remover imports: `findByCpf`, `mockPrecatorios`
- Adicionar imports: `useState`, `useEffect`, `fetchPrecatoriosByDoc`, `PrecatorioRow`
- Converter componente para async com loading/error state
- Adicionar inline `TjspUnavailableCard` (simples Alert)

```typescript
function ResultadoCpf() {
  const { cpf } = Route.useParams()
  const [loading, setLoading] = useState(true)
  const [results, setResults] = useState<PrecatorioRow[]>([])
  const [flag, setFlag] = useState<"not_found" | "tjsp_unavailable" | null>(null)

  useEffect(() => {
    fetchPrecatoriosByDoc(cpf).then(res => {
      setResults(res.data ?? [])
      setFlag(res.flag ?? null)
      setLoading(false)
    }).catch(() => {
      setFlag("tjsp_unavailable")
      setLoading(false)
    })
  }, [cpf])

  const formatted = cpf.length === 11
    ? `${cpf.slice(0,3)}.${cpf.slice(3,6)}.${cpf.slice(6,9)}-${cpf.slice(9)}`
    : cpf

  if (loading) return <LoadingCard />
  if (flag === "tjsp_unavailable") return <TjspUnavailableCard />
  return <GroupedResults kind="CPF" maskedId={maskCpfPartial(formatted)} results={results} />
}
```

Componentes inline necessários:
- `LoadingCard` — loader centralizado (reusar padrão de `resultado.$processo.tsx`)
- `TjspUnavailableCard` — Alert de erro específico ("Serviço TJSP indisponível no momento. Tente novamente em instantes.")

**Validação:**
- [ ] Testar com CPF válido com precatório → exibe lista
- [ ] Testar com CPF sem precatório → exibe "não encontrado" (via `results = []` no GroupedResults)
- [ ] Network tab → chamada real à edge function (não mock)

### 2.3 Remover Mock #3 — `resultado.cnpj.$cnpj.tsx` [Completada ✅]

**Arquivo:** `frontend/src/routes/resultado.cnpj.$cnpj.tsx`

Mesma lógica da 2.2 com `kind="CNPJ"` e `maskCnpjPartial`.

```typescript
function ResultadoCnpj() {
  const { cnpj } = Route.useParams()
  const [loading, setLoading] = useState(true)
  const [results, setResults] = useState<PrecatorioRow[]>([])
  const [flag, setFlag] = useState<"not_found" | "tjsp_unavailable" | null>(null)

  useEffect(() => {
    fetchPrecatoriosByDoc(cnpj).then(res => {
      setResults(res.data ?? [])
      setFlag(res.flag ?? null)
      setLoading(false)
    }).catch(() => {
      setFlag("tjsp_unavailable")
      setLoading(false)
    })
  }, [cnpj])

  const formatted = cnpj.length === 14
    ? `${cnpj.slice(0,2)}.${cnpj.slice(2,5)}.${cnpj.slice(5,8)}/${cnpj.slice(8,12)}-${cnpj.slice(12)}`
    : cnpj

  if (loading) return <LoadingCard />
  if (flag === "tjsp_unavailable") return <TjspUnavailableCard />
  return <GroupedResults kind="CNPJ" maskedId={maskCnpjPartial(formatted)} results={results} />
}
```

**Validação:**
- [ ] Testar com CNPJ válido → exibe lista
- [ ] Testar com CNPJ sem precatório → exibe "não encontrado"

### Comentários da Fase 2:
- `GroupedResults` não muda — já trata `results.length === 0` com mensagem "não encontrado"
- `LoadingCard` e `TjspUnavailableCard` podem ser componentes inline nos próprios arquivos (sem criar novo arquivo)
- Verificar que `maskCpfPartial` e `maskCnpjPartial` já existem em `src/lib/search.ts` (confirmado)

---

## FASE 3 — Deploy e Validação End-to-End [Em Progresso ⏰]

### 3.1 Deploy da edge function [Em Progresso ⏰]

```bash
supabase functions deploy search-by-document --project-ref nxkvfcrnocdxysqsuozj
```

> ⚠️ Verificar se Supabase CLI está configurado. Se a função for deployada via Lovable AI (como ocorreu com `send-token`), seguir o padrão do projeto em vez do CLI.

Verificar no dashboard Supabase: Functions → search-by-document → testar com payload:
```json
{ "documento": "12345678900" }
```

### 3.2 Validação manual end-to-end [Não Iniciada ⏳]

Cenários a testar no browser:

| Cenário | Input | Resultado esperado |
|---------|-------|-------------------|
| CPF com DEPRE no banco | CPF já enriquecido | Lista de precatórios (source: db) |
| CPF sem dados no banco | CPF de titular real | TJSP consultado → lista ou not_found |
| CPF/CNPJ inválido | "123" | Edge fn retorna 400 |
| TJSP fora | (simular timeout) | TjspUnavailableCard |
| CNPJ com múltiplos DEPREs | CNPJ de empresa grande | GroupedResults com vários cards |

### 3.3 Atualizar Linear e documentação [Não Iniciada ⏳]

- Mover FOR-25 para "Done" no Linear
- Registrar parâmetros TJSP confirmados em architecture.md (preencher a nota de implementação)
- Remover imports de `mockPrecatorios` que ficaram órfãos (se houver)

---

## Sequência de Execução

```
Fase 1.1 → 1.2 → 1.3* → 1.4 → 1.5   (sequential — cada passo depende do anterior)
                ↑
          *Testar params TJSP manualmente antes de codar 1.3

Fase 2.1 → 2.2 + 2.3                  (2.2 e 2.3 podem ser paralelos após 2.1)

Fase 3.1 → 3.2 → 3.3                  (sequential)

Fase 1 deve estar completa antes de iniciar Fase 2.
```
