# Evolution Schema — Referência Detalhada

> Schemas completos para os arquivos de evolução, thresholds configuráveis e exemplos.
> Carregado sob demanda quando o agente precisa de detalhes de formato.

---

## Schema: command-usage (JSONL)

> **v3.0 — formato JSONL.** O arquivo canonico agora e `command-usage.jsonl`: **uma entrada
> por linha**, sem array externo. JSON com array nao tem append — cada gravacao lia o arquivo
> inteiro e o reserializava, e como o hook roda a cada prompt o custo crescia com o historico
> (884 KB e 19 ms no repo controladoria com 1349 entradas). Append em JSONL e O(1),
> independente do tamanho.
>
> Ganhos alem da performance: uma linha corrompida custa **uma entrada**, nao o arquivo
> inteiro; e o conflito de merge e por linha — relevante porque sessoes vivem em branches e
> trabalho paralelo e o caso normal, nao a excecao.
>
> **Leitura**: consumidores devem ler `command-usage.jsonl` **e** o legado
> `command-usage.json` (array), concatenando na ordem cronologica. O `.json` fica congelado
> como historico; nada e migrado nem descartado.
>
> **v2.0** — a escrita passou a ser garantida por hook (`.claude/scripts/telemetry-hook.py`,
> registrado em `.claude/settings.json`), não por instrucao no fim do comando. Instrucao em
> prompt depende do agente lembrar; com a janela saturada ele nao lembra — este repositorio
> acumulou 8 entradas em 5 meses sob o modelo antigo. O hook nao depende da janela.

### Formato JSONL (canonico)

```jsonl
{"timestamp":"2026-07-25T01:09:55+00:00","date":"2026-07-25","command":"/engineer:warm-up","task_id":null,"author":"Rafael Fiales","branch":"main","source":"human"}
{"timestamp":"2026-07-25T01:12:03+00:00","date":"2026-07-25","command":"/engineer:start","task_id":"PX-4123","author":"Rafael Fiales","branch":"rafaelfiales/px-4123","source":"human"}
```

Sem virgula entre linhas, sem colchetes. Cada linha e um objeto JSON completo e independente.

### Como ler (produtor unico, dois arquivos)

```python
entries = []
legacy = Path(".claude/memory/evolution/command-usage.json")
if legacy.exists():
    entries += json.loads(legacy.read_text()).get("entries", [])   # historico congelado
current = Path(".claude/memory/evolution/command-usage.jsonl")
if current.exists():
    for line in current.read_text().splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            entries.append(json.loads(line))
        except Exception:
            continue      # linha corrompida custa uma entrada, nao o arquivo
```

### Os tres canais, e como medir cada um

Errar o canal na hora de medir produz a conclusao errada com dado certo. Aconteceu em
2026-07-26: uma verificacao procurou `source: "agent"` com `command` preenchido para julgar se
a telemetria de PROCESSO da frota funcionava. Veio zero — e o zero era real, mas dizia respeito
a outro canal. A telemetria de processo grava `source: "fleet"`.

| `source` | Quem produz | Tem `command`? | Tem `event`? |
|---|---|---|---|
| `human` | `UserPromptSubmit` — alguem digitou `/comando` | sim | nao |
| `agent` | `PostToolUse[Skill]` — comando executado por ferramenta | sim | nao |
| `agent` | `SubagentStart` / `SubagentStop` | nao (`null`) | `subagent.*` |
| `fleet` | `--emit` dos scripts do Fleet | as vezes | `fleet.*` |

**O que perguntar, e onde olhar:**

| Pergunta | Filtro |
|---|---|
| A frota rodou? | `source == "fleet"` — os eventos de fase sao a prova mais forte, porque o gate so emite `pass` com artefato commitado |
| Comandos foram executados por agente, nao digitados? | `source == "agent"` **e** `command != null` |
| Quantos subagentes a onda abriu? | `event` comecando com `subagent.` |
| O humano usou o processo a mao? | `source == "human"` |

> ⚠️ `source: "agent"` significa **"veio por ferramenta"**, nao **"foi um subagente"**: o lead
> invocando uma Skill cai nessa categoria tambem. Para separar, use `agent_id` — o harness so o
> preenche quando o hook dispara dentro de um subagente. Contar frota por `source == "agent"`
> sem esse discriminante infla com as invocacoes do proprio lead.

> ⚠️ **Zero em `subagent.*` costuma ser janela de medicao, nao instrumento morto.** Hook so
> passa a valer em **sessao nova**: sessoes ja abertas seguem com a configuracao que carregaram
> no inicio. Medicao de 2026-07-26 em tres repos deu `subagent.start` = 0 e `agent_type` sempre
> vazio, e a conclusao registrada foi que a camada nao identificava o subagente. **Estava
> errada** — a janela era anterior ao hook estar ativo.
>
> Com o hook ativo ha horas (px-agents, 2026-07-27): **65 `subagent.start`**, 76 `subagent.stop`,
> e `agent_type` preenchido com `adr-compliance-checker`, `code-reviewer`, `branch-code-reviewer`,
> `branch-test-planner`, `branch-master-docs-checker`, `branch-documentation-writer`, `Explore`,
> `workflow-subagent`, `general-purpose`. A camada identifica, sim.
>
> Antes de ler um zero aqui: verificar **ha quanto tempo o hook existe naquele repo** (git log do
> `settings.json`) e se houve sessao nova depois. Zero numa janela que antecede o instrumento nao
> diz nada sobre o instrumento — e `agents_used: []` numa entrada dessa janela significa "o hook
> nao estava ativo", nao "nenhum agente".

### Sem teto de entradas

A versao anterior truncava em 5000 registros para conter o custo de reserializacao. Com
append O(1) o teto perdeu a razao de existir, e truncar destruia a serie historica que a
auditoria de aderencia usa para medir tendencia. Se um dia o arquivo precisar ser reduzido,
isso e trabalho de um comando de compactacao — nao do hook que roda a cada prompt.

### Schema da entrada (v2.0, inalterado)

```json
{
  "version": "2.0",
  "entries": [
    {
      "timestamp": "2026-07-24T23:38:47+00:00",
      "date": "2026-03-05",
      "command": "/engineer:work",
      "task_id": "PX-4123",
      "author": "Rafael Fiales",
      "source": "human",
      "session_id": "abc123",
      "branch": "feat/user-auth",
      "feature": "User Authentication",
      "agents_used": [
        "test-engineer",
        "code-reviewer"
      ],
      "duration_phases": 3,
      "issues_found": {
        "critica": 0,
        "major": 2,
        "minor": 5
      },
      "patterns_detected": [
        "repository-pattern",
        "jwt-auth",
        "zod-validation"
      ],
      "user_corrections": [
        "renamed variable from 'data' to 'userData'",
        "moved enum to shared/enums/"
      ],
      "skills_invoked": [
        "memory-manager"
      ],
      "confidence": "alta"
    }
  ]
}
```

### Campos Obrigatórios (escritos pelo hook, sempre presentes)

| Campo | Tipo | Descrição |
|-------|------|-----------|
| timestamp | string | ISO 8601 com hora. `date` sozinho tem granularidade de dia e impede verificar a **ordem** dos comandos dentro do mesmo dia |
| date | string | Data ISO (YYYY-MM-DD) — mantido para compatibilidade com v1.0 |
| command | string | Comando na **forma canônica** (ver abaixo) |
| task_id | string \| null | Identificador do entregável. Sem ele não há como ligar a cadeia de comandos ao PR |
| author | string | `git config user.name`. Habilita atribuição |
| branch | string | Nome do branch |
| source | string | `human` (digitado) ou `agent` (invocado por sub-agente, caso da frota) |

### Forma canônica do comando

**Namespace completo, sem sufixo livre**: `/engineer:pre-pr`, `/product:check`, `/meta:evolve`.

O produtor nunca grava variante curta (`/pre-pr`) nem sufixo entre parênteses. O `px-agents`
acumulou **15 grafias para 7 comandos** — `/pre-pr`, `/engineer:pre-pr`, `/engineer:pre-pr (F7)`,
`/engineer:pre-pr (FORMAL)` — e nenhuma cadeia era reconstruível.

Para qualificar a execução (fase, lote, modo), use campo próprio. **Nunca concatenar no nome
do comando.**

Consumidores devem normalizar na leitura para tolerar dados v1.0 já gravados.

### Campos de enriquecimento (escritos pelo comando, quando ele chega ao fim)

O hook garante que a entrada existe; o comando a enriquece com o que só ele sabe.

| Campo | Tipo | Descrição |
|-------|------|-----------|
| agents_used | string[] | Agentes invocados durante a sessão |
| confidence | string | "alta", "media" ou "baixa" |

### Campos Opcionais

| Campo | Tipo | Descrição |
|-------|------|-----------|
| feature | string | Nome da feature |
| duration_phases | number | Número de fases completadas |
| issues_found | object | Contagem por severidade |
| patterns_detected | string[] | Padrões arquiteturais detectados |
| user_corrections | string[] | Correções feitas pelo usuário |
| skills_invoked | string[] | Skills utilizadas |
| outcome | string | "success", "partial" ou "failed" |
| notes | string | Observação relevante sobre a sessão |

### Regra de Append

Uma entrada por linha, appendada ao fim de `command-usage.jsonl` — sem ler nem reserializar
o arquivo (append O(1)). Quem escreve é o hook (`.claude/scripts/telemetry-hook.py`), não
instrução em prompt.

O `command-usage.json` legado fica **congelado como histórico**: nada é escrito nele, nada é
migrado, nada é descartado. Não há teto de entradas — ver "Sem teto de entradas" acima.

---

## Schema: agent-performance.md

```markdown
### 2026-03-05 — /work — feat/user-auth

**Agentes invocados**: test-engineer, code-reviewer

**Performance por agente**:

#### test-engineer
- **Resultado**: Positivo
- **Testes escritos**: 8 (6 unit, 2 integration)
- **Cobertura**: 85%
- **Observações**: Cobertura adequada, testes bem estruturados

#### code-reviewer
- **Resultado**: Positivo com ressalvas
- **Issues encontradas**: 2 MAJOR (naming), 5 MINOR (estilo)
- **Issues CRÍTICAS**: 0
- **Observações**: Sugeriu renomear variável, aceito pelo usuário

**Padrões recorrentes**:
- Repository pattern usado consistentemente (3ª vez)
- Zod validation em todos os schemas (2ª vez)

**Sugestões do usuário**:
- "Sempre mover enums para shared/enums/" (preferência explícita)
```

### Regras

- Append-only (novas entradas no final)
- Reter últimos 90 dias
- Marcar padrões recorrentes com contagem: "(Nª vez)"
- Separar observações positivas de problemas

---

## Schema: suggestions.md

```markdown
# Evolution Suggestions

> Propostas geradas pelo comando /evolve.
> Permanente — histórico completo de evolução.

---

## Análise de 2026-03-05

**Sessões analisadas**: 12
**Período**: 2026-02-20 a 2026-03-05
**Propostas geradas**: 3

### Proposta 1: Adicionar Repository Pattern como padrão
- **Score**: Alta (detectado em 8/12 sessões)
- **Categoria**: architecture
- **Evidência**: sessions/2026-02-20, 2026-02-23, 2026-02-25, 2026-02-28, 2026-03-01, 2026-03-02, 2026-03-04, 2026-03-05
- **Estado atual**: Repository pattern não é mencionado nos agentes
- **Mudança proposta**: Adicionar instrução no agente backend para sempre usar Repository Pattern
- **Impacto**: agente backend, template de code-reviewer
- **Reversibilidade**: Remover instrução do agente (1 edit)
- **Status**: ✅ Aplicada em 2026-03-06 (commit abc123)

### Proposta 2: Prevenir remoção de acentos em rewrites
- **Score**: Média (detectado em 3/12 sessões)
- **Categoria**: debugging
- **Evidência**: sessions/2026-02-25, 2026-03-01, 2026-03-05
- **Estado atual**: Ao reescrever arquivos markdown, acentos são às vezes removidos
- **Mudança proposta**: Adicionar verificação de acentos no checklist do code-reviewer
- **Impacto**: agente code-reviewer
- **Reversibilidade**: Remover instrução do checklist (1 edit)
- **Status**: ⏳ Pendente aprovação

### Proposta 3: Mover enums para shared/
- **Score**: Baixa (detectado em 2/12 sessões)
- **Categoria**: preferences
- **Evidência**: sessions/2026-03-04, 2026-03-05
- **Estado atual**: Enums criados junto com o módulo
- **Mudança proposta**: Instrução para mover enums para shared/enums/
- **Impacto**: convenções de código
- **Reversibilidade**: Reverter instrução
- **Status**: 📊 Monitorando (aguardar mais evidência)
```

---

## Schema: applied.md

```markdown
# Applied Evolution Changes

> Registro de todas as mudanças aplicadas via /evolve.
> Permanente — auditoria completa.

---

### 2026-03-06 — evolve(architecture): adicionar Repository Pattern
- **Proposta original**: suggestions.md, Análise de 2026-03-05, Proposta 1
- **Score**: Alta (8/12 sessões)
- **Commit**: abc1234
- **Arquivos modificados**:
  - `.claude/agents/backend-developer.md` (adicionada instrução)
  - `.claude/agents/code-reviewer.md` (adicionado ao checklist)
- **Aprovado por**: [usuário]
- **Monitoramento**: Verificar em 5 sessões se padrão é seguido
- **Resultado**: ✅ Confirmado — padrão seguido em 5/5 sessões seguintes
```

---

## Thresholds Configuráveis

| Parâmetro | Valor Padrão | Descrição |
|-----------|--------------|-----------|
| MIN_SESSIONS_ALTA | 5 | Sessões mínimas para score Alta |
| MIN_SESSIONS_MEDIA | 3 | Sessões mínimas para score Média |
| RETENTION_DAYS_PERF | 90 | Dias de retenção para agent-performance.md |
| MONITORING_SESSIONS | 5 | Sessões para monitorar impacto pós-aplicação |
| STALE_THRESHOLD_DAYS | 30 | Dias sem referência para marcar STALE |
| EXPIRED_THRESHOLD_DAYS | 90 | Dias sem referência para propor remoção |

**Nota**: Estes valores são convenções documentadas (não código). Ajustar conforme maturidade do projeto.

---

## Quem coleta o quê

**Uso de comando** (`command-usage.jsonl`) nao aparece nesta tabela porque nao depende de
comando nenhum: o hook cobre **todos**, e os scripts do Fleet emitem os eventos de processo
via `--emit`. Instrucao em prompt nao e mecanismo de coleta — e o modelo que rendeu 8
entradas em 5 meses.

A tabela abaixo lista o que **so o agente** consegue produzir, porque exige julgamento:

| Comando | Coleta por instrucao |
|---------|---------------------|
| /work | Performance dos agentes invocados na fase |
| /pre-pr | Performance dos 4 agentes do gate |
| /discover | Performance de agentes auxiliares, se invocados |
| /collect | Performance dos sub-agentes, se usados |
| /spec | Performance do master-docs-gate-keeper, se invocado |
| /bug-collect | Performance de agentes auxiliares + patterns de debug |
