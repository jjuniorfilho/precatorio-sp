-- FOR-76 (v2) — corrige double-count do saldo na mv_advogado_carteira.
-- A v1 somava saldo POR INCIDENTE; quando o mesmo advogado tem vários incidentes
-- que referenciam o MESMO precatório (numero_depre), o saldo era contado N vezes.
-- v2: soma o saldo UMA VEZ por (advogado, numero_depre). n_com_saldo = nº de
-- precatórios distintos com saldo do advogado.
-- Aplicar no SQL Editor (substitui a v1).

drop materialized view if exists public.mv_advogado_carteira;

create materialized view public.mv_advogado_carteira as
with pdepre as (
  select processo_depre, max(saldo_depre) as saldo_depre
  from public.precatorios where processo_depre is not null
  group by processo_depre
),
adv as (
  select coalesce(pa.oab_normalizada, 'NOME:'::text || upper(pa.advogado_nome)) as adv_key,
         pa.oab_normalizada, pa.advogado_nome, pa.oab_normalizada is null as sem_oab,
         i.id as incidente_id, i.processo_id, i.numero_depre, i.tipo_previsto, i.macrofase, i.fase,
         i.valor_acao, i.elegivel, i.possivelmente_pago, p.ente_esfera, pd.saldo_depre
    from partes pa
    join incidentes i on i.id = pa.incidente_id
    join processos p on p.id = i.processo_id
    left join pdepre pd on pd.processo_depre = i.numero_depre
   where pa.papel = 'ativa'::text and pa.advogado_nome is not null and p.flag_sp
),
saldo_adv as (
  -- cada precatório (numero_depre) conta uma vez por advogado
  select adv_key, coalesce(sum(saldo_depre), 0::numeric) as valor_total, count(*) as n_com_saldo
  from (select distinct adv_key, numero_depre, saldo_depre
          from adv where numero_depre is not null and saldo_depre is not null) d
  group by adv_key
)
select a.adv_key,
  max(a.oab_normalizada) as oab_normalizada,
  max(a.advogado_nome) as advogado_nome,
  bool_and(a.sem_oab) as sem_oab,
  count(distinct a.processo_id) as n_processos,
  count(distinct a.incidente_id) as n_incidentes,
  count(distinct a.incidente_id) filter (where a.tipo_previsto = 'Precatorio'::text) as n_prec,
  count(distinct a.incidente_id) filter (where a.tipo_previsto = 'RPV'::text) as n_rpv,
  count(distinct a.incidente_id) filter (where a.tipo_previsto = 'Indefinido'::text) as n_indef,
  count(distinct a.incidente_id) filter (where a.ente_esfera = 'Estadual'::text) as n_estadual,
  count(distinct a.incidente_id) filter (where a.ente_esfera = 'Municipal'::text) as n_municipal,
  coalesce(max(s.valor_total), 0::numeric) as valor_total,
  coalesce(sum(a.valor_acao), 0::numeric) as valor_acao_total,
  coalesce(max(s.n_com_saldo), 0) as n_com_saldo,
  count(distinct a.incidente_id) filter (where a.macrofase = any (array['precatorio_efetivo'::text, 'rpv_efetivo'::text])) as n_efetivo,
  count(distinct a.incidente_id) filter (where a.macrofase = 'direito_creditorio'::text) as n_em_formacao,
  count(distinct a.incidente_id) filter (where a.elegivel) as n_eleg,
  count(distinct a.incidente_id) filter (where a.possivelmente_pago) as n_pago,
  count(distinct a.incidente_id) filter (where a.fase = 'calculo'::text) as f_calculo,
  count(distinct a.incidente_id) filter (where a.fase = 'incidente'::text) as f_incidente,
  count(distinct a.incidente_id) filter (where a.fase = 'termo'::text) as f_termo,
  count(distinct a.incidente_id) filter (where a.fase = 'depre'::text) as f_depre,
  count(distinct a.incidente_id) filter (where a.fase = 'oficio'::text) as f_oficio,
  count(distinct a.incidente_id) filter (where a.fase = 'oc'::text) as f_oc,
  case
    when count(*) filter (where a.ente_esfera = 'Estadual'::text) >= count(*) filter (where a.ente_esfera = 'Municipal'::text)
    then 'Estadual'::text else 'Municipal'::text end as esfera_predominante
 from adv a
 left join saldo_adv s on s.adv_key = a.adv_key
 group by a.adv_key;

refresh materialized view public.mv_advogado_carteira;
