# Context: Crawler para Valor Pago (FOR-102)

## ⚠️ Regras Críticas do Projeto (Project Briefing)

> Nota: `project-briefing.md`/`backend-conventions.md` são de 2026-05-31 (pré-FOR-68) e estão
> desatualizados quanto ao estado do schema (hoje há schema novo `processos/incidentes/partes/andamentos`
> + fila `crawler_queue`, não só `precatorios`). As regras abaixo continuam válidas; a modelagem
> real segue o padrão mais recente (RLS `admin_all_{tabela}`, RPCs `SECURITY DEFINER`, migrations
> em `supabase/migrations/`, consolidadas no PR #10).

- **NUNCA** expor CPF/CNPJ completo — sempre mascarado.
- **SEMPRE** usar RLS no Supabase; tabelas de dados sensíveis (leads etc.) são admin-only.
- Tabela `precatorios` (schema legado DEPRE) é pública para leitura; escrita só via `service_role`.
- **Busca tolerante a formato**: normalizar `numero_depre`/CNJ (só dígitos) antes de comparar.
- **Valores monetários sempre em centavos (BIGINT)**, nunca `float`. Exibir com `Intl.NumberFormat('pt-BR')`.
- Performance: busca pública hoje é rápida (índices); este projeto **introduz uma exceção deliberada**
  a essa regra (ver abaixo — disparo síncrono pode levar segundos).

## 📚 Referências Relevantes

- `docs/technical-context/briefing/backend-conventions.md` — convenções de nomenclatura (snake_case,
  `idx_{tabela}_{coluna}`, políticas `admin_all_{tabela}`).
- Padrão mais atual (pós-FOR-68, PR #10 consolidado): migrations em `supabase/migrations/`,
  RPCs `SECURITY DEFINER` com `GRANT EXECUTE` explícito, fila `crawler_queue`/`coleta_config`/`coleta_runs`
  como modelo de orquestração de coleta.
- Issue Linear: [FOR-102](https://linear.app/forjuris/issue/FOR-102/crawler-para-valor-pago-via-portal-tjsp-busca-manual-admin-e)

## Contexto Específico da Feature

### Motivação (por quê)

- `precatorios.valor_pago` existe no schema mas não tem pipeline que o alimente — os valores atuais
  vieram de import manual da carga inicial (planilha do MVP), sem atualização.
- O usuário final do site (busca pública) precisa receber informação completa do processo, incluindo
  se já há valor pago — hoje essa informação não é buscada em tempo real.
- O admin precisa poder disparar/atualizar essa consulta seletivamente pela tela `/admin/processos`.
- Ausência de pagamento é um resultado **válido**, não erro — precisa se diferenciar de "nunca consultado".

### Meta (resultado esperado)

Um crawler novo (rodando na VPS, mesma infra do `worker-crawler` atual) que consulta o portal oficial
do TJSP (`pesquisainternetnumanoep.aspx`/`pesquisainternetv2.aspx`, fluxo "Pagamentos Prioridades") pelo
número DEPRE `.0500`, resolve o captcha (texto simples, tentativa via OCR leve antes de 2captcha pago),
navega em 2 passos (busca → detalhe) e persiste a lista de pagamentos encontrados (data, valor, tipo)
numa nova tabela vinculada por `processo_depre`.

Dois pontos de disparo, entregues juntos na mesma feature:
1. **Manual** — admin seleciona processos em `/admin/processos` e dispara sob demanda.
2. **Automático/síncrono** — toda busca pública nova de um processo `.0500` dispara a consulta ao vivo;
   a resposta da busca só volta depois do resultado (ou da confirmação de ausência de pagamento).

> **Correção (pós-investigação em architecture.md):** não existe hoje nenhum padrão de seleção em
> lote no admin (a tela `admin.consulta-oab.tsx` só tem um botão que enfileira **todos** os resultados
> de uma busca, sem checkbox por linha). O checkbox multi-select em `admin.processos.tsx` é um
> **padrão de UI novo** para este projeto, não uma reaplicação de algo existente.

### Estratégia (direcional, sem detalhes de implementação)

- Novo servidor HTTP leve **dentro do `worker-crawler`** (mesmo repo/processo já rodando na VPS) expõe
  um endpoint que a edge function `buscar-precatorio` chama de forma síncrona.
- Nova tabela relacionada (pagamentos são uma lista, não um valor escalar) vinculada só por
  `processo_depre` — funciona tanto para o schema legado (`precatorios`) quanto para o novo
  (`incidentes.numero_depre`), sem exigir FK para `incidente_id`.
- Campo de controle (timestamp) para registrar que a consulta foi feita, mesmo sem pagamentos encontrados.
- Captcha: tentar OCR leve (Tesseract ou equivalente) primeiro; 2captcha como fallback pago, não como
  dependência obrigatória de dia 1.
- Entrega única (manual + automático juntos), não faseada em duas entregas separadas.

### APIs/Ferramentas novas envolvidas

- Navegação do portal TJSP (`pesquisainternetnumanoep.aspx`) — HTTP puro ou headless browser, a definir
  na arquitetura conforme o comportamento real da sessão/captcha (só testável rodando da VPS — este
  sandbox de desenvolvimento toma 403 de rede, IP fora do Brasil, mesmo padrão já resolvido no FOR-70).
- OCR leve (candidato: Tesseract) para o captcha — nova dependência a avaliar.
- Servidor HTTP no worker-crawler (hoje é só um loop de polling, sem endpoint HTTP exposto) — nova
  capacidade a adicionar nesse serviço.

### Validação

- Rodar contra processos reais conhecidos (ex.: `0150268-84.2024.8.26.0500`, usado nos prints da
  investigação) e confirmar que a lista de pagamentos bate com o PDF de exemplo fornecido pelo usuário.
- Confirmar que processos sem pagamento gravam o campo de controle (consultado) sem erro.
- Testar o disparo síncrono da busca pública com um processo real e medir a latência adicionada.
- Confirmar que o disparo manual em lote no admin funciona para múltiplos processos selecionados.

### Dependências

- Worker-crawler existente (FOR-71/FOR-70, já consolidado no PR #10) — mesma infra/deploy na VPS.
- Tabela `precatorios` (schema legado) e `incidentes.numero_depre` (schema novo) como origem da chave
  de busca `processo_depre`/`numero_depre` (`.0500`).
- Edge function `buscar-precatorio` — precisa ser estendida para fazer a chamada síncrona ao worker.
- Tela `/admin/processos` (frontend) — precisa de UI de seleção múltipla + disparo (padrão já usado
  em outras telas do admin, ex. consulta OAB).

### Limitações e riscos conhecidos

- **~~Bloqueio de IP~~ CORRIGIDO (ver plan.md Fase 1)**: não é bloqueio geográfico/IP — testado ao
  vivo da VPS também e o mesmo 403 aparece sem o token de sessão correto. A causa real é a falta de
  um token assinado obtido em `webmenupesquisa.aspx`. Fluxo completo mapeado no `plan.md`.
- **Escopo corrigido**: "Pagamentos Prioridades" (`pesquisainternetpagamentov2.aspx`) é uma tela
  diferente (busca por CPF do credor, só pra preferência de idoso/doença grave) — **não é o que
  usamos**. O alvo certo é "Pagamentos Precatórios" dentro de `pesquisainternetv2.aspx`, buscável por
  `processo_depre`/EP-Ano, que é exatamente o fluxo que os prints e o PDF do usuário demonstraram.
- **Captcha pode não precisar de OCR**: validação 100% client-side com resposta em hash MD5 exposto
  em JS público — ver detalhes em `plan.md` Fase 1. OCR vira fallback, não caminho principal.
- **Captcha por sessão (hipótese não confirmada)**: prints do fluxo busca→detalhe não mostraram
  captcha repetido — se confirmado, resolve-se uma vez por sessão/lote, não por processo.
- **Sem TTL/cache**: como o disparo público é síncrono e por evento (sem cron), buscas repetidas do
  mesmo processo por usuários diferentes podem gerar múltiplas consultas reais ao portal — risco de
  custo (se cair no fallback 2captcha) e de rate-limit/bloqueio do TJSP.
- **Latência da busca pública**: disparo síncrono pode adicionar segundos à resposta da busca —
  aceito deliberadamente pelo usuário, mas é uma exceção à regra de performance de "< 2 segundos"
  do `critical-rules.md`.
- Mapeamento exato de parâmetros/URLs do portal ainda depende de acesso real (só validável da VPS).

## Decisões já fechadas nesta sessão

1. Endpoint síncrono roda **dentro do worker-crawler** (não é serviço novo separado).
2. Tabela de pagamentos vincula **só por `processo_depre`** (sem FK a `incidente_id`).
3. Entrega **manual + automático juntos**, não faseada em duas entregas.
4. Branch: `jjuniorfilho/for-102-valor-pago-crawler` (criado a partir de `main`).
