-- Contagem de processos principais, cumprimentos de sentença e incidentes
-- por advogado, para as 3 OABs abaixo. Rodar no SQL Editor.
--
-- Antoniel Bispo dos Santos Filho — OAB/SP 185.164
-- Karolinne Kamilla Modesto      — OAB/SP 280.478
-- Kleber Bispo dos Santos        — OAB/SP 207.847
--
-- Leitura: processos = raiz da árvore e-SAJ ("processo principal");
-- cumprimentos = execução/cumprimento de sentença (filho de processos);
-- incidentes = precatório/RPV (pode estar sob um cumprimento ou direto sob o processo).
-- Considera só parte ativa (o credor representado pelo advogado).

with oabs as (
  select unnest(array['185164SP', '280478SP', '207847SP']) as oab_normalizada
)
select
  o.oab_normalizada,
  max(pa.advogado_nome) as advogado_nome,
  count(distinct pr.id) as n_processos_principais,
  count(distinct c.id)  as n_cumprimentos,
  count(distinct i.id)  as n_incidentes
from oabs o
join partes pa      on pa.oab_normalizada = o.oab_normalizada and pa.papel = 'ativa'
join incidentes i   on i.id = pa.incidente_id
join processos pr   on pr.id = i.processo_id
left join cumprimentos c on c.id = i.cumprimento_id
group by o.oab_normalizada
order by o.oab_normalizada;
