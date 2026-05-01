# Guia Mermaid.js — Tema Dark AI Frontiers

> Este guia documenta como usar diagramas Mermaid.js no tema dark da skill html-presentations.
> Todos os diagramas devem usar a paleta de cores escura para integrar com o fundo navy (#0b1929).

---

## Configuração JavaScript

Incluir no HTML antes do fechamento de `</body>`:

```javascript
mermaid.initialize({
    startOnLoad: true,
    theme: 'dark',
    flowchart: {
        useMaxWidth: true,
        htmlLabels: true,
        curve: 'basis',
        padding: 15
    },
    sequence: {
        useMaxWidth: true,
        wrap: true,
        width: 180,
        height: 50,
        boxMargin: 10,
        mirrorActors: false
    },
    themeVariables: {
        background: 'transparent',
        primaryColor: '#0d3b66',
        primaryTextColor: '#e0e0e0',
        primaryBorderColor: '#4fc3f7',
        lineColor: '#4fc3f7',
        secondaryColor: '#132d4a',
        tertiaryColor: '#1a3a5c',
        mainBkg: '#0d3b66',
        nodeBorder: '#4fc3f7',
        clusterBkg: 'rgba(79,195,247,0.08)',
        clusterBorder: '#4fc3f7',
        titleColor: '#4fc3f7',
        edgeLabelBackground: 'transparent',
        nodeTextColor: '#e0e0e0',
        actorBkg: '#0d3b66',
        actorBorder: '#4fc3f7',
        actorTextColor: '#e0e0e0',
        actorLineColor: '#4fc3f7',
        noteBkgColor: '#132d4a',
        noteTextColor: '#e0e0e0',
        noteBorderColor: '#4fc3f7',
        activationBkgColor: '#1a3a5c',
        activationBorderColor: '#4fc3f7',
        signalColor: '#b0bec5',
        signalTextColor: '#e0e0e0',
        labelBoxBkgColor: '#0d3b66',
        labelBoxBorderColor: '#4fc3f7',
        labelTextColor: '#e0e0e0',
        loopTextColor: '#4fc3f7',
        altSectionBkgColor: 'rgba(79,195,247,0.05)'
    },
    securityLevel: 'loose'
});
```

---

## Paleta de Cores para Nós

Use `style` directives no Mermaid para colorir nós individuais:

| Cor | Fill | Stroke | Text Color | Uso Recomendado |
|-----|------|--------|------------|-----------------|
| **Cyan (padrão)** | `#0d3b66` | `#4fc3f7` | `#e0e0e0` | Nós neutros, processos genéricos |
| **Verde** | `#0a3622` | `#66bb6a` | `#66bb6a` | Sucesso, aprovação, resultado positivo |
| **Laranja** | `#3a2200` | `#ffa726` | `#ffa726` | Atenção, processo em andamento, alerta |
| **Vermelho** | `#3a0a0a` | `#ef5350` | `#ef5350` | Erro, risco alto, bloqueio |
| **Roxo** | `#1a0d3a` | `#ab47bc` | `#ab47bc` | Diferenciação, categoria especial |
| **Cyan Brilhante** | `#0d2a4a` | `#4fc3f7` | `#4fc3f7` | Destaque, entrada principal |

### Sintaxe de Style

```
style NOME_NO fill:#COR_FILL,stroke:#COR_STROKE,color:#COR_TEXTO
```

Exemplo:
```
style A fill:#0d3b66,stroke:#4fc3f7,color:#e0e0e0
style B fill:#0a3622,stroke:#66bb6a,color:#66bb6a
style C fill:#3a0a0a,stroke:#ef5350,color:#ef5350
```

---

## Clusters (Subgrafos)

```
subgraph TITULO["Titulo do Grupo"]
    direction TB
    A --> B
end
```

Style padrão de cluster (aplicado automaticamente via themeVariables):
- Background: `rgba(79,195,247,0.08)`
- Border: `#4fc3f7`

Para customizar:
```
style TITULO fill:rgba(79,195,247,0.08),stroke:#4fc3f7
```

---

## Acentuação em Labels

### Regra Geral
- Em texto HTML fora do Mermaid: **SEMPRE** usar acentuação correta
- Em labels Mermaid: **PREFERIR** usar acentuação, mas testar renderização

### Se Acentuação Causar Erro
Alguns caracteres especiais podem causar problemas de parsing no Mermaid. Nesse caso:
1. Use aspas duplas no label: `A["Diagnóstico"]`
2. Se ainda falhar, remova acentos apenas no label Mermaid: `A["Diagnostico"]`
3. Documente no HTML ao redor (título, parágrafo) com a grafia correta

### Melhor Prática
Sempre usar aspas duplas em labels com acentos:
```
A["Automação"] --> B["Validação"]
```

---

## Exemplos por Tipo de Diagrama

### Flowchart (graph TB / graph LR)

```html
<div class="diagram-container">
    <div class="mermaid">
graph TB
    START["Inicio do Processo"] --> ANALISE["Analise de Dados"]
    ANALISE --> DECISAO{"Aprovado?"}
    DECISAO -->|"Sim"| IMPLEMENTA["Implementacao"]
    DECISAO -->|"Nao"| REVISAO["Revisao"]
    REVISAO --> ANALISE
    IMPLEMENTA --> DEPLOY["Deploy"]

    style START fill:#0d2a4a,stroke:#4fc3f7,color:#4fc3f7
    style ANALISE fill:#0d3b66,stroke:#4fc3f7,color:#e0e0e0
    style DECISAO fill:#3a2200,stroke:#ffa726,color:#ffa726
    style IMPLEMENTA fill:#0a3622,stroke:#66bb6a,color:#66bb6a
    style REVISAO fill:#3a0a0a,stroke:#ef5350,color:#ef5350
    style DEPLOY fill:#1a0d3a,stroke:#ab47bc,color:#ab47bc
    </div>
</div>
```

### Sequence Diagram

```html
<div class="diagram-container">
    <div class="mermaid">
sequenceDiagram
    participant U as Usuario
    participant S as Sistema
    participant IA as Agente IA
    participant H as Humano

    U->>S: Submete solicitacao
    S->>IA: Processa com IA
    IA->>IA: Analisa contexto
    IA->>H: Envia para validacao
    H->>S: Aprova resultado
    S->>U: Entrega final
    </div>
</div>
```

### Gantt Chart

```html
<div class="diagram-container">
    <div class="mermaid">
gantt
    title Roadmap de Implementacao
    dateFormat YYYY-MM
    axisFormat %b/%Y

    section Fase 1
    Nivelamento         :f1, 2026-03, 3M
    Governanca          :f1g, 2026-03, 2M

    section Fase 2
    Quick Wins           :f2, after f1, 3M
    Validacao            :f2v, after f1g, 3M

    section Fase 3
    Integracao           :f3, after f2, 3M
    Escala               :f3e, after f2v, 3M
    </div>
</div>
```

### C4 Container Diagram (usando flowchart)

```html
<div class="diagram-container">
    <div class="mermaid">
graph TB
    subgraph EXTERNO["Sistemas Externos"]
        API_EXT["API Externa"]
        DB_EXT[("Banco de Dados")]
    end

    subgraph SISTEMA["Sistema Principal"]
        direction TB
        WEB["Aplicacao Web"]
        API["API Backend"]
        AGENTE["Agente de IA"]
    end

    WEB --> API
    API --> AGENTE
    API --> DB_EXT
    AGENTE --> API_EXT

    style WEB fill:#0d3b66,stroke:#4fc3f7,color:#e0e0e0
    style API fill:#0d3b66,stroke:#4fc3f7,color:#e0e0e0
    style AGENTE fill:#0a3622,stroke:#66bb6a,color:#66bb6a
    style API_EXT fill:#1a0d3a,stroke:#ab47bc,color:#ab47bc
    style DB_EXT fill:#3a2200,stroke:#ffa726,color:#ffa726
    </div>
</div>
```

---

## Container HTML para Diagramas

Sempre usar esta estrutura:

```html
<div class="diagram-container">
    <div class="mermaid">
        <!-- código mermaid aqui -->
    </div>
</div>
```

O CSS garante:
- Centralização horizontal e vertical
- Altura máxima de 72vh (para não ultrapassar o slide)
- SVG responsivo (max-width 100%)
- Fundo transparente (herda do slide)

---

## Dicas de Performance

1. **Evitar diagramas muito complexos** — mais de ~20 nós pode ficar ilegível em um slide
2. **Usar direction** — `graph TB` (top-bottom) funciona melhor em slides landscape
3. **Agrupar com subgraphs** — melhora a leitura em diagramas complexos
4. **Textos curtos nos nós** — máximo ~3 palavras por label para legibilidade
5. **CDN**: Sempre usar `https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js`
