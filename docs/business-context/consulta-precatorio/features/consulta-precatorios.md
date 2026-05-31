# Feature: Consulta de Precatorios

## Resumo
Funcionalidade central do portal que permite ao usuario buscar informacoes sobre seu precatorio usando o numero do processo DEPRE, numero dos autos originais, CPF ou CNPJ do titular, com resultado instantaneo a partir de base de ~200K registros.

## Fase
**Fase 1 - MVP**

## Prioridade
**P0 - Critica** (feature principal do produto)

---

## Descricao Funcional

### Fluxo do Usuario
1. Usuario acessa a pagina principal (landing page)
2. Visualiza campo de busca em destaque
3. Digita o numero do processo (DEPRE ou Autos), CPF ou CNPJ
4. Sistema detecta automaticamente o tipo de input e busca na base de dados
5. Resultado exibido em segundos:
   - Busca por processo → resultado unico
   - Busca por CPF/CNPJ → lista de precatorios vinculados ao titular

### Campos de Busca Aceitos
| Campo | Formato Esperado | Exemplo | Tipo de Resultado |
|-------|-----------------|---------|-------------------|
| Nº Processo DEPRE | NNNNNNN-NN.NNNN.8.26.0500 | 0122089-09.2025.8.26.0500 | Unico |
| Nº de Autos | NNNNNNN-NN.NNNN.8.26.NNNN | 0006248-79.2024.8.26.0506 | Unico |
| CPF | NNN.NNN.NNN-NN | 123.456.789-00 | Lista (1 a N processos) |
| CNPJ | NN.NNN.NNN/NNNN-NN | 12.345.678/0001-90 | Lista (1 a N processos) |

### Deteccao automatica do tipo de input
O sistema detecta o tipo sem campo separado:
- 11 digitos numericos (apos remover mascara) → CPF
- 14 digitos numericos → CNPJ
- Padrao `NNNNNNN-NN.NNNN.8.26.0500` → Processo DEPRE
- Padrao `NNNNNNN-NN.NNNN.8.26.NNNN` → Nº de Autos

### Resultado Exibido — Busca por Processo (Sem Cadastro)
| Dado | Exibido | Fonte |
|------|---------|-------|
| Nº Processo DEPRE | Sim | Base DEPRE |
| Devedora | Sim | Base DEPRE |
| Saldo DEPRE (R$) | Sim | Base DEPRE (sem atualizacao) |
| Status (Ativo/Suspenso) | Sim | Base DEPRE |
| Natureza (Alimentar/Outras) | Sim | Base DEPRE |
| Advogado(s) | Nao (requer cadastro) | Base DEPRE |
| Detalhes completos | Nao (requer cadastro) | Base DEPRE |

### Resultado Exibido — Busca por CPF/CNPJ (Sem Cadastro)
- Lista de cards, um por processo encontrado
- Cada card exibe: Nº Processo DEPRE, Devedora, Saldo, Status, Natureza
- CPF/CNPJ pesquisado exibido parcialmente mascarado (privacidade)
- Soma total dos saldos exibida no topo da lista
- CTA unico para cadastro ao final da lista (nao por processo)

### Cenarios de Resultado
| Cenario | Acao do Sistema |
|---------|----------------|
| Processo encontrado com saldo | Exibir card unico + CTA para cadastro |
| Processo encontrado sem saldo | Exibir info + mensagem explicativa |
| Processo suspenso | Exibir alerta + explicacao |
| Processo nao encontrado | Mensagem amigavel + sugestoes |
| CPF/CNPJ com 1+ processos | Exibir lista de cards + soma total + CTA |
| CPF/CNPJ sem processos | Mensagem: nao encontramos precatorios para este CPF/CNPJ |
| Formato invalido | Validacao inline + exemplos de formatos aceitos |

---

## Requisitos Tecnicos

### Base de Dados
- Importar 199.767 registros da planilha DEPRE para Supabase
- Indexar por: Nº Processo DEPRE, Nº de Autos, CPF titular, CNPJ titular
- Saldo em centavos (campo numerico) → exibir como R$ X.XXX,XX
- Busca case-insensitive e tolerante a formatacao (com/sem pontuacao e mascara)

### Performance
- Tempo de resposta da busca: < 2 segundos
- Suportar buscas concorrentes sem degradacao
- Cache de resultados frequentes

### SEO
- Cada resultado pode gerar URL unica (para indexacao futura)
- Schema markup para rich snippets
- Meta tags dinamicas baseadas no resultado

---

## Metricas de Sucesso
| Metrica | Meta |
|---------|------|
| Buscas realizadas / visitantes | > 50% |
| Tempo medio ate resultado | < 3 segundos |
| Taxa de resultado encontrado | > 60% |
| Taxa de avanco para cadastro | > 40% (quando encontra resultado) |

---

## Consideracoes de UX
- Campo de busca deve ser o elemento mais visivel da pagina
- Placeholder com exemplo de formato aceito
- Botao de busca grande e claro
- Loading state durante a busca
- Resultado exibido na mesma pagina (sem redirect)
- Formatacao clara do valor monetario (R$ com separador de milhares)
- Destaque visual para saldo positivo vs sem saldo
