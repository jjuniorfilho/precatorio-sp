# Skill DOCX - Guia de Replicacao

Este documento lista todos os arquivos necessarios para replicar a skill de geracao de documentos Word (.docx) em outros projetos.

## Arquivos Necessarios

### 1. Skill Definition
**Arquivo:** `.claude/skills/docx/SKILL.MD`

Define as capacidades, regras criticas e padroes de uso do docx-js.

### 2. Comando Invocavel
**Arquivo:** `.claude/commands/docx/report.md`

Comando `/docx:report` que pode ser invocado no chat para gerar documentos.

### 3. Script Gerador
**Arquivo:** `.claude/scripts/docx/generator.js`

Script Node.js que gera os documentos DOCX programaticamente.

## Estrutura de Diretorios

```
.claude/
├── skills/
│   └── docx/
│       └── SKILL.MD              # Documentacao da skill
├── commands/
│   └── docx/
│       └── report.md             # Comando invocavel
└── scripts/
    └── docx/
        └── generator.js          # Script de geracao
```

## Instalacao

### 1. Copiar Arquivos

```bash
# Criar estrutura
mkdir -p .claude/skills/docx
mkdir -p .claude/commands/docx
mkdir -p .claude/scripts/docx

# Copiar do cortex-v1
CORTEX_PATH="/caminho/para/cortex-v1"

cp $CORTEX_PATH/.claude/skills/docx/SKILL.MD .claude/skills/docx/
cp $CORTEX_PATH/.claude/commands/docx/report.md .claude/commands/docx/
cp $CORTEX_PATH/.claude/scripts/docx/generator.js .claude/scripts/docx/
```

### 2. Instalar Dependencia

```bash
npm install docx --save-dev
```

### 3. Verificar Instalacao

```bash
node .claude/scripts/docx/generator.js --help
```

## Uso

### Via Comando (no chat)

```
/docx:report
```

O agente ira guiar voce pelo processo de criacao.

### Via Script (linha de comando)

```bash
# Documento tecnico
node .claude/scripts/docx/generator.js \
  -t technical \
  -T "Arquitetura do Sistema" \
  -o doc_tecnico.docx

# Relatorio executivo
node .claude/scripts/docx/generator.js \
  -t executive \
  -T "Relatorio Q1 2026" \
  -i dados.json \
  -o relatorio.docx

# Proposta comercial
node .claude/scripts/docx/generator.js \
  -t proposal \
  -T "Proposta Cliente XYZ" \
  -o proposta.docx

# Relatorio de consultoria
node .claude/scripts/docx/generator.js \
  -t consulting \
  -T "Diagnostico Operacional" \
  -o consultoria.docx
```

## Tipos de Documento

| Tipo | Descricao | Secoes |
|------|-----------|--------|
| `technical` | Documentacao tecnica | Sumario, Visao Geral, Arquitetura, Requisitos |
| `executive` | Relatorios executivos | Resumo, Metricas, Entregas, Riscos, Proximos Passos |
| `proposal` | Propostas comerciais | Apresentacao, Desafio, Solucao, Investimento, Cronograma |
| `consulting` | Relatorios de consultoria | Diagnostico, Recomendacoes, Plano de Acao, ROI |
| `general` | Documento generico | Introducao, Desenvolvimento, Conclusao |

## Formato de Dados JSON

O arquivo de dados JSON pode conter os seguintes campos (todos opcionais):

```json
{
  "project": "Nome do Projeto",
  "version": "1.0.0",
  "period": "Janeiro - Marco 2026",
  "summary": "Resumo do documento...",
  "highlight": "Destaque principal...",
  "metrics": [
    ["Metrica 1", "Valor", "Meta", "Status"],
    ["Metrica 2", "Valor", "Meta", "Status"]
  ],
  "deliverables": [
    "Entrega 1",
    "Entrega 2"
  ],
  "nextSteps": [
    "Passo 1",
    "Passo 2"
  ],
  "risks": [
    ["Risco 1", "Probabilidade", "Impacto", "Mitigacao"],
    ["Risco 2", "Probabilidade", "Impacto", "Mitigacao"]
  ],
  "objective": "Objetivo do documento...",
  "scope": "Escopo do documento...",
  "stack": [
    "Tecnologia 1",
    "Tecnologia 2"
  ],
  "components": [
    ["Componente", "Tecnologia", "Descricao"]
  ],
  "functionalReqs": [
    "Requisito funcional 1",
    "Requisito funcional 2"
  ],
  "nonFunctionalReqs": [
    "Requisito nao-funcional 1",
    "Requisito nao-funcional 2"
  ]
}
```

## Personalizacao

### Cores Corporativas

Edite as cores no `generator.js`:

```javascript
const COLORS = {
  primary: '1e3a5f',      // Cor principal (headings)
  secondary: 'f0a500',    // Cor de destaque (highlight boxes)
  text: '333333',         // Texto normal
  muted: '666666',        // Texto secundario
  border: 'CCCCCC'        // Bordas
};
```

### Tamanho de Pagina

Ajuste para A4 ou outros formatos:

```javascript
const PAGE = {
  WIDTH: 12240,   // US Letter: 12240, A4: 11906
  HEIGHT: 15840,  // US Letter: 15840, A4: 16838
  MARGIN: 1440    // 1 inch = 1440 DXA
};
```

## Saida

Os documentos sao salvos no diretorio especificado:

```
reports/
└── docs/
    └── YYYY-MM-DD/
        ├── dados.json           # Dados de entrada
        └── documento.docx       # Documento gerado
```

## Troubleshooting

### Sumario nao aparece

O Table of Contents do docx-js requer atualizacao manual:
1. Abra o documento no Word
2. Selecione tudo (Ctrl+A)
3. Pressione F9 para atualizar campos

### Bullets aparecem como caracteres estranhos

Verifique se esta usando `LevelFormat.BULLET` no numbering config, nunca caracteres unicode diretamente.

### Tabelas com largura incorreta

Sempre defina `width: { size: 100, type: WidthType.PERCENTAGE }` no Table.

## Referencias

- [docx-js Documentation](https://docx.js.org/)
- [GitHub: dolanmiu/docx](https://github.com/dolanmiu/docx)
- [Skill DOCX Original](.claude/skills/docx/SKILL.MD)
