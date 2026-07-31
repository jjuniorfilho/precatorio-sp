# Crawler para Valor Pago (FOR-102)

Se você está trabalhando nesta feature, certifique-se de atualizar este arquivo plan.md conforme progride.

> Sequenciamento: FASE 1→5 são sequenciais (cada uma depende da anterior — schema, depois captcha,
> depois navegação, depois persistência, depois exposição HTTP). FASE 6 (busca pública) e FASE 7
> (admin manual) podem rodar **em paralelo** entre si assim que a FASE 5 estiver pronta, já que ambas
> só consomem o mesmo endpoint HTTP. FASE 8 depende de 6 e 7 estarem concluídas.

## FASE 0 — Preparação da sessão [Completada ✅]

### Branch de feature criado [Completada ✅]

`jjuniorfilho/for-102-valor-pago-crawler`, a partir de `main`.

### context.md e architecture.md [Completada ✅]

Entendimento e desenho arquitetural documentados e aprovados em `.claude/sessions/for-102-valor-pago-crawler/`.

### Comentários:
- Descoberto durante a arquitetura que o padrão de "seleção em lote" que eu supunha existir no admin
  (consulta OAB) não existe de fato — corrigido em ambos os documentos.
- Bloqueio de IP confirmado ao vivo (403 do sandbox) — todo teste real do crawler precisa rodar da VPS.

---

## FASE 1 — Schema + reconhecimento manual do portal [Completada ✅]

### Migration `precatorios_pagamentos` + `pagamentos_consultado_em` [Completada ✅]

Criada em `sql/2026-07-21_pagamentos_tjsp.sql` e **aplicada no SQL Editor (Lovable/Supabase) em
2026-07-21**:
- Tabela `precatorios_pagamentos` (`id`, `processo_depre`, `data_pagamento`, `valor` BIGINT centavos,
  `tipo` TEXT, `created_at`), índice `idx_precatorios_pagamentos_processo_depre` + índice único
  `(processo_depre, data_pagamento, valor, tipo)` pra idempotência.
- `ALTER TABLE precatorios ADD COLUMN pagamentos_consultado_em TIMESTAMPTZ`.
- RLS: leitura pública (`anon`), escrita só `service_role`.

### Reconhecimento manual do portal, rodando da VPS [Completada ✅]

Feito via SSH direto na VPS (`root@31.97.242.130`, mesma onde roda `precatorio-crawler` via pm2).

**⚠️ Hipótese do IP bloqueado estava ERRADA.** Testado ao vivo: `esaj.tjsp.jus.br` e
`www.tjsp.jus.br/` respondem 200 normalmente da VPS (e do sandbox de dev também, aliás — só esse
endpoint específico bloqueia). `www.tjsp.jus.br/cac/scp/pesquisainternetv2.aspx` direto (sem sessão)
retorna 403 tanto do sandbox quanto da própria VPS — não é bloqueio geográfico/IP, é falta do token
de sessão (ver abaixo). Corrigido em `context.md`/`architecture.md`.

**Cadeia de navegação real descoberta:**
1. `GET /cac/scp/webmenupesquisa.aspx` (público, sem login, 200) → menu "PESQUISAS" com 3 opções,
   cada uma um `<a href>` com um **token assinado por sessão** (exceto uma):
   - `LBLPRECATORIOSV2_Link` → `pesquisainternetv2.aspx?<token>` ("Precatórios")
   - `LBLPAGAMENTOSV2_Link` → `pesquisainternetv2.aspx?<token>` ("Pagamentos Precatórios") — **é este que queremos**
   - `LBLPRIORIDADESV2_Link` → `pesquisainternetpagamentov2.aspx` (**sem token**, "Pagamentos Prioridades")
2. **Correção de escopo importante**: "Pagamentos Prioridades" (`pesquisainternetpagamentov2.aspx`,
   testado direto, 200, sem token) é uma tela **diferente e mais restrita** do que pensávamos — busca
   por **CPF/nome do credor** (não por processo_depre), específica pra pagamentos de preferência de
   idosos/doença grave. **Não é o que precisamos.** O fluxo que o usuário demonstrou nos prints/PDF
   (busca por EP/Ano → lista → detalhe com "Pagamentos do Processo") vem de **"Pagamentos
   Precatórios"** (`pesquisainternetv2.aspx?<token>`), que É buscável por `Processo DEPRE`/`EP-Ano`
   (campos `vPRP_PROCESSO`, `vPRP_NUM_ORDEM`/`vPRP_ANO_ORDEM`) — bate exatamente com o primeiro print
   da investigação (mesmos campos: Tipo de Pesquisa, Entidade, Nº EP/Ano, Processo DEPRE, etc.).
   `webmenupesquisa.aspx` retorna 200 com o token embutido no HTML — o worker só precisa dar `GET`
   nessa página primeiro pra capturar o link/token antes de acessar `pesquisainternetv2.aspx`.
3. **Captcha por sessão: confirmado.** A navegação busca→resultados (`pesquisainternetnumanoep.aspx`)
   não pediu novo captcha — mesma sessão (cookies) manteve validade.
4. **🔓 Achado grande — o captcha provavelmente é trivialmente contornável, sem OCR nem 2captcha:**
   - São **191 imagens estáticas fixas** (`Captcha/images/1.jpg` … `191.jpg`), escolhidas por
     `Math.random()` **no JavaScript do navegador** (`Captcha/CaptchaRender.js`).
   - A resposta correta de cada imagem é um **hash MD5 hardcoded num array JS público**
     (`Captcha/jcap.js`, variável `cword`, 191 hashes) — enviado a qualquer visitante, mesmo sem
     resolver nada.
   - A validação (`hex_md5(input) == cword[n]`) roda **inteiramente no navegador**; o resultado
     (0 ou 1) vira só um campo (`CAPTCHA1_Validationresult`) dentro do JSON `GXState` que é
     reenviado ao servidor no submit.
   - Como o número da imagem (`anum`) é sorteado **só no cliente**, o servidor não tem como saber
     qual imagem foi mostrada — ou seja, muito provavelmente **não há como o servidor validar de
     forma independente**, e um cliente HTTP puro (sem JS) pode simplesmente mandar
     `CAPTCHA1_Validationresult: 1` no POST, sem nunca precisar ler a imagem.
   - Imagem de exemplo baixada e conferida visualmente: texto limpo, baixo ruído (ex.: "polish") —
     confirma a impressão do usuário de que é um captcha simples. Serve como **fallback OCR** caso o
     bypass acima não funcione na prática.
   - **Testado ao vivo (com autorização explícita do usuário)**: montei um POST forjando
     `CAPTCHA1_Validationresult: "1"` direto no `GXState`, sem nunca ler a imagem, contra o form real
     (token de sessão válido) buscando `0150268-84.2024.8.26.0500`. **O servidor aceitou e ecoou o
     valor forjado de volta sem rejeitar** — forte sinal de que o bypass funciona (nenhum erro de
     captcha, nenhum reset do valor). Confirma a hipótese: `CAPTCHA1_Validationresult` não tem o
     `gxhash_*` de proteção que outros campos sensíveis têm (ex. `vBPAGAMENTO`), então não é
     validado server-side.
   - **Protocolo real capturado** (usuário fez uma busca de verdade com DevTools aberto e trouxe as
     4 chamadas `fetch()`, processo `0150268-84.2024.8.26.0500`, captcha real digitado = "story"):
     - É uma **sequência de 4 AJAX calls**, não uma só: 1 GET (`gxajaxrequest: 2`, inicialização) +
       3 POST (`gxajaxrequest: 1`), cada uma com `_EventName` diferente
       (`EVENT_ID.ISVALID.` → `ERFR.` → `E'PESQUISAR'.`), cada uma carregando o `GXState` que a
       chamada anterior devolveu (estado cresce a cada volta — campos como `GX_STYLE_FILES`,
       `AV8bPagamento`, `AV16HLP_PAGINA` só aparecem depois de 2-3 idas e vindas).
     - Headers **obrigatórios** que eu não tinha mandado antes: `ajax_security_token` (mesmo valor
       de `AJAX_SECURITY_TOKEN` do GXState, mas como **header HTTP**, não só no body) e
       `gxajaxrequest: 1`.
     - URL das chamadas POST não é só `?<token-da-página>` — é
       `?<nonce-32-hex>,<token-da-página>,gx-no-cache=<epoch-ms>` (o nonce parece gerado por
       chamada, mesmo valor nas 3 POSTs de uma mesma sequência).
     - `cfield` no fluxo real leva a palavra certa digitada pelo usuário — a captura **não prova
       nem desprova** o bypass (não foi um teste do bypass, foi um fluxo legítimo).
   - **2º teste do bypass (com autorização explícita), agora com headers/URL corretos**: montei uma
     sessão nova, peguei token+GXState frescos, e tentei pular direto pra `_EventName: "E'PESQUISAR'."`
     (as 3 chamadas em 1 só, `CAPTCHA1_Validationresult` forjado, `cfield` com lixo) — **resultado:
     HTTP 440** ("Login Time-out", erro específico de sessão/estado do IIS, não de captcha).
     **Conclusão**: o servidor mantém alguma validação de sequência/estado (não é simplesmente
     "aceita qualquer coisa"). Ainda não sabemos se ele *também* valida o captcha de verdade, ou só
     a sequência de eventos — pular etapas quebra por outro motivo antes de chegar nessa resposta.
   - **Decisão**: parar de testar o bypass às cegas por aqui. Duas opções pra Fase 3: (a) replicar a
     sequência completa de 4 chamadas (não pular nenhuma) e *então* testar se um `cfield`
     incorreto/vazio ainda passa — teste mais fiel, exige mais engenharia; (b) ir direto de OCR
     (mais simples, garantido de funcionar, só não é grátis em tentativas/tempo de CPU). Recomendo
     **(b) como caminho padrão pra Fase 2/3**, e revisitar o bypass como otimização depois, com mais
     tempo, replicando a sequência completa em vez de pular passos.

### Comentários:
- A Fase 2 do plano original (módulo de OCR) pode não ser necessária como caminho principal — vira
  fallback. Se o bypass do `ValidationResult` funcionar, o crawler nem precisa baixar a imagem do
  captcha.
- Ainda falta confirmar o formato exato do POST/AJAX do GeneXus (provavelmente `Content-Type`
  específico + corpo serializado, não um form POST comum) — melhor forma de descobrir é capturar
  tráfego de um browser real navegando o fluxo uma vez (DevTools → Network → copiar como cURL).

---

## FASE 2 — Módulo de captcha (OCR leve) [Completada ✅]

### `worker-crawler/src/captcha.ts` [Completada ✅]

Decidido: binário de sistema (`tesseract` + `convert`/ImageMagick via `child_process.execFile`),
não `tesseract.js`. Motivo: node instalado na VPS é **18.19.1** (o `pm2 describe
precatorio-crawler` confirmou — apesar do `package.json` declarar `engines: >=20`, é uma
inconsistência pré-existente, não mexi nisso agora) e o padrão do projeto já é depender de CLIs de
sistema (ex.: `pdftotext`/poppler no pipeline DEPRE) em vez de libs Node pesadas. Instalei na VPS:
`apt-get install tesseract-ocr tesseract-ocr-por tesseract-ocr-eng imagemagick` (não documentado
em nenhum script de provisionamento ainda — **pendência**: adicionar isso ao `worker-crawler/README.md`
ou a um script de setup, pra não perder esse passo se a VPS for recriada).

Pipeline: `convert` (grayscale → despeckle 2x → resize 600% → threshold 55%) → `tesseract --psm 8`
com whitelist `a-z` (os exemplos reais só têm palavras simples em inglês minúsculo: "story",
"polish", "wind", "idea", "butter", "fact", "after", "jewel"...).

### Testar contra as imagens reais [Completada ✅]

Baixei 10 imagens reais (`Captcha/images/{1,5,20,47,63,88,105,130,155,191}.jpg`) e validei
objetivamente contra a resposta certa — sem depender de eu "achar que li certo": o `Captcha/jcap.js`
expõe o MD5 da resposta de cada uma das 191 imagens (`cword[n-1]`), então bati
`md5(palpite_do_ocr) == cword[n-1]` pra saber com certeza se acertou.

**Resultado com o pipeline final (1 tentativa, sem escolher a dedo): 5/10 (50%).**

### Comentários:
- 50% numa tentativa é baixo isoladamente, mas o captcha é **de graça pra recarregar** ("Nova
  Imagem", sem custo/rate-limit conhecido) — a estratégia real não é "acertar de primeira", é
  **tentar, e se o servidor rejeitar, pedir uma imagem nova e tentar de novo**. Com ~50% por
  tentativa: 2 tentativas ≈ 75% de sucesso acumulado, 3 ≈ 87,5%. Essa lógica de retry fica pra
  Fase 3 (`pagamentos-tjsp.ts`), não faz parte do `captcha.ts` (que só resolve *uma* imagem).
  Também vale registrar quantas tentativas foram necessárias por consulta — útil pra decidir depois
  se compensa investir mais em pré-processamento ou simplesmente aceitar o custo de retry.
  **Nota**: ainda não confirmamos se o servidor de fato valida o `cfield` contra a imagem (ver
  Fase 1) — se ele *não* validar (hipótese do bypass), a taxa de acerto do OCR pode nem importar
  na prática. Mantendo os dois caminhos vivos: OCR real funciona, e o bypass fica como otimização
  a testar com calma durante a Fase 3.
- Falhas comuns do OCR: letras extras coladas por ruído residual (`polisheress` em vez de
  `polish`, `buckets` em vez do que quer que fosse a 191) — pré-processamento adicional
  (erosão morfológica, ou treinar um modelo customizado) poderia melhorar, mas não vale o esforço
  agora dado que o retry é praticamente grátis.

---

## FASE 3 — Navegação do portal (`pagamentos-tjsp.ts`) [Completada ✅]

### Tentativa HTTP puro (undici) [Abandonada — ver Playwright abaixo]

Primeira tentativa seguiu o estilo de `esaj.ts` (HTTP puro): replicar a sequência de eventos
AJAX do GeneXus (`EVENT_ID.ISVALID.` → `ERFR.` → `E'PESQUISAR'.`) via `undici`, com headers
`ajax_security_token`/`gxajaxrequest`, URL `?<nonce>,<token>,gx-no-cache=<ts>` etc. **Toda
chamada retornava HTTP 440 "Session timeout"**, mesmo com cookies/headers/URL conferindo com
captura real de navegador. Causa exata não isolada em tempo razoável — **decisão: trocar para
Playwright** só neste fluxo (ver `architecture.md`, seção de restrição de capacidade da VPS,
pra decisão de concorrência).

### Sessão + busca por `processo_depre` (Playwright) [Completada ✅]

`worker-crawler/src/pagamentos-tjsp.ts`: `webmenupesquisa.aspx` → token de "Pagamentos
Precatórios" → `pesquisainternetv2.aspx` → preenche `vPRP_PROCESSO` (tipo "Processo DEPRE") →
resolve captcha (`captcha.ts`) → clica "Pesquisar". Testado ao vivo contra
`0150268-84.2024.8.26.0500` (o mesmo do PDF de exemplo do usuário) — funciona.

**Duas corridas (race conditions) resolvidas, ambas pelo mesmo padrão** (esperar
`networkidle` + folga antes de agir):
1. Clicar "Pesquisar" antes da validação assíncrona do captcha (disparada no `blur` do campo)
   terminar faz a busca ser ignorada silenciosamente (reexibe o mesmo formulário).
2. Timeout curto demais no `waitForURL` do resultado fazia o código desistir e pedir um
   captcha novo **antes** da navegação anterior realmente completar — a navegação tardia
   deixava a próxima tentativa num formulário parcialmente desabilitado (trava em "aguardando
   elemento ficar visível/habilitado"). Aumentado o timeout pra 25s e adicionado
   `networkidle` também após o reload do captcha.

### Extração do status da grade [Completada ✅]

Campo `span[id^="span_PRP_SITUACAO_ANDAMENTO_"]` (ex. "Pendente de Pagamento") já vem na
própria grade de resultado, sem precisar clicar em mais nada.

**Achado**: a mensagem "Não foram encontrados Processos com estes filtros !!!" fica **sempre**
presente no HTML (só oculta via CSS), mesmo quando há resultado — não é sinal confiável de
"não encontrado". O sinal correto é a presença do próprio campo de status.

### Download e parse do PDF de pagamentos [Completada ✅]

**Descoberta principal da sessão**: clicar no ícone "Selecionar" (`input[type="image"]
name="vSELECIONAR_NNNN"`) da linha **não navega pra uma página de detalhe HTML** — abre uma
aba nova que o Chromium trata como **download** de um PDF gerado sob demanda
(`arelpesquisainternetprecatorio.aspx`), com a seção "Pagamentos do Processo" (Data | Valor R$
| Tipo). Confirmado pelo usuário navegando manualmente e me mostrando a sequência real.

Isso muda (de volta) o modelo de dados: a tabela `precatorios_pagamentos` da Fase 1 **estava
certa desde o início** — pagamentos individuais por `processo_depre` existem sim, só chegam via
PDF, não HTML. (Uma tentativa no meio do caminho de simplificar pra só "status" foi descartada
depois desta descoberta.)

**Duas armadilhas de implementação, ambas resolvidas:**
1. A aba do PDF não expõe uma URL utilizável via `page.url()` (fica presa em `":"`, mesmo
   depois de carregado) — não dá pra usar `page.request.get(novaPagina.url())`.
2. Como o Chromium trata como *download* (não navegação normal), ler o corpo via evento
   `response`/CDP falha com `"No resource with given identifier found"` — é preciso usar a
   API de download do Playwright (`page.on("download")` + `download.path()`, contexto criado
   com `acceptDownloads: true`), não tentar capturar via rede.

**Resultado do teste final** (mesmo processo do PDF do usuário): 3 pagamentos, mesmas datas
(28/07/2025), mesmos valores (R$ 77.791,89 / R$ 3.123,89 / R$ 567,97) e tipo "Preferência" —
bateu exatamente.

`pdftotext` (poppler, já usado no pipeline DEPRE — `bin/extract_depre.py`) extrai o texto do
PDF; `parsePagamentosPdf` faz o parse da seção de pagamentos por regex.

### Comentários:
- Toda a exploração foi feita numa VPS de teste isolada (`/root/test-playwright`, fora do
  diretório de produção `/opt/precatorio-worker`) — nada tocou o worker em produção.
- `tesseract-ocr`, `imagemagick` e `poppler-utils` (`pdftotext`) precisam estar instalados na
  VPS de produção antes do deploy — nenhum script de provisionamento documenta isso ainda
  (mesma pendência já registrada na Fase 2).
- O teste do bypass do captcha (Fase 1) ficou definitivamente irrelevante — com Playwright +
  OCR real funcionando de ponta a ponta, não há mais motivo pra revisitar isso.

### Parse do resultado + navegação pro detalhe [Não Iniciada ⏳]

Parsear a lista de resultados (EP/Ano, Processo DEPRE, Entidade Devedora) e seguir o link/postback
do ícone de detalhe.

### Parse da tabela "Pagamentos do Processo" [Não Iniciada ⏳]

Extrair `{data, valor, tipo}` de cada linha da tabela de pagamentos (pode ser vazia — resultado válido).

### Teste end-to-end com processo real [Não Iniciada ⏳]

Validar contra `0150268-84.2024.8.26.0500` (exemplo já confirmado com 3 pagamentos de Preferência)
e contra ao menos um processo sem nenhum pagamento.

### Comentários:
-

---

## FASE 4 — Persistência (`supabase.ts`) [Completada ✅]

### `upsertPagamentos(processoDepre, pagamentos[])` [Completada ✅]

Upsert por chave composta `processo_depre+data_pagamento+valor+tipo` (índice único).
`tipo` vira `''` em vez de `NULL` (NULL não conflita com NULL num índice único do Postgres —
duas linhas com `tipo=NULL` não seriam consideradas duplicatas, quebrando a idempotência).

**Duas correções de schema/RLS descobertas só ao testar de verdade:**
1. O índice único da migration original (Fase 1) usava `COALESCE(tipo, '')` — uma
   **expressão**. O `.upsert(..., {onConflict})` do Supabase só aceita nomes de coluna
   simples, nunca batia com esse índice (`"no unique or exclusion constraint matching the
   ON CONFLICT specification"`). Corrigido tornando `tipo`/`data_pagamento` NOT NULL e
   trocando por um índice direto nas colunas
   (`sql/2026-07-22_fix_precatorios_pagamentos_index.sql`).
2. RLS só tinha policy de leitura — faltava permitir escrita pro worker (que autentica como
   `authenticated`, não `service_role` cru; ver "Opção B" em `config.ts`). Adicionado
   `admin_write_precatorios_pagamentos` (`sql/2026-07-22_fix_precatorios_pagamentos_rls_write.sql`).

### `markPagamentosConsultado(processoDepre)` [Completada ✅]

**Não é update direto na tabela** — `precatorios` só permite escrita via `service_role` (dado
público DEPRE, não deve abrir UPDATE geral pra `authenticated`). Implementado como RPC
`SECURITY DEFINER` (`sql/2026-07-22_marcar_pagamentos_consultado_rpc.sql`), mesmo padrão já
usado em `claim_crawler_jobs`/`classify_processo`.

### Teste de idempotência [Completada ✅]

Rodei a mesma consulta 2x contra o Supabase real (processo `0150268-84.2024.8.26.0500`) —
continuam só 3 linhas na segunda vez, sem duplicar.

### Comentários:
- **Achado bônus**: a soma dos 3 pagamentos que o crawler encontrou (R$ 81.483,75) bate
  **exatamente** com o `precatorios.valor_pago` legado que já estava na base (import manual
  da carga inicial do MVP). Valida cruzadamente que o crawler está extraindo certo, e sugere
  que `valor_pago` poderia futuramente virar um valor computado (soma de
  `precatorios_pagamentos`) em vez de dado estático — não fiz essa mudança agora, só registro
  a possibilidade.
- Toda a validação rodou numa cópia isolada na VPS (`/root/test-for102b`, fora de
  `/opt/precatorio-worker`), autenticando com as mesmas credenciais reais do worker
  (`ensureAuth()` — "Opção B", anon key + login admin) contra o Supabase de produção. Os
  dados gravados (pagamentos de um processo real) são dados reais, não de teste — ficam
  válidos pra uso.
- Lição pra próximas fases: sempre chamar `ensureAuth()` antes de testar qualquer persistência
  isoladamente — sem isso, as chamadas vão como `anon` (RLS bloqueia silenciosamente, sem erro
  óbvio até você checar o motivo certo).

---

## FASE 5 — Endpoint HTTP síncrono no worker [Completada ✅]

### `worker-crawler/src/http-server.ts` [Completada ✅]

`POST /valor-pago { processo_depre }` (Node `http` nativo, sem framework novo). Valida
`processo_depre` (precisa terminar em `.8.26.0500`), autentica via header `X-Worker-Secret`
(env `WORKER_HTTP_SECRET`), chama `consultarEPersistirPagamentos` (Fases 3+4) e devolve o
`ConsultaPagamento` completo (`encontrado`/`situacao`/`pagamentos`) como JSON.

**Escuta só em `127.0.0.1`** nesta fase — a exposição pública fica pra Fase 6 (quando o
`buscar-precatorio`, fora da VPS, precisar alcançá-lo de verdade pela internet; aí é o
momento certo de decidir nginx/HTTPS com o usuário, já que a VPS não tem TLS configurado em
nenhum serviço hoje).

### Subir o servidor junto ao loop existente [Completada ✅]

`index.ts` chama `startHttpServer()` logo após `ensureAuth()`, antes de entrar no loop de
`claim/crawl/persist` — os dois rodam no mesmo processo/event-loop do Node sem se atrapalhar
(o servidor HTTP é assíncrono/orientado a evento, não bloqueia o loop de polling).

### Teste via curl direto na VPS [Completada ✅]

Testado numa cópia isolada (`/root/test-http`, fora de `/opt/precatorio-worker`) via `curl`
local na própria VPS: 401 sem secret/com secret errado, 400 com `processo_depre` inválido,
404 em rota inexistente, e 200 com o resultado real e correto (mesmo processo das fases
anteriores — 3 pagamentos, valores batendo).

### Comentários:
- Achei um bug bobo no processo: esqueci de copiar o `config.ts` atualizado (com
  `HTTP_PORT`/`WORKER_HTTP_SECRET`) pro diretório de teste isolado na primeira tentativa —
  o servidor subiu escutando numa porta aleatória do SO em vez de 3200. Lição: ao criar um
  diretório de teste isolado, conferir que TODOS os arquivos alterados na sessão foram
  copiados, não só os que mudaram nesta fase específica.
- `WORKER_HTTP_SECRET` ainda não tem um valor real gerado — só um placeholder no
  `.env.example`. Gerar e configurar na VPS antes do deploy real.

---

## FASE 6 — Integração na busca pública [Em Progresso ⏰]

### Exposição pública do endpoint (HTTPS) [Completada ✅]

Decisão tomada com o usuário: subdomínio + Let's Encrypt (em vez de Cloudflare Tunnel ou
HTTP puro sem TLS). Domínio já existente do usuário (`forjuris.com.br`, Hostinger).

- DNS: registro A `crawler.forjuris.com.br` → `31.97.242.130` (criado pelo usuário no
  Hostinger, propagação confirmada via `dig`).
- `certbot` + `python3-certbot-nginx` instalados na VPS; certificado emitido via
  `certbot --nginx -d crawler.forjuris.com.br` (expira 2026-10-20, renovação automática já
  agendada pelo certbot).
- Novo site nginx (`/etc/nginx/sites-available/crawler-worker`, habilitado em
  `sites-enabled/`): proxy HTTPS → `127.0.0.1:3200` (onde o `http-server.ts` da Fase 5
  escuta). HTTP puro redireciona automaticamente pra HTTPS (configurado pelo certbot).
  Cópia de referência salva em `worker-crawler/infra/nginx-crawler-worker.conf` (o arquivo
  real vive só na VPS, em `/etc/nginx/sites-enabled/` — útil só se a VPS precisar ser
  reprovisionada).
- **`proxy_read_timeout` ajustado pra 300s** (default do nginx, 60s, dava 504 — a consulta
  real ao TJSP com retries de captcha pode passar de 60s).

**Testado de ponta a ponta via HTTPS externo** (da máquina local, não da VPS): 200 com
resultado real e correto, 401 sem secret, redirect 301 de HTTP pra HTTPS. Servidor de teste
rodou numa cópia isolada (`/root/test-https`), removida depois do teste.

**Atualização 2026-07-22 (verificado ao vivo)**: `http-server.ts` de produção **já está
rodando** — faz parte do mesmo processo pm2 `precatorio-crawler` em `/opt/precatorio-worker`
(`index.ts` chama `startHttpServer()` antes do loop de crawl, como planejado). Log confirma
`[http-server] ouvindo em 127.0.0.1:3200 (POST /valor-pago)`. `WORKER_HTTP_SECRET` real (64
chars) já está gerado e configurado no `.env` da VPS. Externamente, `https://crawler.forjuris.com.br/valor-pago`
responde 401 sem secret e 401 com secret errado — endpoint público protegido e no ar.

### `supabase/functions/buscar-precatorio/index.ts` [Código pronto, deploy no Lovable pendente ⏳]

Código implementado e commitado (`438f982`): quando um item tem `numero_depre` terminando em
`.0500`, chama `https://crawler.forjuris.com.br/valor-pago` de forma síncrona antes de montar
a resposta; incorpora `situacao_pagamento`/`pagamentos` no payload. Falha graciosamente
(timeout/erro não derruba a busca).

**Falta**: como as edge functions deste projeto deployam via Lovable AI (API interna, não
git — ver `project_lovable_integration` na memória), o usuário precisa (1) colar esse código
no editor de edge functions do Lovable (ou pedir ao Lovable AI via chat pra criar/atualizar
`buscar-precatorio` com ele) e (2) configurar `WORKER_HTTP_SECRET` em Cloud → Secrets do
Lovable com o mesmo valor que já está no `.env` da VPS.

### Teste end-to-end de busca real no site [Não Iniciada ⏳]

Validar a latência adicionada e o conteúdo da resposta com um processo real, após o deploy no
Lovable.

### Comentários:
- Endpoint interno (`http-server.ts`) e exposição pública (nginx/HTTPS) são preocupações
  separadas — o primeiro não sabe nada sobre domínio/certificado, só escuta em
  `127.0.0.1:3200`. Confirmado ao vivo em 2026-07-22 que os dois já estão de pé em produção;
  o único elo que falta na Fase 6 é o deploy da edge function no Lovable.

### Achado + extensão (2026-07-22): titular (nome/documento) nunca chegava no relatório [Código pronto, migration+deploy pendentes ⏳]

Usuário testou o fluxo de relatório por email (`enviar-relatorio`) com o processo real
`0150268-84.2024.8.26.0500` e "Titular do Precatório" saiu em branco (Nome e Documento). Causa
raiz investigada e confirmada (consulta direta via anon REST em `precatorios_publico`: `autor`
null pra esse processo):
- O único código que já preencheu `precatorios.autor`/`cpf_titular`/`cnpj_titular` era
  `search-by-document/index.ts` (scraping DOCPARTE no e-SAJ) — **órfão**: nenhuma tela chama
  mais essa function desde que `buscarPublico`/`buscar-precatorio` virou o fluxo único (CPF,
  CNPJ e processo). `buscar-precatorio` nunca lia nem gravava titular em lugar nenhum.
- Achado bônus: o crawler **já parseia** o nome do requerente (Reqte) toda vez que visita a
  ficha de um `.0500` (`extractPartes`/`parte_ativa.nome` em `parse.ts`, chamado por
  `crawlRequisitorio`) — confirmado pelo usuário com print real do e-SAJ (`Carlos Alberto
  Teixeira` como Reqte). Só que `persistRequisitorio` (supabase.ts) descartava esse nome —
  só gravava `devedora` (parte passiva) em `djen_depre`, nunca o titular.
- Documento (CPF/CNPJ) nunca aparece na ficha do e-SAJ — só existe se o próprio titular
  informar buscando por ele no site (aí sim é uma auto-declaração, tudo bem persistir).

**Implementado:**
1. `sql/2026-07-22_djen_depre_titular.sql` — `titular_nome`/`titular_documento` em
   `djen_depre`. **Não aplicado ainda** (usuário aplica no SQL Editor do Lovable).
2. `worker-crawler/src/supabase.ts` (`persistRequisitorio`) — grava `titular_nome` a partir de
   `parte_ativa.nome` sempre que o crawler visita a ficha do `.0500`. **Já buildado e deployado
   em produção** (`/opt/precatorio-worker`, pm2 restart em 2026-07-22 22:59) — mas só populará
   `djen_depre.titular_nome` nos próximos re-crawls (não retroage sozinho pros já coletados).
3. `supabase/functions/buscar-precatorio/index.ts` — `buscarTitulares()` lê
   `djen_depre.titular_nome/titular_documento` por `numero_depre` pra todo item `.0500` do
   resultado; expõe `titular_nome` no payload (documento nunca volta, mesmo princípio de LGPD
   que já tirou `cpf_titular`/`cnpj_titular` da view pública). Backfill best-effort:
   `precatorios.autor` quando descobre nome via djen_depre (fecha o loop pro
   `enviar-relatorio`, que lê direto da tabela legada); `djen_depre.titular_documento` +
   `precatorios.cpf_titular`/`cnpj_titular` quando a busca é por CPF/CNPJ e bate num `.0500`.
   Também corrigido bug pré-existente: o campo de titular do braço legado estava hardcoded
   `maskCpf(null)` (sempre null, mesmo quando `precatorios.autor` tinha dado real).
4. `frontend/src/lib/api/precatorios.ts` — `PublicItem.titular_nome` adicionado ao tipo.

**Concluído em 2026-07-22**: migration aplicada, `buscar-precatorio` deployado no Lovable,
validado de ponta a ponta (curl real: `titular_nome` retornando, `precatorios.autor`
backfilled). O processo de teste (`0150268-84.2024.8.26.0500`) precisou de um upsert manual em
`djen_depre` pra retestar na hora — o re-crawl automático via fila não pegou o job em tempo
hábil durante a sessão (fila com bastante atividade concorrente, provável cron DJEN). Não
investigado a fundo — se o padrão se repetir, vale revisitar. Commit: `d4fdb4f`.

**Limitação conhecida, não resolvida agora**: busca por CPF/CNPJ no schema novo
(`partes.documento`) é código morto na prática — nada popula `partes.documento` hoje (o e-SAJ
nunca expõe CPF na ficha), então esse branch nunca encontra nada por CPF a menos que já exista
match prévio. Buscas por CPF real hoje só funcionam via a tabela legada
(`precatorios.cpf_titular`/`cnpj_titular`, vindo da carga inicial). Não é bug desta sessão —
é uma lacuna de produto pré-existente, registrada aqui pra não se perder.

---

## FASE 7 — Disparo manual no admin [Completada ✅]

### `supabase/functions/disparar-valor-pago/index.ts` [Completada ✅ — deployada]

Ponte fina pro endpoint HTTP do worker (`/valor-pago`) — só existe pra manter
`WORKER_HTTP_SECRET` fora do browser. O worker já persiste o resultado sozinho
(`consultarEPersistirPagamentos`); a function só repassa a resposta.

**Achado da sessão**: eu tinha escrito e commitado essa function no cortex-v1 como
`consultar-pagamento-manual` (commit `0ae01bd`) e dado o código pro usuário levar ao Lovable —
só que o usuário/Lovable já tinha criado e deployado ela horas antes, direto via Lovable AI,
com o nome `disparar-valor-pago` (commit `48206f2` em `precatorio-sp`, mesmo código
byte-a-byte). Removido o duplicado `consultar-pagamento-manual` do cortex-v1; o nome real em
produção é `disparar-valor-pago`, e é esse que o frontend chama.

### `frontend/src/lib/api/processos.ts` + `frontend/src/routes/admin.processos.$id.tsx` [Completada ✅]

Decisão: **botão por incidente** (não checkbox+lote) — mais simples, e o caso de uso real é
"reconsultar esse .0500 específico que parece desatualizado", não lote. Botão "Reconsultar
valor pago" no card do requisitório `.0500` (`RequisitorioDepre`, já existente por outra
sessão — `becf402`), mostra situação + tabela de pagamentos inline após a consulta.

**Nota de branch**: o frontend tinha 65 commits de atraso entre `for-83-frontend-resultado`
(onde eu commitei primeiro) e `precatorio-sp` (o que o Lovable sincroniza) — inclusive um
`DepreRow`/UI de requisitório que já não existia mais do jeito antigo. Reaplicado limpo num
branch novo a partir do `precatorio-sp` atual, via `git worktree` (não mexeu no branch/working
tree original, que tinha outras mudanças em andamento não relacionadas). PR aberto:
[#30](https://github.com/jjuniorfilho/sp-precat-rios-simples-c2fc47c1/pull/30).

### Teste manual no browser [Não Iniciada ⏳]

Selecionar processo(s) reais e confirmar que o resultado aparece corretamente na grade/detalhe.

### Comentários:
-

---

## FASE 8 — Validação end-to-end + decisão de fallback [Não Iniciada ⏳]

### Rodar contra volume real de processos `.0500` [Não Iniciada ⏳]

Medir taxa de sucesso do OCR em produção (VPS).

### Decisão: manter OCR ou plugar 2captcha [Não Iniciada ⏳]

Se a taxa de erro do OCR for alta o suficiente para prejudicar a experiência (síncrona!) da busca
pública, plugar 2captcha como fallback (interface já isolada desde a Fase 2).

### Atualizar `worker-crawler/README.md` [Não Iniciada ⏳]

Documentar o novo módulo, igual já é feito para o crawler e-SAJ.

### Comentários:
-
