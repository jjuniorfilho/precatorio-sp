# Templates de Tipos de Slide — AI Frontiers HTML

> Todos os templates abaixo devem ser inseridos dentro do container `<div class="presentation">` no template base.
> Cada slide usa `data-slide="N"` para a navegação funcionar.

---

## 1. Title Slide (Capa)

```html
<div class="slide title-slide active" data-slide="1">
    <div class="slide-content">
        <div class="slide-label">CATEGORIA OU TIPO DO DOCUMENTO</div>
        <h1>Título Principal da Apresentação</h1>
        <div class="divider"></div>
        <p class="subtitle">Subtítulo descritivo com mais detalhes sobre o conteúdo</p>
        <p class="authors">
            Elaborado por <span>Nome da Empresa</span> para <span>Nome do Cliente</span>
        </p>
    </div>
</div>
```

**Notas:**
- Primeiro slide sempre tem a classe `active`
- data-slide="1" para ser o primeiro
- `.slide-label` é o texto pequeno em cyan acima do título
- `.divider` é a linha horizontal gradient
- `.authors span` fica em cyan-light

---

## 2. Agenda / Índice

```html
<div class="slide" data-slide="2">
    <div class="slide-content">
        <div class="slide-label">VISÃO GERAL</div>
        <h2>Agenda</h2>
        <p>Navegue pelas seções desta apresentação</p>
        <div class="agenda-grid">
            <div class="agenda-item">
                <div class="item-number">01</div>
                <h3>Nome da Seção</h3>
                <p>Breve descrição do conteúdo desta seção</p>
            </div>
            <div class="agenda-item">
                <div class="item-number">02</div>
                <h3>Segunda Seção</h3>
                <p>Descrição do segundo bloco de conteúdo</p>
            </div>
            <div class="agenda-item">
                <div class="item-number">03</div>
                <h3>Terceira Seção</h3>
                <p>Descrição do terceiro bloco</p>
            </div>
            <!-- Adicione mais agenda-items conforme necessário -->
        </div>
    </div>
</div>
```

**Notas:**
- `.agenda-grid` faz grid de 3 colunas
- `.agenda-item` tem hover effect na borda
- `.item-number` é o número grande translúcido (2rem, cyan 30% opacity)

---

## 3. Section Header (Separador de Seção)

```html
<div class="slide section-header" data-slide="3">
    <div class="slide-content">
        <div class="section-number">01</div>
        <h2>Nome da Seção</h2>
        <p>Descrição breve do que será abordado nesta seção</p>
    </div>
</div>
```

**Notas:**
- `.section-number` é o número gigante (5rem) translúcido
- Texto centralizado automaticamente
- Use como divisor visual entre blocos temáticos

---

## 4. Conteúdo com Tabela

```html
<div class="slide" data-slide="4">
    <div class="slide-content">
        <div class="slide-label">CATEGORIA</div>
        <h2>Título do Slide</h2>
        <p>Descrição ou contexto para a tabela abaixo</p>
        <table class="data-table">
            <thead>
                <tr>
                    <th>Coluna 1</th>
                    <th>Coluna 2</th>
                    <th>Coluna 3</th>
                    <th>Impacto</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>Dado 1</td>
                    <td>Dado 2</td>
                    <td>Dado 3</td>
                    <td class="impact">Alto</td>
                </tr>
                <tr>
                    <td>Dado 4</td>
                    <td>Dado 5</td>
                    <td>Dado 6</td>
                    <td class="impact">Médio</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>
```

**Variante compacta (muitas linhas):**
```html
<table class="compact-table">
    <!-- Mesmo formato, mas fonte menor e padding reduzido -->
</table>
```

**Notas:**
- `.data-table` para tabelas normais (até ~8 linhas visíveis)
- `.compact-table` para tabelas densas (9+ linhas)
- `.impact` colore o texto em verde (accent-green)
- Headers são uppercase em cyan com background bg-tertiary

---

## 5. Conteúdo com Stats Grid (Métricas)

```html
<div class="slide" data-slide="5">
    <div class="slide-content">
        <div class="slide-label">MÉTRICAS</div>
        <h2>Indicadores-Chave</h2>
        <p>Resumo quantitativo dos principais números</p>
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-value">35+</div>
                <div class="stat-label">Participantes</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">9</div>
                <div class="stat-label">Sessões</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">19h</div>
                <div class="stat-label">Material Gravado</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">800+</div>
                <div class="stat-label">Horas Recuperáveis</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">2.3</div>
                <div class="stat-label">Maturidade Média</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">17</div>
                <div class="stat-label">Quick Wins</div>
            </div>
        </div>
    </div>
</div>
```

**Notas:**
- `.stats-grid` faz grid de 3 colunas
- `.stat-value` é o número grande em cyan-bright
- `.stat-label` é o rótulo pequeno uppercase
- Ideal para 3, 6 ou 9 métricas

---

## 6. Conteúdo com Diagrama Mermaid

```html
<div class="slide" data-slide="6">
    <div class="slide-content">
        <div class="slide-label">ARQUITETURA</div>
        <h2>Visão do Sistema</h2>
        <p>Diagrama de alto nível da arquitetura proposta</p>
        <div class="diagram-container">
            <div class="mermaid">
graph TB
    A["Entrada"] --> B["Processamento"]
    B --> C["Saida"]

    style A fill:#0d3b66,stroke:#4fc3f7,color:#e0e0e0
    style B fill:#0a3622,stroke:#66bb6a,color:#66bb6a
    style C fill:#1a0d3a,stroke:#ab47bc,color:#ab47bc
            </div>
        </div>
    </div>
</div>
```

**Notas:**
- `.diagram-container` centraliza e limita a altura (max 72vh)
- Use aspas duplas em labels Mermaid: `A["Texto"]`
- Aplique styles com a paleta dark (ver SKILL.md seção Mermaid)
- Em labels Mermaid, evitar acentos se causar erro de renderização
- SVG gerado é responsivo (max-width 100%)

---

## 7. Conteúdo com Citação (Quote Box)

```html
<div class="slide" data-slide="7">
    <div class="slide-content">
        <div class="slide-label">DESTAQUE</div>
        <h2>Título do Contexto</h2>
        <p>Texto explicativo antes da citação</p>
        <div class="quote-box">
            <p>"A citação relevante vai aqui, com aspas e em itálico. Deve comunicar um insight importante."</p>
            <div class="quote-author">— Nome do Autor, Cargo ou Contexto</div>
        </div>
    </div>
</div>
```

**Notas:**
- `.quote-box` tem border-left 4px cyan e fundo bg-secondary
- `.quote-box p` é itálico em cyan-light
- `.quote-author` é fonte menor em text-muted
- Ideal para depoimentos, insights de diagnóstico, frases de impacto

---

## 8. Conteúdo com SCR Cards (Situação / Complicação / Resolução)

```html
<div class="slide" data-slide="8">
    <div class="slide-content">
        <div class="slide-label">FRAMEWORK</div>
        <h2>Análise SCR</h2>
        <div class="scr-cards">
            <div class="scr-card situacao">
                <h3>Situação</h3>
                <p>Descrição da situação atual e contexto</p>
            </div>
            <div class="scr-card complicacao">
                <h3>Complicação</h3>
                <p>O que complica ou dificulta a situação</p>
            </div>
            <div class="scr-card resolucao">
                <h3>Resolução</h3>
                <p>Proposta de solução e caminho a seguir</p>
            </div>
        </div>
    </div>
</div>
```

**Notas:**
- 3 cards com border-left colorido (verde, laranja, cyan)
- Use para frameworks de análise 3-partes
- Pode adaptar os nomes (Ex: Problema/Causa/Solução)

---

## 9. Conteúdo com Tier Cards / Project Cards

```html
<div class="slide" data-slide="9">
    <div class="slide-content">
        <div class="slide-label">PORTFÓLIO</div>
        <h2>Projetos por Tier</h2>
        <p>Organização por nível de complexidade</p>
        <div class="tier-cards">
            <div class="tier-card">
                <h4>Projeto Alpha</h4>
                <p>Descrição breve do projeto e escopo</p>
                <div class="tier-impact">Impacto: 200h/mês economizadas</div>
            </div>
            <div class="tier-card">
                <h4>Projeto Beta</h4>
                <p>Outra descrição de projeto</p>
                <div class="tier-impact">Impacto: R$ 50k/ano</div>
            </div>
            <!-- Mais cards conforme necessário -->
        </div>
    </div>
</div>
```

**Notas:**
- `.tier-cards` usa grid auto-fit (mínimo 220px)
- `.tier-impact` mostra impacto em verde
- Flexível para qualquer número de cards

---

## 10. Conteúdo com Módulos (4 colunas)

```html
<div class="slide" data-slide="10">
    <div class="slide-content">
        <div class="slide-label">TREINAMENTO</div>
        <h2>Módulos do Programa</h2>
        <div class="module-cards">
            <div class="module-card">
                <h4>Módulo 1</h4>
                <div class="module-hours">4 horas</div>
                <p>Fundamentos e conceitos básicos</p>
            </div>
            <div class="module-card">
                <h4>Módulo 2</h4>
                <div class="module-hours">6 horas</div>
                <p>Aplicações práticas e exercícios</p>
            </div>
            <div class="module-card">
                <h4>Módulo 3</h4>
                <div class="module-hours">4 horas</div>
                <p>Técnicas avançadas</p>
            </div>
            <div class="module-card">
                <h4>Módulo 4</h4>
                <div class="module-hours">2 horas</div>
                <p>Projetos e avaliação</p>
            </div>
        </div>
    </div>
</div>
```

**Notas:**
- `.module-cards` grid de 4 colunas
- `.module-card` tem border-top 3px cyan
- `.module-hours` mostra duração em cyan bold
- Colapsa para 2 colunas em telas menores

---

## 11. Conteúdo com Duas Colunas

```html
<div class="slide" data-slide="11">
    <div class="slide-content">
        <div class="slide-label">COMPARAÇÃO</div>
        <h2>Antes vs. Depois</h2>
        <div class="two-col">
            <div>
                <h3>Situação Atual</h3>
                <p>Descrição do estado atual com detalhes relevantes para comparação.</p>
                <ul style="color: var(--text-secondary); margin-top: 12px; padding-left: 20px;">
                    <li>Ponto 1 da situação atual</li>
                    <li>Ponto 2 da situação atual</li>
                    <li>Ponto 3 da situação atual</li>
                </ul>
            </div>
            <div>
                <h3>Estado Proposto</h3>
                <p>Descrição do estado futuro desejado com os benefícios esperados.</p>
                <ul style="color: var(--text-secondary); margin-top: 12px; padding-left: 20px;">
                    <li style="color: var(--accent-green);">Melhoria 1</li>
                    <li style="color: var(--accent-green);">Melhoria 2</li>
                    <li style="color: var(--accent-green);">Melhoria 3</li>
                </ul>
            </div>
        </div>
    </div>
</div>
```

**Notas:**
- `.two-col` divide em 2 colunas iguais
- Gap de 40px entre colunas
- Colapsa para 1 coluna em mobile
- Útil para comparações, antes/depois, prós/contras

---

## 12. Conteúdo com Badges de Fase

```html
<div class="slide" data-slide="12">
    <div class="slide-content">
        <div class="slide-label">ROADMAP</div>
        <h2>Fases de Implementação</h2>
        <table class="data-table">
            <thead>
                <tr>
                    <th>Fase</th>
                    <th>Período</th>
                    <th>Foco</th>
                    <th>Status</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td><span class="phase-badge green">Fase 1</span></td>
                    <td>Meses 1-3</td>
                    <td>Fundação e nivelamento</td>
                    <td>Em planejamento</td>
                </tr>
                <tr>
                    <td><span class="phase-badge blue">Fase 2</span></td>
                    <td>Meses 3-6</td>
                    <td>Quick wins e validação</td>
                    <td>Planejado</td>
                </tr>
                <tr>
                    <td><span class="phase-badge purple">Fase 3</span></td>
                    <td>Meses 6-9</td>
                    <td>Escala e integrações</td>
                    <td>Futuro</td>
                </tr>
                <tr>
                    <td><span class="phase-badge orange">Fase 4</span></td>
                    <td>Meses 9-12</td>
                    <td>Transformação</td>
                    <td>Futuro</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>
```

**Notas:**
- `.phase-badge` é inline-block com border-radius
- Variantes: `.green`, `.blue`, `.purple`, `.orange`, `.red`
- Ideal para timelines, roadmaps, status de projetos

---

## 13. Conteúdo com Riscos (cores de severidade)

```html
<div class="slide" data-slide="13">
    <div class="slide-content">
        <div class="slide-label">GESTÃO DE RISCOS</div>
        <h2>Matriz de Riscos</h2>
        <table class="compact-table">
            <thead>
                <tr>
                    <th>Risco</th>
                    <th>Probabilidade</th>
                    <th>Impacto</th>
                    <th>Mitigação</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>Expectativas infladas</td>
                    <td class="risk-high">Alta</td>
                    <td class="risk-high">Alto</td>
                    <td>Comunicação transparente</td>
                </tr>
                <tr>
                    <td>Baixa adoção</td>
                    <td class="risk-med">Média</td>
                    <td class="risk-high">Alto</td>
                    <td>Quick wins visíveis</td>
                </tr>
                <tr>
                    <td>Evolução tecnológica</td>
                    <td class="risk-med">Média</td>
                    <td class="risk-low">Baixo</td>
                    <td>Revisão trimestral</td>
                </tr>
            </tbody>
        </table>
    </div>
</div>
```

**Notas:**
- `.risk-high` = vermelho, `.risk-med` = laranja, `.risk-low` = verde
- Use `.compact-table` para muitas linhas de risco
- Combine com `.data-table` para menos linhas

---

## 14. Closing Slide (Encerramento)

```html
<div class="slide title-slide" data-slide="14">
    <div class="slide-content">
        <div class="slide-label">ENCERRAMENTO</div>
        <h1>Obrigado!</h1>
        <div class="divider"></div>
        <p class="subtitle">Documento elaborado por Empresa para Cliente</p>
        <p style="color: var(--text-muted); font-size: 0.9rem; margin-top: 16px;">
            Versão 1.0 — Fevereiro de 2026
        </p>
    </div>
</div>
```

**Notas:**
- Reutiliza `.title-slide` para centralização
- Pode adicionar informações de contato
- Último slide, navegação finaliza aqui

---

## Combinações Frequentes

| Tipo de Apresentação | Slides Típicos |
|----------------------|----------------|
| **Plano Estratégico** | Capa → Agenda → Stats → SCR → Diagnóstico (tabela) → Treinamento (módulos) → Projetos (tiers) → Roadmap (badges) → Riscos → Próximos Passos → Closing |
| **Proposta Comercial** | Capa → Contexto (quote) → Escopo (2-col) → Metodologia (diagrama) → Investimento (stats) → Timeline (badges) → Closing |
| **Relatório de Projeto** | Capa → Agenda → Métricas (stats) → Resultados (tabela) → Análise (diagrama) → Próximos Passos → Closing |
| **Tech Report** | Capa → Arquitetura (diagrama) → Componentes (módulos) → Métricas (stats) → Riscos → Closing |
