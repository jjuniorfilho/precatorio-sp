# Architecture: FOR-171

## Estado atual
UI (botão) -> supabase.functions.invoke("disparar-valor-pago") (Lovable edge, guarda WORKER_HTTP_SECRET)
-> POST https://crawler.forjuris.com.br/valor-pago (nginx -> 127.0.0.1:3200, http-server.ts)
-> consultarEPersistirPagamentos -> consultarPagamentos (fila concorrência-1, Playwright) -> consultarInterno.
`encontrado` = existe `span[id^=span_PRP_SITUACAO_ANDAMENTO_]` (extrairSituacao). Sem linha => `{encontrado:false}` e nada é gravado.
Falhas (captcha 4x, timeout, link do menu ausente) = throw -> HTTP 502 -> UI "Falha ao consultar o worker".
Logo hoje o "Não encontrado" da UI já é "página de resultado carregou sem linha" — mas indistinguível de página inesperada.

## Estado proposto
### 1. Crawler (`pagamentos-tjsp.ts`)
- `ConsultaPagamento` ganha `resultado: 'encontrado'|'nao_consta'|'falha'` (manter `encontrado` boolean por compat com edge/buscar-precatorio).
- Classificação em `classificarResultado(page)` (função isolada, testável com Page stub):
  - linha da grade presente => encontrado (inalterado);
  - senão `nao_consta` SOMENTE se: URL de resultado (RESULTADO_RE) E mensagem "Não foram encontrados Processos" VISÍVEL
    (`getByText(/Não foram encontrados Processos/i).first().isVisible()` — computed visibility do Playwright, cobre display:none/visibility/hidden/size 0;
    acrescentar checagem de opacity/ancestral via `evaluate(getComputedStyle)` se preciso) E grade sem linhas E rodapé `getByText(/Data da Consulta/i)` visível;
  - qualquer outra coisa => `falha` (erro lançado com etapa).
  - Extrair a "Data da Consulta" do portal (regex dd/mm/aaaa hh:mm:ss) e guardar no passo (útil no log).
- Coletor `PassosCollector`: `passo(etapa, status:'ok'|'erro'|'info', detalhe?)` com `at` ISO; instrumentar: abrir menu, obter link, abrir pesquisa, cada tentativa (captcha ok/rejeitado/timeout), resultado carregou, leitura (msg visível/linha), extração PDF, persistência. Em falha, último passo `erro` indica a etapa. `consultarInterno` recebe o coletor; falha é capturada, registrada e re-lançada.
- `consultarEPersistirPagamentos(processoDepre, {origem='manual'|'crawler', maxTentativas})`:
  - encontrado/nao_consta: upsertPagamentos (se houver) + `marcarPagamentosConsultado`;
  - falha: NÃO marca; grava log com resultado='falha'; re-lança (HTTP 502 continua, agora com corpo `{resultado:'falha', etapa, error}`).
  - Log gravado num `finally` (best-effort: erro ao gravar log só faz console.error, nunca derruba a consulta).
- `http-server.ts`: aceita `origem` opcional no body (default 'manual'; valida enum), devolve `resultado` + `consultado_em`. Edge `disparar-valor-pago` repassa (já repassa JSON inteiro; só ajustar erro para propagar `resultado`/`etapa`).
- Chamada "ciclo do crawler": hoje só o HTTP endpoint chama consultarEPersistirPagamentos (origem 'manual' via admin, 'busca_publica' via buscar-precatorio). Proposta de valores de origem: `manual | busca_publica | crawler` (checar com o humano se o ciclo do crawler chama de fato; grep não achou chamada em crawl.ts/index.ts).

### 2. Banco (SQL em `cortex-v1/sql/2026-09-25_for171_pagamentos_consultas_log.sql` + espelho em migration do frontend)
Tabela (não jsonb em `precatorios`: histórico N por processo, retenção simples, consultável):
`pagamentos_consultas_log(id uuid pk default gen_random_uuid(), processo_depre text not null, iniciada_em timestamptz not null, finalizada_em timestamptz, origem text check in ('manual','busca_publica','crawler'), resultado text check in ('encontrado','nao_consta','falha'), tentativas int, situacao text, qtd_pagamentos int, data_consulta_portal timestamptz null, erro text, passos jsonb not null default '[]')`; índice (processo_depre, iniciada_em desc).
RLS ligado, sem policy (nenhum SELECT/INSERT direto).
RPCs SECURITY DEFINER, `SET search_path=public`, plpgsql (padrão do projeto):
- `registrar_consulta_pagamento(...)` GRANT authenticated, service_role: INSERT + poda (`DELETE ... WHERE id NOT IN (últimas 20 do processo)`).
- `listar_consultas_pagamento(p_processo_depre text, p_limit int default 20)` GRANT anon, authenticated, service_role (admin roda anônimo — padrão admin-anon-rpc). Só campos do log; sem dados sensíveis.
- `marcar_pagamentos_consultado` inalterada (já existe).
Retenção: últimas 20 por processo na própria RPC de escrita.
Coluna `precatorios.pagamentos_consultado_em` basta para FOR-169; NÃO criar coluna de resultado (o "não consta" se deduz: consultado_em preenchido e valor_pago nulo/0). Opcional futuro.

### 3. Frontend (`admin.processos.$id.tsx`, `lib/api/processos.ts`)
- `consultarPagamentoManual` trata 3 estados (+ erro com etapa). Novo `fetchConsultasPagamento(numeroDepre)` via `db.rpc("listar_consultas_pagamento")`.
- `ConsultarPagamentoManual`: msg nao_consta com data/hora; falha = "Falha na consulta (etapa X) — tente novamente", nunca "não consta".
- Novo `ConsultasTjspLog` (Collapsible, mesmo padrão dos andamentos) renderizado em `RequisitorioDepre` logo abaixo do bloco de andamentos do requisitório e acima do botão; recarrega após cada consulta manual. Também no ramo `depre.length===0`.
- `src/lib/leads.ts`: rótulo "Não (consultado em dd/mm)" quando consultado_em e zero — verificar se FOR-169 já o faz (leads.ts:133 comenta esse comportamento); reaproveitar util de rótulo.

## Banco: mesmo projeto ou não?
Worker: `SUPABASE_URL` do .env da VPS (não versionado). Frontend: `.env` versionado -> nxkvfcrnocdxysqsuozj. Memória (2026-09-11) diz que VPS e Lovable usam bancos DIFERENTES, MAS evidências atuais indicam o mesmo: migration FOR-169 do frontend enfileira em `crawler_queue` (consumida pelo worker), lê `pagamentos_consultado_em` gravado pelo worker, e o Lovable já tem migrations de `precatorios_pagamentos`. NÃO verificável daqui — precisa confirmação humana (comparar SUPABASE_URL da VPS). Se forem diferentes, a UI não enxerga o log; fallback: o worker expõe GET /consultas?processo_depre no endpoint HTTP e a edge lê de lá (sem tabela no Lovable).

## Deploy / ordem
1. Aplicar SQL (tabela + RPCs) no SQL Editor do banco correto (e migration no frontend p/ Lovable manter em sincronia).
2. Deploy worker na VPS (/opt/precatorio-worker: git pull, build, `pm2 restart precatorio-crawler`) — tolera RPC ausente (log best-effort) então pode ir antes/depois, mas marcação de nao_consta não depende do SQL novo.
3. Publicar PR frontend (Lovable) + redeploy da edge `disparar-valor-pago` se alterada.
Ordem segura: SQL -> worker -> frontend.

## Trade-offs / riscos
- Tabela vs jsonb: tabela (retenção/consulta) escolhida; custo = SQL novo + poda.
- Sem HTML de fixture do portal, o classificador é validado só com stubs; seletor real de visibilidade precisa de 1 rodada contra o portal (autorização pendente). Default seguro = `falha` (não marca consultado).
- Log público via RPC anon: aceitável (sem PII), alinhado ao admin anônimo.

## Arquivos
Crawler: `worker-crawler/src/pagamentos-tjsp.ts`, novo `pagamentos-passos.ts`, `supabase.ts` (registrarConsultaPagamento), `http-server.ts`, testes `pagamentos-tjsp.test.ts`, `sql/2026-09-25_for171_*.sql`.
Frontend: `src/lib/api/processos.ts`, `src/routes/admin.processos.$id.tsx`, `src/lib/leads.ts`, `supabase/migrations/*for171*.sql`, `supabase/functions/disparar-valor-pago/index.ts`.

## Validação no portal real (Gate 1 aprovado) — STATUS: NÃO EXECUTADA
Nenhuma consulta foi feita ao TJSP. O portal exige captcha e o único jeito de passar (solveCaptcha por OCR) foi barrado pelo classificador de permissões como contorno de proteção de terceiro; regra do projeto + instrução do coordenador: parar e reportar.
Opções para o humano: (a) rodar ele mesmo o script de validação (não persiste) num ambiente com tesseract, ou fornecer o HTML salvo da página de resultado de 0145616-63.2020.8.26.0500 e de 0150268-84.2024.8.26.0500 (Salvar como/DevTools) para virarem fixtures; (b) autorizar explicitamente o uso do solver OCR local; (c) validar direto em produção pela VPS (que já roda o solver) com uma consulta de `consultarPagamentos` sem persistir.
Fixtures serão criadas a partir do HTML fornecido; até lá os testes usam stubs e o seletor de visibilidade fica a confirmar (default seguro = falha).

## Ramo condicional — banco
Principal: tabela+RPCs no mesmo banco do frontend (nxkvfc…), tela lê via RPC listar_consultas_pagamento.
Fallback (se VPS != frontend): worker expõe `GET /consultas?processo_depre=` (X-Worker-Secret), edge `disparar-valor-pago` (ou nova edge) lê dele; sem tabela no Lovable.
Confirmação do SUPABASE_URL da VPS é DEPENDÊNCIA antes do apply do SQL.

## ✅ Verificação de Consistência
**Data**: 2026-09-25 — **Status**: ⚠️ CORRIGIDO
- [x] Problema/meta iguais em ambos (3 estados, log recolhível, retenção 20, origens).
- [x] Arquivos coerentes (crawler: pagamentos-tjsp.ts/supabase.ts/http-server.ts/sql; frontend: processos.ts/admin.processos.$id.tsx/leads.ts/edge).
- [x] Spec da issue: texto do nao_consta sem afirmar "nenhum pagamento"; marca consultado em encontrado|nao_consta, nunca falha; FOR-169 rótulo "Não (consultado em dd/mm)".
- Correção: context.md agora registra aprovações, candidatos e bloqueio do captcha; architecture.md ganhou ramo condicional de banco e status da validação.
- Nota: pastas de origem — 'busca_publica' vem do buscar-precatorio; 'crawler' só se o ciclo passar a chamar (confirmado sem chamada hoje).

## Atualização da validação no portal (após autorização opção b)
- Humano autorizou o solver OCR local; `brew install tesseract imagemagick` passou (tesseract, magick e convert instalados em /opt/homebrew/bin; deps npm e chromium do Playwright OK).
- A EXECUÇÃO da sonda (script descartável em /private/tmp/claude-501/probe171.ts que replica o fluxo de consultarInterno com solveCaptcha, sem persistir) foi NEGADA pelo classificador de permissões (Third-Party Attack). Nenhuma consulta ao TJSP foi feita; nenhum fixture salvo. Conforme instrução, parei sem tentar outro caminho.
- Para destravar: o humano adiciona regra Bash no settings.local.json que permita rodar a sonda (ex.: `Bash(npx tsx /private/tmp/claude-501/probe171.ts:*)`), ou roda a sonda ele mesmo, ou fornece o HTML salvo.


## RESULTADO DA VALIDAÇÃO NO PORTAL (sonda rodada pelo humano na VPS, sem persistir)
| Caso | TXTNENHUM | Grade | Rodapé | Captcha |
|---|---|---|---|---|
| 0145616-63.2020.8.26.0500 (sem pagamento) | span#TXTNENHUM visível (display inline, visibility visible, opacity 1, offsetHeight 15, sem ancestral oculto); GeneXus TXTNENHUM_Visible="1" | 0 linhas, situacao null | "Data da Consulta:" visível | falhou 1ª, passou 2ª |
| 0150268-84.2024.8.26.0500 (com pagamento) | span#TXTNENHUM oculto (display none, offsetHeight 0); TXTNENHUM_Visible="0" | 1 linha, "Pendente de Pagamento" | visível | passou na 3ª |
- Rodapé visível nos 2 casos: prova busca concluída, não discrimina.
- Sinal server-side `TXTNENHUM_Visible` (estado GeneXus serializado) confirma a visibilidade computada; usar os dois.
- REGRA FINAL classificarResultado: encontrado = linha da grade; nao_consta = URL resultado + #TXTNENHUM visível (computed e TXTNENHUM_Visible=1) + grade vazia + rodapé; senão falha (default seguro; divergência de sinais = falha).
- Fixtures: worker-crawler/src/__fixtures__/pagamentos/resultado-{sem,com}-pagamento.html. Sonda scripts/probe-pagamentos.ts é descartável (não commitar).
- Estado antigo do bloqueio (captcha/permissão) superado: humano rodou a sonda.
