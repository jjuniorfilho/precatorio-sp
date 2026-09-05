-- Verifica, pra uma lista de números .0500, se o incidente correspondente tem algum
-- andamento indicando cessão de crédito (ex.: "Cessão de crédito - DEPRE",
-- "Cessão de Crédito de Requisitório"). Read-only. Aplicar no SQL Editor.

create or replace function public.diag_cessao_credito(p_numeros text[])
returns table(
  numero_informado text,
  existe_incidente boolean,
  tem_cessao boolean,
  andamentos_cessao jsonb
)
language sql stable security definer set search_path = public
as $$
  with entrada as (
    select distinct numero_informado, regexp_replace(numero_informado, '\D', '', 'g') as numero_normalizado
      from unnest(p_numeros) as numero_informado
  ),
  -- Mesmo padrão dual (cnj OU numero_depre) de lookup_precatorios_lote, incluindo a
  -- normalização por dígitos dos dois lados: comparar string exata (sem normalizar)
  -- prendia existe_incidente em ~83% mesmo quando lookup_precatorios_lote achava 100% —
  -- máscara/pontuação de cnj/numero_depre em incidentes varia e batia só depois de
  -- regexp_replace. Nem todo .0500 está linkado por cnj direto no incidente — vários
  -- (achado real, ex. 0254129-96...) só têm o link via numero_depre.
  incidentes_norm as materialized (
    select id, regexp_replace(cnj, '\D', '', 'g') as cnj_normalizado,
           regexp_replace(coalesce(numero_depre, ''), '\D', '', 'g') as numero_depre_norm
      from incidentes
  ),
  inc_por_cnj as materialized (
    select e.numero_informado, i.id as incidente_id, 0 as prioridade
      from entrada e
      join incidentes_norm i on i.cnj_normalizado = e.numero_normalizado
  ),
  inc_por_depre as materialized (
    select e.numero_informado, i.id as incidente_id, 1 as prioridade
      from entrada e
      join incidentes_norm i on i.numero_depre_norm = e.numero_normalizado and i.numero_depre_norm <> ''
  ),
  inc_uniao as (
    select *, row_number() over (partition by numero_informado order by prioridade, incidente_id) as rn
      from (select * from inc_por_cnj union all select * from inc_por_depre) u
  ),
  inc as (
    select numero_informado, incidente_id from inc_uniao where rn = 1
  ),
  -- Restringe primeiro aos incidentes de interesse (join indexado por incidente_id) —
  -- ILIKE na tabela andamentos inteira (provavelmente milhões de linhas) estourava o
  -- statement timeout mesmo materializado; filtrando por incidente_id antes, o ILIKE
  -- roda só sobre o subconjunto pequeno relevante.
  andamentos_relevantes as materialized (
    select a.incidente_id, a.data, a.descricao
      from andamentos a
      join inc on inc.incidente_id = a.incidente_id
  ),
  -- Os 2 termos originais do usuário não batiam literalmente com nenhum andamento real
  -- (confirmado testando contra 0254129-96.2018.8.26.0500) — troca pelos 4 rótulos de tipo
  -- de movimentação que de fato aparecem nesse processo-exemplo. 3 deles são o próprio
  -- início da célula (ILIKE ancorado, sem % antes); o 4º ("Ato Ordinatório...") só tem
  -- "Cessão de Crédito" como sufixo depois de um prefixo genérico, então não pode ser
  -- ancorado no início — teria que casar qualquer "Ato Ordinatório" (falso positivo demais).
  cessoes as (
    select incidente_id,
           jsonb_agg(jsonb_build_object('data', data, 'descricao', descricao) order by data desc) as itens
      from andamentos_relevantes
     where descricao ilike 'DEPRE - Informação de Cessão de Crédito%'
        or descricao ilike 'Ofício Requisitório - Cessão de Crédito%'
        or descricao ilike 'Decisão - Homologada a Cessão de Crédito%'
        or descricao ilike '%+ Ofício Cessão de Crédito%'
     group by incidente_id
  )
  select e.numero_informado,
         inc.incidente_id is not null as existe_incidente,
         c.itens is not null as tem_cessao,
         coalesce(c.itens, '[]'::jsonb) as andamentos_cessao
    from entrada e
    left join inc on inc.numero_informado = e.numero_informado
    left join cessoes c on c.incidente_id = inc.incidente_id;
$$;

grant execute on function public.diag_cessao_credito(text[]) to anon, authenticated;
