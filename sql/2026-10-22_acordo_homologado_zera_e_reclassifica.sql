-- Acordo homologado: troca da regra fraca ("Comunicado de Acordo de Requisitório" = petição
-- que só informa que há acordo) pela regra segura = frase de homologação do juiz na ficha
-- do .0500 ("Homologo o acordo"). Ver parse.ts:temAcordoHomologado (mantenha em sincronia).
--
-- Por que zerar tudo: ~200k fichas foram gravadas com andamentos vazios (o parser não
-- capturava a Movimentação) e ficaram `false` sem nunca terem sido verificadas; os 712 `true`
-- vieram da regra fraca (nenhum tem "Homologo o acordo"). Tri-state, como cessao_credito
-- (FOR-202): NULL = não verificado; `true` só com prova; `false` só depois do recrawl completo.
--
-- Ordem: (1) deploy do worker com a regra nova  (2) ESTE script  (3) enfileira recrawl
-- (sql/2026-10-22_acordo_homologado_enfileira_recrawl.sql). Se o worker antigo ainda rodar,
-- ele regrava `true` pela regra fraca a cada crawl.
--
-- Os andamentos NÃO são apagados: o recrawl os sobrescreve, e até lá o que já está gravado
-- (incl. 5.875 textos legados com "Homologo o acordo") continua servindo à reclassificação.
-- Rode cada bloco separado no SQL Editor.

-- 1) Zera toda a coluna.
set statement_timeout = '300s';
update djen_depre set acordo_homologado = null where acordo_homologado is not null;

-- 2) Reclassifica o que já está provado pelos andamentos gravados. Mesma regex do JS:
--    sem "não" antes, aceita plural, exclui "acordo de compensação" (outro instituto).
--    Em blocos por id (a regex com lookbehind sobre jsonb de até 16k chars é pesada: um
--    count dela sobre a tabela toda estourou o timeout do MCP). O ilike barato vai antes.
--    Repita mudando o intervalo até cobrir max(id) (~369.361 em 2026-10-22; select max(id) from djen_depre).
set statement_timeout = '300s';
update djen_depre d
   set acordo_homologado = true
 where d.id between 0 and 50000
   and jsonb_typeof(d.andamentos) = 'array'
   and jsonb_array_length(d.andamentos) > 0
   and exists (
     select 1 from jsonb_array_elements(d.andamentos) a
      where a->>'descricao' ilike '%homologo%'
        and a->>'descricao' ~* '(?<!n[ãa]o\s)homologo\s+os?\s+acordos?\y(?!\s+de\s+compensa)'
   );

-- Verificação (separado). Esperado: true ≈ 2.778 (menos os de compensação), resto null.
-- select acordo_homologado, count(*) from djen_depre group by 1 order by 1;
