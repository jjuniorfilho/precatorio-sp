# Brainstorm: Classificação de precatórios/RPV federais no caderno DJEN (TRF1-6)

**Data:** 2026-09-05
**Participantes:** José Oliveira Filho + Claude
**Issue relacionada:** FOR-145 (projeto Linear "Precatório Federal")

## Contexto

No refine da FOR-145 (captura do caderno DJEN completo dos TRF1-6), surgiram duas premissas técnicas em aberto antes de fechar os requisitos:

1. Como identificar que uma publicação do caderno é de precatório/RPV federal, já que — diferente do TJSP, onde o sufixo `.8.26.0500` do CNJ marca precatório — no federal o segmento do CNJ (`.4.01` TRF1, `.4.03` TRF3 etc.) indica só o tribunal/região, não o tipo de processo.
2. O usuário quer classificar as publicações em **conhecimento** vs **cumprimento de sentença** — nomenclatura que já existe no schema atual (tabela `processos` = raiz/conhecimento, tabela `cumprimentos` = execução/cumprimento de sentença, filha de `processos`), mas sem acesso à árvore de processo do sistema de origem (decidido no refine que o roteamento pro sistema — tipo PJe — fica fora de escopo desta entrega).

## Pesquisa realizada

- **Teste ao vivo da API Comunica** (`comunicaapi.pje.jus.br`, mesma API usada hoje pro TJSP): o payload já traz `codigoClasse`/`nomeClasse` por item (ex: `"codigoClasse":"436","nomeClasse":"PROCEDIMENTO DO JUIZADO ESPECIAL CÍVEL"`). Testado com TRF3, data 2026-09-01.
- **A API não filtra por classe no servidor** — passar `codigoClasse=1265` na query foi ignorado (retornou o mesmo resultado de uma chamada sem esse parâmetro). Filtro por classe só pode ser aplicado client-side (pós-fetch), igual ao mecanismo `classes_relevantes` que já existe em `ingest-djen.ts`.
- **Volume real:** só o TRF3, só no dia 2026-09-01, já ultrapassa 15.000 publicações (paginação testada até página 150 × 100 itens/página, ainda cheia). Mesma ordem de grandeza que levou o TJSP a filtrar por `nomeParte` no servidor (comentário no código: "caderno inteiro do TJSP é grande demais, >1500 págs/dia").
- **Tabela Processual Unificada do CNJ** (padronizada nacionalmente, diferente de nome de parte que varia por ente): classes **1265 = "Precatórios"** e **1266 = "Requisição de Pequeno Valor"** confirmadas via busca. "Cumprimento de Sentença contra a Fazenda Pública" também tem classe própria, mas o código exato divergiu entre fontes (viu-se referência a 12078 e a 12148 em contextos diferentes) — **não confirmado, precisa validação com amostra real**.
  - Fontes: [Portal CNJ — Tabelas Processuais Unificadas](https://www.cnj.jus.br/programas-e-acoes/tabela-processuais-unificadas/), [SGT Consulta Pública de Classes](https://www.cnj.jus.br/sgt/consulta_publica_classes.php)

## Alternativas Exploradas

### Alternativa A: Classificar só por classe processual (código CNJ)
- **Descrição:** Filtra/classifica client-side só pelo `codigoClasse` do payload (1265, 1266, faixa de cumprimento de sentença).
- **Vantagens:** Sinal estruturado e padronizado nacionalmente (não varia por ente/tribunal como nome de parte); reaproveita 100% o mecanismo `classes_relevantes` já existente; zero trabalho de curadoria de regex.
- **Desvantagens:** Se algum TRF usa classe local/diferente da tabela nacional, perde publicações silenciosamente; não captura nuances do teor (ex: valor, "ofício expedido") que hoje vêm de regras textuais.
- **Esforço:** Baixo
- **Impacto:** Alto
- **Riscos principais:** código de classe de "cumprimento de sentença" ainda não confirmado; possível divergência de classes locais por TRF.
- **Premissas:** classes 1265/1266 (e a de cumprimento) são usadas de forma consistente pelos 6 TRFs.

### Alternativa B: Classificar só por texto/teor (regex, igual `classificacao_regras` do estadual)
- **Descrição:** Replica o padrão hoje usado no estadual — regras ILIKE/regex sobre o texto da publicação.
- **Vantagens:** Mais tolerante a variação de formato entre tribunais; reaproveita a tabela `classificacao_regras` (editável sem deploy) tal como está.
- **Desvantagens:** Exige curadoria manual de padrões por conta própria (mesmo trabalho já feito pro estadual, agora duplicado pro federal); teor de intimação federal é mais variado (ex: "Ato Ordinatório" de prazo administrativo não tem nada a ver com precatório, mas usa linguagem processual comum).
- **Esforço:** Médio-Alto
- **Impacto:** Médio
- **Riscos principais:** curadoria incompleta gera falsos negativos/positivos; manutenção contínua de regras.

### Alternativa C: Híbrida — classe como sinal primário + regras de teor como refinamento (ESCOLHIDA)
- **Descrição:** `codigoClasse` decide o balde estrutural (conhecimento / cumprimento de sentença / precatório-RPV); regras de teor (reaproveitando `classificacao_regras`) refinam dentro do balde (ex: "ofício expedido", valor, credor) — mesmo desenho conceitual do pipeline estadual (macrofase via `classify_processo`), mas com um sinal de entrada mais confiável que texto puro.
- **Vantagens:** Reaproveita quase toda a infra já existente (schema `processos`/`cumprimentos`/`incidentes`, tabela `classificacao_regras`, lógica de `classify_processo`); menor risco de falso-negativo em massa que a Alternativa B sozinha; menos frágil a variação de teor que a Alternativa A sozinha.
- **Desvantagens:** Mais complexo que uma única fonte de sinal; ainda depende de confirmar os códigos de classe corretos.
- **Esforço:** Médio
- **Impacto:** Alto
- **Riscos principais:** mesmo risco de código de classe não confirmado da Alternativa A, mitigado pelo refinamento textual como camada de segurança.
- **Premissas:** classe CNJ é suficientemente confiável como sinal primário nos 6 TRFs; a camada de teor consegue ser adaptada com esforço incremental (não do zero).

## Análise de Trade-offs

| Critério | Alt A (só classe) | Alt B (só texto) | Alt C (híbrida) |
|----------|:---:|:---:|:---:|
| Reaproveitamento de infra existente | ⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Confiabilidade do sinal | ⭐⭐ | ⭐⭐ | ⭐⭐⭐ |
| Esforço de implementação | ⭐⭐⭐ (baixo esforço) | ⭐ (alto esforço) | ⭐⭐ (médio esforço) |
| Robustez a variação entre TRFs | ⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐ |

## Riscos (Alternativa C)

- **Técnicos:** código de classe de "cumprimento de sentença" não confirmado — precisa validar com amostra real de 1-2 TRFs antes de codar a regra definitiva.
- **Operacionais:** volume de fetch (15k+/dia só no TRF3) não é reduzido por essa decisão — continua sendo um custo de infraestrutura/paginação a absorver nos 6 TRFs, independente da estratégia de classificação escolhida.
- **Estratégicos:** nenhum — decisão é isolada ao pipeline de classificação, não afeta escopo de produto.

## Decisão/Recomendação

**Recomendação:** Alternativa C (híbrida) — **aprovada pelo usuário em 2026-09-05.**

**Justificativa:** melhor relação esforço/confiabilidade, reaproveita a arquitetura já validada no fluxo estadual (schema de árvore processos→cumprimentos→incidentes, tabela `classificacao_regras`), e usa um sinal estrutural (classe CNJ) que é mais estável entre tribunais do que texto livre.

**Premissas-chave desta decisão:**
1. Classes CNJ 1265 (Precatório) e 1266 (RPV) são usadas de forma consistente pelos 6 TRFs.
2. O código de classe de "cumprimento de sentença" ainda precisa ser confirmado com dados reais antes da implementação.
3. O volume de fetch por TRF (15k+/dia no TRF3) é um custo aceito, não mitigado por esta decisão de classificação.

**Próximos Passos:**
- [ ] Validar os códigos de classe reais (precatório, RPV, cumprimento de sentença) amostrando o caderno de 1-2 TRFs antes de codar a regra de classificação definitiva.
- [ ] Retomar o `/product:refine` da FOR-145 incorporando esta decisão.

## Pendências/Questões em Aberto

- Confirmar código(s) de classe de "cumprimento de sentença" (e possíveis variações provisório/definitivo) com amostra real — Responsável: a definir na fase de implementação.
- Confirmar se as classes 1265/1266 realmente aparecem de forma consistente nos 6 TRFs, ou se algum tribunal usa código local divergente.

## Aprendizados

- Nome de parte (usado hoje pro TJSP) não é um sinal padronizado nacionalmente; classe processual do CNJ é — isso é uma vantagem estrutural real do federal sobre o padrão estadual atual, não apenas uma alternativa equivalente.
- Filtrar por classe reduz custo de classificação/persistência, mas **não** reduz o custo de paginação/fetch do caderno — são dois problemas distintos que podem ser confundidos.
- Vale testar APIs ao vivo (mesmo que informalmente, via curl) antes de comprometer uma decisão de arquitetura em cima de suposição — a suposição inicial de "sem filtro = aceitar volume maior" só ficou concreta depois de medir o volume real.
