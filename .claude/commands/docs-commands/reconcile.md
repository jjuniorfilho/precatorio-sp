# Doc Reconcile — Sincronização Índice ↔ Fonte da Verdade

Você é responsável por executar a manutenção e reconciliação periódica entre um **documento ÍNDICE** (enxuto, auto-carregado em toda sessão) e seu **documento FONTE DA VERDADE** (detalhado, lido sob demanda). Com o tempo o índice acumula detalhe que nunca é propagado para a fonte, ou aponta para seções que não existem mais. Este comando detecta esse *drift*, porta o conteúdo órfão para a fonte, enxuga o índice de volta para ponteiros e valida todos os links.

**Princípio fundamental**: o comando **propõe**, o humano **aprova**. NUNCA aplicar mudanças destrutivas sem confirmação explícita. O documento original sempre permanece no histórico git como rede de segurança.

**Contrato dos dois documentos** (o invariante que este comando protege):

| Documento | Papel | Como é consumido |
|-----------|-------|------------------|
| **ÍNDICE** (ex.: `CLAUDE.md`) | Resumo de 1–2 linhas por tópico + ponteiro para a fonte | **Auto-carregado** em todo warm-up/sessão — DEVE ser enxuto |
| **FONTE DA VERDADE** (ex.: `CLAUDE.meta.md`) | Detalhe completo, exemplos, tabelas, gotchas | Lido **sob demanda e em pedaços** (grep heading → read offset/limit) |

> Este é o mesmo padrão da memória do Cortex (`MEMORY.md` curado ↔ `sessions/` brutas) e o par que o `/build-tech-docs` gera. Aqui ele é mantido em vez de só gerado.

> **IMPORTANTE**: caminhos `.claude/memory/` referem-se à pasta `memory/` dentro do `.claude/` do **projeto atual** (working directory), NUNCA a `~/.claude/memory/` do usuário.

---

## Configuração

Resolva o par de arquivos a reconciliar (nesta ordem de precedência):

1. **Argumentos** — `#$ARGUMENTS`. Formato aceito: `<índice> <fonte>` (dois caminhos). Ex.: `/docs-commands:reconcile CLAUDE.md specs/technical/CLAUDE.meta.md`.
2. **Auto-detecção** — se sem argumentos, procurar o par convencional:
   - ÍNDICE = `CLAUDE.md` na raiz do projeto.
   - FONTE = primeiro match de `CLAUDE.meta.md` (ex.: `specs/technical/CLAUDE.meta.md`, `docs/specs/technical/CLAUDE.meta.md`).
3. **Fallback** — se não achar o par, perguntar ao humano qual índice e qual fonte usar. Não inventar.

Parâmetros (defaults sensatos, mencione-os no relatório):
- `INDEX_BLOAT_THRESHOLD` = 25 linhas — seção do índice acima disso é candidata a enxugamento (deveria ser ponteiro).
- `SECTION_HEADING_LEVELS` = H2/H3 (`##`, `###`) — níveis tratados como "seções".

---

## Fase 1 — Pré-checagem

1. Confirmar que ÍNDICE e FONTE existem. Se a FONTE não existir, **parar** e sugerir `/build-tech-docs` (a fonte precisa existir antes de reconciliar).
2. Medir ambos (`wc -l`, `wc -c`). Registrar o baseline para o relatório final.
3. Confirmar que o repositório está limpo o suficiente OU avisar o humano que mudanças serão feitas nesses dois arquivos (o git history é a rede de segurança — não há perda permanente).

---

## Fase 2 — Detecção de Drift

Trabalhe com **dados, não impressões**. Gere as evidências por shell/script antes de classificar.

### 2.1 Mapa de seções e anchors

- Extraia os headings (`^#{1,3} `) de ambos os arquivos com número de linha.
- Compute o **anchor GitHub** de cada heading da FONTE (ver Apêndice A — o algoritmo tem armadilhas: hífen inicial em headings com emoji, hífen duplo em separadores `—`/`+`/`/`, acentos preservados, sem colapsar espaços).

### 2.2 Quatro categorias de drift

Para cada seção do ÍNDICE, classifique:

| Categoria | Como detectar | Ação na Fase 4/5 |
|-----------|---------------|------------------|
| **GAP** (só no índice) | Seção/feature do índice sem contraparte na fonte. Confirme com `grep` na fonte por tokens identificadores (IDs tipo `PX-####`/`#issue`, nome da seção, termos-chave). 0 hits = gap. | **Portar** o detalhe do índice → fonte. |
| **STALE** (fonte desatualizada) | Seção existe na fonte mas faltam tokens recentes que só estão no índice (ex.: `PX-1756` com 0 hits na fonte). | **Portar os deltas** → fonte. |
| **BLOAT** (índice gordo) | Corpo da seção do índice > `INDEX_BLOAT_THRESHOLD` linhas. | **Enxugar** para ponteiro. |
| **LINK QUEBRADO** | Ponteiro do índice (`fonte#anchor` ou `#anchor` interno) que não resolve. | **Corrigir** o anchor. |

### 2.3 Relatório de drift

Produza uma tabela: seção | categoria | evidência (linha/contagem de hits) | ação proposta. **Não aplique nada ainda.**

---

## Fase 3 — Apresentar Plano e Obter Aprovação

Apresente ao humano:

```
## Drift detectado: ÍNDICE ↔ FONTE

Índice: <path> (N linhas)  |  Fonte: <path> (M linhas)

- GAPs (só no índice, a portar):   <lista>
- STALE (deltas a portar):         <lista>
- BLOAT (a enxugar p/ ponteiro):   <lista>
- Links quebrados (a corrigir):    <lista>

Plano:
1. Portar GAPs+STALE para a fonte (slicing fiel, sem retranscrição).
2. Enxugar seções gordas do índice para resumo + ponteiro.
3. Corrigir anchors quebrados.
4. Validar 100% dos links.

Aprovar tudo (a) | Aprovar seletivamente (s) | Cancelar (c)
```

Aguardar decisão. Se "seletivamente", listar item a item.

---

## Fase 4 — Portar para a Fonte (GAPs + STALE)

**Use slicing fiel — nunca retranscreva texto à mão** (introduz erros). Técnica:

1. Identifique os ranges de linha das seções órfãs no ÍNDICE (heading até a linha antes do próximo heading).
2. Extraia por shell, ajustando o nível do heading (`###` → `##` se a fonte usa H2 para seções), e — para seções STALE — retitule para `## <Título> — Estado Atual (<faixa de IDs>)` para **evitar heading duplicado** na fonte.
3. Insira o bloco num ponto âncora estável da fonte (ex.: imediatamente antes de uma seção de cauda como `## External Integrations Reference` ou antes da última seção), via `head`/`tail` split (mais robusto que `awk getline` no BSD/macOS).
4. **Nunca** crie heading H2 com texto idêntico a um já existente (gera anchor duplicado). Verifique com `grep -E '^## ' fonte | sort | uniq -d` (deve sair vazio).

Esqueleto (adapte os ranges/anchor reais):

```bash
SRC=<ÍNDICE>; META=<FONTE>
slice()   { sed -n "${1},${2}p" "$SRC" | sed '1s/^### /## /'; }            # net-new: sobe nível
retitle() { sed -n "${1},${2}p" "$SRC" | sed "1s|^### .*|## $3|"; }          # stale: retitula
{ slice 361 434; retitle 830 1006 "Financial — Estado Atual (PX-942 → PX-1801)"; } > /tmp/insert.md

LN=$(grep -nE '^## <SEÇÃO ÂNCORA DE CAUDA>$' "$META" | head -1 | cut -d: -f1)
head -n $((LN-1)) "$META" > /tmp/m.new
cat /tmp/insert.md       >> /tmp/m.new
tail -n +"$LN" "$META"   >> /tmp/m.new
mv /tmp/m.new "$META"
grep -E '^## ' "$META" | sort | uniq -d   # deve sair vazio (sem heading duplicado)
```

---

## Fase 5 — Enxugar o Índice (BLOAT)

Para cada seção gorda, colapse o corpo para **resumo de 1–2 linhas + ponteiro para a fonte**, mantendo:

- **O texto exato do heading** (`### N. Título`) — os anchors são referenciados pela Decision Tree do índice e por back-links da fonte; mudar o texto quebra ambos.
- Um ponteiro no formato `**→ [meta](<fonte>#<anchor-correto>)**` usando o anchor computado na Fase 2.

Se for reescrever o índice inteiro, preserve: árvore de decisão/navegação, princípios arquiteturais, tabela de integrações, gotchas como one-liners, quick-refs e comandos. O ganho vem de colapsar as **seções de feature**, não de remover navegação.

Adicione (se ainda não houver) no topo do ÍNDICE e da FONTE a guidance de leitura cirúrgica:

> ⚡ **Leitura da fonte (agentes)**: a fonte tem milhares de linhas — não a leia inteira. Cada ponteiro cita o título exato da seção: `Grep '^## <título>'` na fonte → pega a linha → `Read` com `offset/limit`. Só o índice é auto-carregado por sessão.

---

## Fase 6 — Validar Links (obrigatório, gate de saída)

Rode o validador (Apêndice B). Ele confere que **todo** link `fonte#anchor` e todo link interno `#anchor` do índice resolve para um heading real. **Não finalize com links quebrados** — corrija o anchor (lembre das armadilhas do Apêndice A) e revalide até `0 quebrados`.

---

## Fase 7 — Registrar e Reportar

1. Registrar em `.claude/memory/evolution/applied.md`:
   ```markdown
   ### YYYY-MM-DD — /docs-commands:reconcile — <índice> ↔ <fonte>

   **Drift**: N gaps · N stale · N bloat · N links quebrados
   **Portado para a fonte**: <seções>
   **Índice**: <linhas antes> → <linhas depois> (<% redução>)
   **Validação**: 0 links quebrados ✅
   ```
2. Reporte ao humano o resumo (baseline → resultado, lista do que foi portado/enxugado, validação).
3. **Não commitar automaticamente.** O commit fica com o humano ou com `/pre-pr`. Sugira a mensagem: `docs: reconcilia <índice> (índice) ↔ <fonte> (fonte da verdade)`.

---

## Regras Importantes

1. **Human-in-the-loop** — drift é reportado e o plano aprovado antes de qualquer escrita.
2. **Slicing fiel, nunca retranscrição** — mova texto canônico por shell; transcrever à mão corrompe.
3. **Preserve textos de heading do índice** — anchors são contrato (Decision Tree + back-links da fonte).
4. **Sem heading duplicado na fonte** — retitule seções STALE; verifique com `uniq -d`.
5. **Gate de links** — terminar com 0 links quebrados é obrigatório.
6. **Git é a rede de segurança** — nunca há perda permanente; o índice original fica no histórico.
7. **Genérico** — funciona para qualquer par índice/fonte via argumentos, não só `CLAUDE.md`/`CLAUDE.meta.md`.
8. **Acentos obrigatórios** — todo texto gerado com acentuação correta em português.

---

## Apêndice A — Algoritmo de Anchor do GitHub (com as armadilhas)

Regras (github-slugger), na ordem:
1. `lowercase`.
2. Remover tudo que **não** seja alfanumérico (Unicode, **acentos preservados**), espaço, `-` ou `_`. Isso **remove emoji e pontuação** (`(`, `)`, `.`, `⭐`, `⚠️`, `—`, `→`, `+`, `/`).
3. Cada espaço vira **um** `-`. **NÃO colapsar** múltiplos espaços. **NÃO** remover hífen no início/fim.

Consequências não óbvias (causam links quebrados se ignoradas):
- Heading com **emoji no início** → anchor com **hífen inicial**: `## 📦 BullMQ ...` → `#-bullmq-`.
- Separador `—`/`→`/`+`/`/` entre espaços → **hífen duplo**: `Foo — Bar` → `foo--bar`; `(PX-1 + PX-2)` → `px-1--px-2`.
- ` - ` (hífen entre espaços) → **hífen triplo**: `Sys (X) - CRITICAL` → `sys-x---critical`.
- Acentos são mantidos: `Operações` → `operações`.

Implementação de referência (use exatamente esta — não a versão "ingênua" que faz strip/collapse):

```python
def slug(t):
    t = t.strip().lower().replace('**','').replace('`','')
    out = [c for c in t if c.isalnum() or c in (' ', '-', '_')]
    return ''.join(out).replace(' ', '-')   # sem strip, sem collapse
```

## Apêndice B — Validador de Links

```python
import re, sys
INDEX, SOURCE = sys.argv[1], sys.argv[2]
def slug(t):
    t=t.strip().lower().replace('**','').replace('`','')
    return ''.join(c for c in t if c.isalnum() or c in (' ','-','_')).replace(' ','-')
def anchors(p):
    a=set()
    for ln in open(p):
        m=re.match(r'^(#{1,6})\s+(.*)$', ln)
        if m: a.add(slug(m.group(2).rstrip()))
    return a
src, idx = anchors(SOURCE), anchors(INDEX)
txt = open(INDEX).read()
src_name = re.escape(SOURCE.split('/')[-1])
bad_src = [a for a in re.findall(src_name+r'#([^\s\)\]]+)', txt) if a not in src]
bad_int = [a for a in re.findall(r'\]\(#([^\s\)\]]+)\)', txt) if a not in idx]
print("Links para a fonte quebrados:", bad_src or "NENHUM ✅")
print("Links internos quebrados:", bad_int or "NENHUM ✅")
sys.exit(1 if (bad_src or bad_int) else 0)
```

Uso: `python3 validador.py <ÍNDICE> <FONTE>` — sai com código ≠ 0 se houver link quebrado (serve de gate em CI/pre-pr).
