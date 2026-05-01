# Issue 004: Pipeline de Extracao e Atualizacao da Base DEPRE (PDF → Supabase)

**Tipo**: Feature
**Prioridade**: P1 - Alta
**Fase**: Fase 2
**Status**: Backlog
**Linear**: FOR-13

---

## POR QUE

- A DEPRE publica mensalmente um PDF atualizado com saldos de precatorios — o portal precisa refletir esses valores atualizados para manter credibilidade
- A importacao manual via Excel (Fase 1) nao escala — precisa ser automatizada
- Saber se um processo ja esta cadastrado na DEPRE ou ainda e um direito creditorio e essencial para qualificar o lead
- Identificar processos com homologacao de calculo revela pipeline de futuros precatorios (oportunidades comerciais)

## O QUE

### 1. Extrator DEPRE (`extract_depre.py`)
Motor principal. Usa `pdftotext` (poppler) + regex para parsear o PDF da Lista DEPRE (~200K registros), gerando a base de saldos.

- **Input**: PDF da Lista DEPRE (ex: `ListaPrecatorioPendente_707495.pdf`)
- **Output**: Excel com uma linha por ordem de pagamento (12 colunas)
- Parse por blocos "Ordem de Pagamento:" com regex para cada campo
- Suporta extracao parcial (por range de paginas) para testes
- **Frequencia**: Mensal, quando a DEPRE publica atualizacao

### 2. Cruzamento processos x DEPRE (`match_depre_csv.py`)
Cruza base de processos (CSV do TJSP) com a lista DEPRE para identificar status.

- Match por dois campos: Nº Processo DEPRE e Nº de Autos
- Lookup O(1) com indices pre-construidos
- Detecta duplicidades (mesmo numero CSV com multiplas ordens DEPRE)
- Enriquece com saldo DEPRE a partir de CSV separado (`depre_saldo.csv`)
- Gera Excel com dados cruzados + aba de resumo

### 3. Coletor de homologacoes (`collect_homologacoes.py`)
Consulta API publica PJe Comunica para identificar publicacoes de homologacao de calculo no TJSP.

- API: `https://comunicaapi.pje.jus.br/api/v1/comunicacao`
- Detecta homologacao via regex em 9 padroes
- Rate limiting (0.3s entre requests)
- Output: JSON com dados do processo + trecho relevante

## COMO

### Dependencias tecnicas
- Python 3
- `pdftotext` (poppler-utils)
- `openpyxl` (geracao Excel)
- Acesso a API PJe Comunica (publica, sem auth)

### Fluxo mensal (Fase 2)
1. Download do PDF atualizado da DEPRE
2. Executar `extract_depre.py` → gera Excel/CSV atualizado
3. Executar `match_depre_csv.py` → cruza com base de processos
4. Script Node.js faz UPSERT no Supabase (issue FOR-10)
5. Portal reflete saldos atualizados

### Origem do codigo
Scripts originais em `capano-discovery-toolkit.zip` → `bin/`

### Fora de escopo desta issue
- Automacao do download do PDF (pode ser manual inicialmente)
- Interface admin para trigger da importacao (issue FOR-11)
