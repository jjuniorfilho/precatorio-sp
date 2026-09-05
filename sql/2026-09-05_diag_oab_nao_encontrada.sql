-- Diagnóstico: por que a contagem por OAB (185164/280478/207847) voltou vazia?
-- Rodar no SQL Editor e conferir os resultados de cada bloco.

-- 1) Existe alguma parte com esses números de OAB, em qualquer formato?
select oab, oab_normalizada, advogado_nome, papel, fonte, count(*)
from partes
where oab ilike '%185164%' or oab ilike '%185.164%'
   or oab ilike '%280478%' or oab ilike '%280.478%'
   or oab ilike '%207847%' or oab ilike '%207.847%'
group by oab, oab_normalizada, advogado_nome, papel, fonte
order by oab_normalizada;

-- 2) Existe alguma parte com esses nomes (nome pode estar com variação de acento/maiúsculas)?
select oab, oab_normalizada, advogado_nome, papel, fonte, count(*)
from partes
where advogado_nome ilike '%antoniel%bispo%'
   or advogado_nome ilike '%karolinne%modesto%'
   or advogado_nome ilike '%kleber%bispo%'
group by oab, oab_normalizada, advogado_nome, papel, fonte
order by advogado_nome;

-- 3) Como o oab_normalizada costuma se parecer (amostra geral, pra comparar o padrão)?
select oab, oab_normalizada
from partes
where oab_normalizada is not null
limit 20;
