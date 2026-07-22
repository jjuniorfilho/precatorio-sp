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

## FASE 3 — Navegação do portal (`pagamentos-tjsp.ts`) [Em Progresso ⏰ — bloqueada, ver Comentários]

### Sessão + busca por `processo_depre` [Em Progresso ⏰ — implementado, não funcional ainda]

Escrito `worker-crawler/src/pagamentos-tjsp.ts` seguindo o estilo de `esaj.ts` (HTTP puro via
`undici`): `abrirSessaoPagamentos()` (GET `webmenupesquisa.aspx` → token → GET
`pesquisainternetv2.aspx?<token>` → `GXState` inicial) + `ajaxCall()` (replica uma chamada AJAX do
GeneXus: headers `ajax_security_token`/`gxajaxrequest`, URL `?<nonce>,<token>,gx-no-cache=<ts>`,
corpo com `GXState` + campos do form) + `buscarPagamentos()` (encadeia os 3 eventos
`EVENT_ID.ISVALID.` → `ERFR.` → `E'PESQUISAR'.`, com retry de captcha).

**🚧 Bloqueada**: testei o módulo de verdade (não script solto — o próprio `.ts`, rodando com
`tsx` numa cópia isolada fora da produção) contra o portal real, com logging de request/response.
**Toda chamada retorna HTTP 440 "Session timeout" imediatamente**, mesmo a primeira da sequência,
mesmo com cookies (`ASP.NET_SessionId`, `GX_SESSION_ID`, `X-Mapping-mkemcnbb` — esse último parece
cookie de afinidade de load balancer) sendo capturados e reenviados corretamente. Headers, URL e
corpo conferem com a captura real do navegador. Não consegui isolar a causa exata (candidatos:
diferença sutil na serialização do `GXState` ao fazer `JSON.parse`+`JSON.stringify` — o servidor
pode ser sensível a formatação/ordem exata dos campos; algum comportamento de cookie-jar do
`undici` diferente do Chrome; ou o `X-Mapping-mkemcnbb` de fato exigir alguma outra coisa do load
balancer que curl/undici não replicam da mesma forma que um navegador real).

**Recomendação para retomar**: dado que replicar esse protocolo GeneXus via HTTP puro já consumiu
esforço considerável sem sucesso (diferente do e-SAJ, que é bem mais simples), a essa altura
**Playwright só pra este fluxo específico** provavelmente compensa mais do que continuar
depurando o AJAX manualmente — deixa o navegador real cuidar de cookies/sessão/timing, que é
exatamente o tipo de coisa que esse protocolo está exigindo. Isso muda o trade-off registrado em
`architecture.md` ("HTTP puro vs Playwright") — vale revisitar essa decisão com o usuário antes de
continuar.

### Parse do resultado + navegação pro detalhe [Não Iniciada ⏳]

Parsear a lista de resultados (EP/Ano, Processo DEPRE, Entidade Devedora) e seguir o link/postback
do ícone de detalhe. **Bloqueado pelo item acima** — sem conseguir completar uma busca, não há
HTML de resultado real pra desenvolver/testar este parser contra.

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

## FASE 4 — Persistência (`supabase.ts`) [Não Iniciada ⏳]

### `upsertPagamentos(processoDepre, pagamentos[])` [Não Iniciada ⏳]

Upsert idempotente na `precatorios_pagamentos` (limpar+reinserir por `processo_depre`, ou upsert por
chave composta `processo_depre+data_pagamento+valor` — decidir na implementação).

### `markPagamentosConsultado(processoDepre)` [Não Iniciada ⏳]

Seta `precatorios.pagamentos_consultado_em = now()` mesmo quando não há pagamentos.

### Teste de idempotência [Não Iniciada ⏳]

Rodar a mesma consulta 2x e confirmar que não duplica registros.

### Comentários:
-

---

## FASE 5 — Endpoint HTTP síncrono no worker [Não Iniciada ⏳]

### `worker-crawler/src/http-server.ts` [Não Iniciada ⏳]

`POST /valor-pago { processo_depre }` (Node `http` nativo) → chama Fase 3+4 on-demand → retorna
`{ pagamentos: [...], consultado_em }`. Timeout interno definido com folga contra o teto da edge function.

### Subir o servidor junto ao loop existente [Não Iniciada ⏳]

Modificar `worker-crawler/src/index.ts` para iniciar o `http-server.ts` em paralelo ao loop de
`claim/crawl/persist` já existente, sem interferir um no outro.

### Teste via curl direto na VPS [Não Iniciada ⏳]

Confirmar que o endpoint responde corretamente antes de integrar com o resto do sistema.

### Comentários:
-

---

## FASE 6 — Integração na busca pública [Não Iniciada ⏳]

### `supabase/functions/buscar-precatorio/index.ts` [Não Iniciada ⏳]

Quando o processo encontrado tem `.0500` (ou o `numero_depre` do incidente termina em `.0500`),
chamar o endpoint da Fase 5 de forma síncrona antes de montar a resposta; incorporar `pagamentos`/
`pagamentos_consultado_em` no payload retornado.

### Teste end-to-end de busca real no site [Não Iniciada ⏳]

Validar a latência adicionada e o conteúdo da resposta com um processo real.

### Comentários:
-

---

## FASE 7 — Disparo manual no admin [Não Iniciada ⏳]

### `frontend/src/lib/api/processos.ts` [Não Iniciada ⏳]

Nova função client que chama o endpoint da Fase 5 (via edge function ponte, se necessário, ou
diretamente — decidir conforme exposição de rede do worker).

### `frontend/src/routes/admin.processos.tsx` [Não Iniciada ⏳]

UI de disparo — **padrão novo** (sem precedente no admin): checkbox por linha + botão em lote, ou
botão por linha (mais simples) — decidir na implementação conforme trade-off já registrado em
`architecture.md`.

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
