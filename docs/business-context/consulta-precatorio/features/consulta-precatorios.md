# Feature: Consulta de Precatorios

## Resumo
Funcionalidade central do portal que permite ao usuario buscar informacoes sobre seu precatorio usando o numero do processo DEPRE ou numero dos autos originais, com resultado instantaneo a partir de base de ~200K registros.

## Fase
**Fase 1 - MVP**

## Prioridade
**P0 - Critica** (feature principal do produto)

---

## Descricao Funcional

### Fluxo do Usuario
1. Usuario acessa a pagina principal (landing page)
2. Visualiza campo de busca em destaque
3. Digita o numero do processo (DEPRE ou Autos)
4. Sistema busca na base de dados
5. Resultado exibido em segundos

### Campos de Busca Aceitos
| Campo | Formato Esperado | Exemplo |
|-------|-----------------|---------|
| Nº Processo DEPRE | NNNNNNN-NN.NNNN.8.26.0500 | 0122089-09.2025.8.26.0500 |
| Nº de Autos | NNNNNNN-NN.NNNN.8.26.NNNN | 0006248-79.2024.8.26.0506 |
| CPF (Fase 2) | NNN.NNN.NNN-NN | 123.456.789-00 |

### Resultado Exibido (Sem Cadastro)
| Dado | Exibido | Fonte |
|------|---------|-------|
| Nº Processo DEPRE | Sim | Base DEPRE |
| Devedora | Sim | Base DEPRE |
| Saldo DEPRE (R$) | Sim | Base DEPRE (sem atualizacao) |
| Status (Ativo/Suspenso) | Sim | Base DEPRE |
| Natureza (Alimentar/Outras) | Sim | Base DEPRE |
| Advogado(s) | Nao (requer cadastro) | Base DEPRE |
| Detalhes completos | Nao (requer cadastro) | Base DEPRE |

### Cenarios de Resultado
| Cenario | Acao do Sistema |
|---------|----------------|
| Processo encontrado com saldo | Exibir resumo + CTA para cadastro |
| Processo encontrado sem saldo | Exibir info + mensagem explicativa |
| Processo suspenso | Exibir alerta + explicacao |
| Processo nao encontrado | Mensagem amigavel + sugestoes |
| Formato invalido | Validacao inline + exemplo de formato |

---

## Requisitos Tecnicos

### Base de Dados
- Importar 199.767 registros da planilha DEPRE para Supabase
- Indexar por: Nº Processo DEPRE, Nº de Autos
- Saldo em centavos (campo numerico) → exibir como R$ X.XXX,XX
- Busca case-insensitive e tolerante a formatacao (com/sem pontuacao)

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
