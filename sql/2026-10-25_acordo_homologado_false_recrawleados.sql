-- Fichas .0500 recrawleadas pelo worker novo (deploy 2026-10-22 02:30 UTC, PR #46/#47) com a Movimentação
-- lida por inteiro e SEM "Homologo o acordo" -> acordo_homologado = false (verificado de verdade).
-- Daqui para frente o próprio worker grava o false (PR feat/acordo-homologado-false-leitura-completa);
-- este UPDATE só acerta o que foi crawleado entre o deploy e o deploy desse PR. Aplicar DEPOIS do deploy
-- do worker novo, senão ele regrava null por cima nos recrawls seguintes.
-- Critério de "leitura completa": o jsonb tem linhas típicas de Movimentação (não só Petições diversas).
set statement_timeout = '300s';
update djen_depre d
   set acordo_homologado = false
 where d.acordo_homologado is null
   and d.ficha_crawled_at > timestamptz '2026-10-22 02:30:00+00'
   and jsonb_typeof(d.andamentos) = 'array'
   and exists (
     select 1 from jsonb_array_elements(d.andamentos) a
      where a->>'descricao' ~* '^(Certidão de Publicação Expedida|Remetido ao DJE|Documento Juntado|DEPRE |Ofício Requisitório|ENCAMINHADO|Petição de Informações)'
   );
-- Verificação: select acordo_homologado, count(*) from djen_depre group by 1 order by 1;
-- Esperado: false ≈ 1.7k (as recrawleadas sem homologação), true ≈ 2.1k, resto null.
