# Audit Structure — Auditoria e Correção da Estrutura de Pastas

Você é responsável por auditar a **estrutura de pastas e a nomenclatura de arquivos** de um repositório contra o padrão do Cortex, e — mediante aprovação — corrigi-la preservando histórico e referências.

**Por que isso importa**: os comandos do Cortex são encadeados e localizam artefatos por **caminho e nome convencionais**. Um PRD salvo fora do lugar, uma ADR com nomenclatura divergente ou um `backlog.md` dentro de `adr/` não são lidos por `/start`, `/plan`, `/spec` nem pelos agentes de `pre-pr`. O arquivo existe, mas para o framework ele é invisível — e o time conclui que "o Cortex não pegou o contexto".

**Princípio fundamental**: o comando **propõe**, o humano **aprova**. Nenhuma movimentação sem confirmação explícita. Git é a rede de segurança.

> **IMPORTANTE**: caminhos `.claude/memory/` referem-se à pasta `memory/` dentro do `.claude/` do **projeto atual**, NUNCA a `~/.claude/memory/` do usuário.

---

## Configuração

Argumentos: `#$ARGUMENTS`

| Modo | Invocação | Efeito |
|------|-----------|--------|
| Auditoria (default) | `/meta:audit-structure` | Só relatório. Nada é movido |
| Correção | `/meta:audit-structure --fix` | Relatório + plano de correção + aplicação após aprovação |
| Escopo restrito | `/meta:audit-structure docs` | Audita apenas a subárvore indicada |

---

## Fase 1 — Detectar o perfil do repositório

Duas convenções de fundação convivem nos projetos e **ambas são válidas**. Detecte qual está em uso antes de julgar qualquer coisa:

| Perfil | Raiz da fundação | Exemplo |
|--------|------------------|---------|
| **A — docs-based** | `docs/` | cortex-framework, galaticos-os |
| **B — master-docs-based** | `master-docs/` + `docs/` auxiliar | px-agents |

Detecção: se `master-docs/` existe com conteúdo de fundação (ADRs, technical-context, business-context), o perfil é B; senão A.

**Nunca converta um perfil no outro.** A escolha é do projeto. O que se audita é a **consistência interna** do perfil detectado — mistura dos dois é que é drift.

Registre o perfil detectado no relatório. Se ambíguo (fundação espalhada nos dois), esse é o primeiro achado a reportar.

---

## Fase 2 — Mapear o layout canônico esperado

Para o perfil detectado, o layout esperado:

```
<fundação>/                      # docs/ (perfil A) ou master-docs/ (perfil B)
  index.md                       # índice mestre — obrigatório
  business-context/
    index.md
    features/                    # catálogo de features
  specs/technical/  |  technical-context/
    index.md
    adr/                         # ADRs, uma decisão por arquivo
    CLAUDE.meta.md               # fonte da verdade técnica
    CODEBASE_GUIDE.md
  technical-context/briefing/    # gerado por /discover
  guides/

docs/                            # perfil B: auxiliar — discovery, protótipos, apresentações
.claude/
  agents/ commands/ skills/ rules/ templates/
  memory/                        # MEMORY.md, sessions/, patterns/, evolution/
  sessions/                      # micro-contexto por tarefa: context.md, architecture.md, plan.md
```

**Regra de separação** (a mais violada): fundação de negócio/produto/ADR vive na fundação; material auxiliar — discovery, protótipo, apresentação, amostra — vive em `docs/`. Nada que não pertença ao fluxo de engenharia entra em `.claude/`.

Subestrutura de `.claude/commands/` esperada: `engineer/`, `product/`, `docs-commands/`, `master-docs-commands/`, `meta/`, `report/`, `docx/`. Comando solto na raiz de `commands/` é drift.

---

## Fase 3 — Detecção

Trabalhe com **dados, não impressões**: gere as evidências por shell antes de classificar.

### Categorias

| Categoria | Como detectar | Ação em `--fix` |
|-----------|---------------|-----------------|
| **MISPLACED** | Arquivo de fundação fora da raiz correta do perfil (ex.: ADR em `docs/` no perfil B; comando solto na raiz de `commands/`) | `git mv` para o caminho canônico |
| **INTRUSO** | Arquivo que não pertence à pasta (ex.: `backlog.md` dentro de `adr/`, `.pptx` em `specs/`) | Mover para `docs/` ou remover, conforme natureza |
| **NOMENCLATURA** | ADR fora de `ADR-NNN-slug.md` ou `NNN-slug.md`; feature doc sem padrão; índice com nome divergente | `git mv` normalizando o nome |
| **AUSENTE** | Pasta ou índice obrigatório do perfil que não existe | Criar, ou apontar o comando que gera (`/discover`, `/build-tech-docs`) |
| **DUPLICADO** | Mesma fundação em dois lugares (perfis misturados) | **Nunca resolver automaticamente** — exige decisão humana |

### Comandos de apoio

```bash
# perfil e raízes
ls -d docs master-docs .claude 2>/dev/null

# ADRs: onde estão e como se chamam
find . -path ./node_modules -prune -o -type d -name "adr*" -print 2>/dev/null
ls <adr-dir> | grep -vE '^(ADR-)?[0-9]{3}[a-z]?-.+\.md$'      # fora do padrão

# comandos soltos na raiz de commands/
ls .claude/commands/*.md 2>/dev/null

# intrusos em .claude/ que não são do fluxo de engenharia
find .claude -maxdepth 1 -type f ! -name "settings*.json" 2>/dev/null

# artefatos de update pendentes
find . -name "*.cortex-new*" -not -path "./.git/*" 2>/dev/null
```

### Relatório de drift

Tabela: caminho atual | categoria | caminho proposto | evidência. **Não aplique nada ainda.**

---

## Fase 4 — Apresentar plano e obter aprovação

```
## Estrutura: drift detectado

Perfil: <A docs-based | B master-docs-based>   Raiz da fundação: <path>

- MISPLACED (fora do lugar):   <n>
- INTRUSO (não pertence):      <n>
- NOMENCLATURA (nome fora do padrão): <n>
- AUSENTE (obrigatório faltando):     <n>
- DUPLICADO (exige decisão sua):      <n>

Impacto: <quais comandos deixam de enxergar quais arquivos>

Aprovar tudo (a) | Aprovar seletivamente (s) | Só relatório (c)
```

Em modo auditoria (sem `--fix`), pare aqui.

---

## Fase 5 — Aplicar correções

1. **Sempre `git mv`, nunca `mv`.** Preserva histórico e blame — o arquivo movido continua rastreável.
2. **Um `git mv` por vez**, verificando o resultado. Movimentação em lote falha silenciosamente quando o destino não existe.
3. Criar diretório de destino antes (`mkdir -p`).
4. **DUPLICADO nunca é resolvido automaticamente.** Apresente as duas versões, o diff e pergunte qual é a fonte da verdade.

---

## Fase 6 — Corrigir as referências (gate obrigatório)

**Mover arquivo quebra todo link que aponta para ele.** Esta fase não é opcional — pular aqui converte um problema de organização em um problema pior, de documentação quebrada.

Para cada arquivo movido:

```bash
# quem apontava para o caminho antigo
grep -rn "<caminho-antigo>" . --include="*.md" --exclude-dir=.git --exclude-dir=node_modules
```

Atualize cada referência para o caminho novo. Cobrir: índices (`index.md`), `CLAUDE.md`, `CLAUDE.meta.md`, briefing em `technical-context/`, ADRs que citam outras ADRs, e os próprios comandos em `.claude/commands/` que hardcodam caminhos.

**Validação de saída**: nenhum link apontando para caminho movido pode sobrar. Se o repositório tiver o par índice/fonte, rode o validador do `/docs-commands:reconcile` (Apêndice B) como confirmação.

---

## Fase 7 — Registrar e reportar

1. Registrar em `.claude/memory/evolution/applied.md`:
   ```markdown
   ### YYYY-MM-DD — /meta:audit-structure — <repo>

   **Perfil**: <A|B>
   **Drift**: N misplaced · N intrusos · N nomenclatura · N ausentes · N duplicados
   **Movidos**: <lista resumida>
   **Referências atualizadas**: N arquivos
   **Validação**: 0 links quebrados
   ```
2. Reportar ao humano: perfil, drift encontrado, o que foi movido, o que ficou pendente de decisão.
3. **Não commitar automaticamente.** Sugira: `refactor(docs): normaliza estrutura de pastas ao padrão Cortex`.

---

## Regras Importantes

1. **Human-in-the-loop** — nenhuma movimentação sem aprovação explícita.
2. **`git mv` sempre** — preserva histórico; `mv` puro descarta rastreabilidade.
3. **Perfil é do projeto** — audite consistência interna, nunca converta A em B.
4. **Referências são gate** — mover sem atualizar links é regressão, não correção.
5. **DUPLICADO é decisão humana** — duas fundações concorrentes exigem escolha, não heurística.
6. **Não toque em `.claude/memory/` nem `.claude/sessions/`** — são dados, não estrutura. Reorganizá-los destrói continuidade entre sessões.
7. **Customização não é drift** — agente ou comando específico do domínio é legítimo. Só reporte como achado se estiver fora da subpasta correta.
8. **Acentos obrigatórios** — todo texto gerado com acentuação correta em português.
