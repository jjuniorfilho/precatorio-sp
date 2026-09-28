-- FOR-173 (6) — ROTEIRO DE TESTE no Postgres REAL (comportamento que os testes de texto do repo não provam).
--
-- JÁ VALIDADO em Postgres 15 real, num sandbox descartável que replica o schema vivo (sql/sandbox/
-- for173_validate_local.sh: 38 ok, 0 FALHOU, inclusive com os DEFAULT PRIVILEGES do Supabase). Rode-o TAMBÉM no
-- SQL Editor do projeto Supabase do worker, DEPOIS de aplicar os SQLs 1 a 4 e de o SQL 5 (verificação) dar tudo
-- ok = true: o sandbox é uma réplica, e só o banco real prova papéis/grants/policies reais.
--
-- COMO NADA FICA GRAVADO: o teste inteiro roda num único bloco DO que termina SEMPRE com RAISE EXCEPTION.
-- O erro desfaz TODAS as escritas do teste (leads e linhas de progresso de mentira). O RELATÓRIO vem na
-- própria MENSAGEM DO ERRO ("ERROR: FOR-173 roteiro ... nada foi gravado ..."): copie-a e cole no chat.
-- (O SQL Editor mostra só o resultado da última instrução, por isso não há BEGIN/ROLLBACK/SELECT final.)
-- As duas funções auxiliares ficam em pg_temp (somem com a sessão) e são criadas na mesma mensagem, então
-- também são desfeitas pelo erro.
--
-- Cobre o que só o banco real prova:
--   * lead avulso: os CHECKs (um DEPRE só, sem consentimento, documento com 11/14 dígitos), o índice único
--     parcial (2º avulso do mesmo DEPRE) e que email/relacao realmente aceitam NULL;
--   * o caminho PÚBLICO: o `anon` NÃO consegue forjar origem='avulso' nem gravar criado_por/documento, nem
--     inserir sem email/relacao; o cadastro normal do site AINDA passa; e o `anon` não consegue promover um
--     lead a avulso por UPDATE;
--   * a RPC de escrita: ON CONFLICT + p_nova (preserva vs. renova iniciada_em), normalização de etapa/origem/
--     etapa_falha, truncamento, rejeição de DEPRE/estado inválidos e a limpeza (7 dias e órfãs de 1 dia);
--   * as permissões por papel (anon / authenticated / service_role) nas duas RPCs e na tabela.
-- Nota: dentro de UMA transação now() é constante, então "preserva x renova iniciada_em" é provado
-- recuando iniciada_em à mão (UPDATE) antes de chamar a RPC.
--
-- Códigos esperados: 23514 = CHECK; 23505 = índice único; 42501 = RLS/permissão negada; P0001 = RAISE da RPC.

CREATE OR REPLACE FUNCTION pg_temp.tenta(p_sql text, p_role text DEFAULT NULL) RETURNS text
LANGUAGE plpgsql AS $f$
BEGIN
  IF p_role IS NOT NULL THEN
    EXECUTE format('SET LOCAL ROLE %I', p_role);
  END IF;
  EXECUTE p_sql;
  IF p_role IS NOT NULL THEN
    RESET ROLE;
  END IF;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  -- o sub-bloco desfaz o SET LOCAL ROLE; RESET por garantia
  RETURN 'BLOQUEADO ' || SQLSTATE || ' ' || left(SQLERRM, 90);
END
$f$;

CREATE OR REPLACE FUNCTION pg_temp.linha(p_caso text, p_esperado text, p_atual text) RETURNS text
LANGUAGE sql AS $f$
  SELECT CASE WHEN p_atual LIKE p_esperado || '%' THEN 'ok ' ELSE 'FALHOU ' END
         || p_caso || '  [esperado: ' || p_esperado || ' | atual: ' || p_atual || ']' || E'\n'
$f$;

DO $do$
DECLARE
  rel     text := '';
  falhas  int;
  oks     int;
  d1      constant text := '0000101-01.2020.8.26.0500';   -- DEPREs de mentira (não existem na base)
BEGIN
  RESET ROLE;

  -- ================= LEADS (papel do editor; RLS não se aplica ao dono da tabela) =================
  rel := rel || pg_temp.linha('avulso válido (email/relacao/nome/telefone NULL) INSERE',
    'OK', pg_temp.tenta($q$INSERT INTO public.leads (processo_depre, origem, lgpd_consent, documento)
      VALUES ('0000001-01.2020.8.26.0500', 'avulso', false, '12345678901')$q$));
  rel := rel || pg_temp.linha('2º avulso do MESMO DEPRE é barrado (índice único parcial)',
    'BLOQUEADO 23505', pg_temp.tenta($q$INSERT INTO public.leads (processo_depre, origem, lgpd_consent)
      VALUES ('0000001-01.2020.8.26.0500', 'avulso', false)$q$));
  rel := rel || pg_temp.linha('avulso com DOIS DEPREs (vírgula) é barrado',
    'BLOQUEADO 23514', pg_temp.tenta($q$INSERT INTO public.leads (processo_depre, origem, lgpd_consent)
      VALUES ('0000002-01.2020.8.26.0500,0000003-01.2020.8.26.0500', 'avulso', false)$q$));
  rel := rel || pg_temp.linha('avulso COM consentimento é barrado',
    'BLOQUEADO 23514', pg_temp.tenta($q$INSERT INTO public.leads (processo_depre, origem, lgpd_consent)
      VALUES ('0000004-01.2020.8.26.0500', 'avulso', true)$q$));
  rel := rel || pg_temp.linha('documento com 3 dígitos é barrado (CHECK 11/14)',
    'BLOQUEADO 23514', pg_temp.tenta($q$INSERT INTO public.leads (processo_depre, origem, lgpd_consent, documento)
      VALUES ('0000005-01.2020.8.26.0500', 'avulso', false, '123')$q$));
  rel := rel || pg_temp.linha('documento com 14 dígitos (CNPJ) é aceito',
    'OK', pg_temp.tenta($q$INSERT INTO public.leads (processo_depre, origem, lgpd_consent, documento)
      VALUES ('0000006-01.2020.8.26.0500', 'avulso', false, '12345678000199')$q$));

  -- ================= LEADS como ANON (o caminho PÚBLICO — o mais sensível) =================
  rel := rel || pg_temp.linha('anon NÃO forja origem=avulso',
    'BLOQUEADO 42501', pg_temp.tenta($q$INSERT INTO public.leads (email, relacao, lgpd_consent, origem, processo_depre)
      VALUES ('t@t.com', 'titular', true, 'avulso', '0000010-01.2020.8.26.0500')$q$, 'anon'));
  rel := rel || pg_temp.linha('anon NÃO grava criado_por',
    'BLOQUEADO 42501', pg_temp.tenta($q$INSERT INTO public.leads (email, relacao, lgpd_consent, criado_por, processo_depre)
      VALUES ('t@t.com', 'titular', true, gen_random_uuid(), '0000012-01.2020.8.26.0500')$q$, 'anon'));
  rel := rel || pg_temp.linha('anon NÃO grava documento',
    'BLOQUEADO 42501', pg_temp.tenta($q$INSERT INTO public.leads (email, relacao, lgpd_consent, documento, processo_depre)
      VALUES ('t@t.com', 'titular', true, '12345678901', '0000013-01.2020.8.26.0500')$q$, 'anon'));
  rel := rel || pg_temp.linha('anon NÃO insere sem email',
    'BLOQUEADO 42501', pg_temp.tenta($q$INSERT INTO public.leads (relacao, lgpd_consent, processo_depre)
      VALUES ('titular', true, '0000014-01.2020.8.26.0500')$q$, 'anon'));
  rel := rel || pg_temp.linha('anon NÃO insere sem relacao',
    'BLOQUEADO 42501', pg_temp.tenta($q$INSERT INTO public.leads (email, lgpd_consent, processo_depre)
      VALUES ('t@t.com', true, '0000015-01.2020.8.26.0500')$q$, 'anon'));
  rel := rel || pg_temp.linha('anon NÃO insere sem consentimento',
    'BLOQUEADO 42501', pg_temp.tenta($q$INSERT INTO public.leads (email, relacao, lgpd_consent, processo_depre)
      VALUES ('t@t.com', 'titular', false, '0000016-01.2020.8.26.0500')$q$, 'anon'));
  rel := rel || pg_temp.linha('CADASTRO NORMAL DO SITE (nome/email/telefone/relacao/consent) AINDA PASSA',
    'OK', pg_temp.tenta($q$INSERT INTO public.leads (nome, email, telefone, relacao, processo_depre, saldo_consultado, session_id, intent, lgpd_consent, lgpd_consent_at)
      VALUES ('Teste Site', 't@t.com', '11999999999', 'titular', '0000011-01.2020.8.26.0500', 0, 'sess-teste', 'info', true, now())$q$, 'anon'));
  -- (informativo: sem policy de UPDATE para o anon o UPDATE tipicamente afeta 0 linhas SEM erro; o que vale é o efeito, conferido na linha seguinte)
  rel := rel || pg_temp.linha('anon tenta promover o lead do site a avulso por UPDATE (informativo: OK com 0 linhas ou BLOQUEADO)',
    '', pg_temp.tenta($q$UPDATE public.leads SET origem = 'avulso' WHERE processo_depre = '0000011-01.2020.8.26.0500'$q$, 'anon'));
  rel := rel || pg_temp.linha('…e o lead do site continua SEM origem=avulso',
    'sim', CASE WHEN (SELECT origem FROM public.leads WHERE processo_depre = '0000011-01.2020.8.26.0500') IS NULL THEN 'sim' ELSE 'NAO' END);

  -- ================= RPC DE ESCRITA: ON CONFLICT / p_nova / normalização =================
  rel := rel || pg_temp.linha('escrita na_fila nova=true (1ª escrita) INSERE',
    'OK', pg_temp.tenta(format($q$SELECT public.registrar_progresso_consulta_pagamento(%L,'na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$, d1)));
  UPDATE public.pagamentos_consultas_progresso SET iniciada_em = now() - interval '1 hour' WHERE processo_depre = d1;
  rel := rel || pg_temp.linha('escrita nova=false atualiza',
    'OK', pg_temp.tenta(format($q$SELECT public.registrar_progresso_consulta_pagamento(%L,'em_andamento','busca',1,4,'Tentativa 1 de 4',NULL,NULL,'manual',false)$q$, d1)));
  rel := rel || pg_temp.linha('nova=false PRESERVA iniciada_em (recuada 1h à mão)',
    'sim', (SELECT CASE WHEN iniciada_em < now() - interval '30 minutes' AND etapa = 'busca' AND tentativa = 1 THEN 'sim'
                        ELSE 'NAO (etapa=' || coalesce(etapa,'null') || ')' END
              FROM public.pagamentos_consultas_progresso WHERE processo_depre = d1));
  rel := rel || pg_temp.linha('nova=true + etapa lixo + origem lixo + detalhe de 300 chars',
    'OK', pg_temp.tenta(format($q$SELECT public.registrar_progresso_consulta_pagamento(%L,'em_andamento','lixo',1,4,%L,NULL,NULL,'zzz',true)$q$, d1, repeat('a', 300))));
  rel := rel || pg_temp.linha('nova=true RENOVA iniciada_em; etapa lixo→desconhecida; detalhe truncado em 200; origem lixo NÃO apaga a gravada',
    'sim', (SELECT CASE WHEN iniciada_em > now() - interval '1 minute' AND etapa = 'desconhecida'
                             AND length(detalhe) = 200 AND origem = 'manual' THEN 'sim'
                        ELSE 'NAO (etapa=' || coalesce(etapa,'null') || ', len=' || coalesce(length(detalhe)::text,'null') || ', origem=' || coalesce(origem,'null') || ')' END
              FROM public.pagamentos_consultas_progresso WHERE processo_depre = d1));
  rel := rel || pg_temp.linha('falha com etapa_falha fora da lista',
    'OK', pg_temp.tenta(format($q$SELECT public.registrar_progresso_consulta_pagamento(%L,'falha','busca',9,4,NULL,'falha','fake',NULL,false)$q$, d1)));
  rel := rel || pg_temp.linha('etapa_falha lixo→desconhecida; estado=falha; resultado=falha; tentativa limitada',
    'sim', (SELECT CASE WHEN etapa_falha = 'desconhecida' AND estado = 'falha' AND resultado = 'falha' THEN 'sim'
                        ELSE 'NAO (' || coalesce(etapa_falha,'null') || '/' || estado || '/' || coalesce(resultado,'null') || ')' END
              FROM public.pagamentos_consultas_progresso WHERE processo_depre = d1));
  rel := rel || pg_temp.linha('DEPRE inválido (sufixo certo, formato errado) é rejeitado',
    'BLOQUEADO P0001', pg_temp.tenta($q$SELECT public.registrar_progresso_consulta_pagamento('lixo.8.26.0500','na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$));
  rel := rel || pg_temp.linha('DEPRE com sufixo .0499 é rejeitado',
    'BLOQUEADO P0001', pg_temp.tenta($q$SELECT public.registrar_progresso_consulta_pagamento('0145616-63.2020.8.26.0499','na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$));
  rel := rel || pg_temp.linha('estado inválido é rejeitado',
    'BLOQUEADO P0001', pg_temp.tenta(format($q$SELECT public.registrar_progresso_consulta_pagamento(%L,'xxx','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$, d1)));

  -- limpeza preguiçosa: concluída velha (8d) e órfã (2d) somem; recente (1h) fica
  INSERT INTO public.pagamentos_consultas_progresso (processo_depre, estado, atualizado_em) VALUES
    ('0000201-01.2020.8.26.0500', 'concluida',    now() - interval '8 days'),
    ('0000202-01.2020.8.26.0500', 'em_andamento', now() - interval '2 days'),
    ('0000203-01.2020.8.26.0500', 'em_andamento', now() - interval '1 hour');
  rel := rel || pg_temp.linha('escrita nova dispara a limpeza',
    'OK', pg_temp.tenta($q$SELECT public.registrar_progresso_consulta_pagamento('0000204-01.2020.8.26.0500','na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$));
  rel := rel || pg_temp.linha('limpeza: concluída de 8 dias e órfã de 2 dias APAGADAS; recente de 1h PRESERVADA',
    'sim', (SELECT CASE WHEN count(*) FILTER (WHERE processo_depre IN ('0000201-01.2020.8.26.0500','0000202-01.2020.8.26.0500')) = 0
                         AND count(*) FILTER (WHERE processo_depre = '0000203-01.2020.8.26.0500') = 1 THEN 'sim'
                        ELSE 'NAO (' || count(*)::text || ' linhas)' END
              FROM public.pagamentos_consultas_progresso
             WHERE processo_depre IN ('0000201-01.2020.8.26.0500','0000202-01.2020.8.26.0500','0000203-01.2020.8.26.0500')));

  -- ================= RPC DE LEITURA =================
  rel := rel || pg_temp.linha('obter devolve NULL para DEPRE sem linha',
    'sim', CASE WHEN public.obter_progresso_consulta_pagamento('0000999-01.2020.8.26.0500') IS NULL THEN 'sim' ELSE 'NAO' END);
  rel := rel || pg_temp.linha('obter devolve o jsonb do contrato (estado, etapa, tentativa, iniciada_em…)',
    'sim', CASE WHEN (public.obter_progresso_consulta_pagamento(d1) ?& ARRAY['estado','etapa','tentativa','max_tentativas','detalhe','resultado','etapa_falha','origem','iniciada_em','atualizado_em'])
                 AND (public.obter_progresso_consulta_pagamento(d1)->>'estado') = 'falha' THEN 'sim' ELSE 'NAO' END);

  -- ================= PERMISSÕES POR PAPEL =================
  rel := rel || pg_temp.linha('anon NÃO executa a leitura', 'BLOQUEADO 42501',
    pg_temp.tenta(format($q$SELECT public.obter_progresso_consulta_pagamento(%L)$q$, d1), 'anon'));
  rel := rel || pg_temp.linha('authenticated NÃO executa a leitura', 'BLOQUEADO 42501',
    pg_temp.tenta(format($q$SELECT public.obter_progresso_consulta_pagamento(%L)$q$, d1), 'authenticated'));
  rel := rel || pg_temp.linha('service_role executa a leitura', 'OK',
    pg_temp.tenta(format($q$SELECT public.obter_progresso_consulta_pagamento(%L)$q$, d1), 'service_role'));
  rel := rel || pg_temp.linha('anon NÃO executa a escrita', 'BLOQUEADO 42501',
    pg_temp.tenta($q$SELECT public.registrar_progresso_consulta_pagamento('0000301-01.2020.8.26.0500','na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$, 'anon'));
  rel := rel || pg_temp.linha('authenticated executa a escrita (o worker pode autenticar assim)', 'OK',
    pg_temp.tenta($q$SELECT public.registrar_progresso_consulta_pagamento('0000302-01.2020.8.26.0500','na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$, 'authenticated'));
  rel := rel || pg_temp.linha('service_role executa a escrita', 'OK',
    pg_temp.tenta($q$SELECT public.registrar_progresso_consulta_pagamento('0000303-01.2020.8.26.0500','na_fila','na_fila',0,4,NULL,NULL,NULL,'manual',true)$q$, 'service_role'));
  rel := rel || pg_temp.linha('anon NÃO lê a tabela de progresso direto', 'BLOQUEADO 42501',
    pg_temp.tenta('SELECT count(*) FROM public.pagamentos_consultas_progresso', 'anon'));
  rel := rel || pg_temp.linha('authenticated NÃO lê a tabela de progresso direto', 'BLOQUEADO 42501',
    pg_temp.tenta('SELECT count(*) FROM public.pagamentos_consultas_progresso', 'authenticated'));
  rel := rel || pg_temp.linha('anon NÃO lê a view leads_processos (PII)', 'BLOQUEADO 42501',
    pg_temp.tenta('SELECT count(*) FROM public.leads_processos', 'anon'));

  SELECT count(*) INTO falhas FROM regexp_matches(rel, E'(^|\\n)FALHOU ', 'g');
  SELECT count(*) INTO oks    FROM regexp_matches(rel, E'(^|\\n)ok ', 'g');

  RAISE EXCEPTION E'FOR-173 roteiro transacional — NADA foi gravado (este erro desfaz o teste inteiro).\n\n%\nRESUMO: % ok, % FALHOU',
    rel, oks, falhas;
END
$do$;
