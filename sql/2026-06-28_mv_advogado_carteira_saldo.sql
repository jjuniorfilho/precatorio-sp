-- FOR-76 — mv_advogado_carteira: ranking por VALOR usar o saldo real do precatório.
-- Antes valor_total = sum(valor_acao) (proxy, NULO na maioria dos incidentes de
-- precatório/RPV) → advogados precatório-pesados apareciam com R$ 0. Agora:
--   valor_total      = soma do saldo_depre (via numero_depre = precatorios.processo_depre)
--   valor_acao_total = soma do valor_acao (proxy preservado)
--   n_com_saldo      = nº de incidentes com saldo de precatório conhecido
-- Materialized view não aceita CREATE OR REPLACE → drop + create + refresh.
-- A RPC buscar_advogados ordena por valor_total (agora = saldo); buscar_advogado_detalhe
-- faz to_jsonb(mv) e ganha as colunas novas automaticamente.
-- Aplicar no SQL Editor.

drop materialized view if exists public.mv_advogado_carteira;

create materialized view public.mv_advogado_carteira as
with pdepre as (
  select processo_depre, max(saldo_depre) as saldo_depre
  from public.precatorios
  where processo_depre is not null
  group by processo_depre
),
adv as (
  select coalesce(pa.oab_normalizada, 'NOME:'::text || upper(pa.advogado_nome)) as adv_key,
         pa.oab_normalizada,
         pa.advogado_nome,
         pa.oab_normalizada is null as sem_oab,
         i.id as incidente_id,
         i.processo_id,
         i.tipo_previsto,
         i.macrofase,
         i.fase,
         i.valor_acao,
         i.elegivel,
         i.possivelmente_pago,
         p.ente_esfera,
         pd.saldo_depre
    from partes pa
    join incidentes i on i.id = pa.incidente_id
    join processos p on p.id = i.processo_id
    left join pdepre pd on pd.processo_depre = i.numero_depre
   where pa.papel = 'ativa'::text and pa.advogado_nome is not null and p.flag_sp
)
select adv_key,
  max(oab_normalizada) as oab_normalizada,
  max(advogado_nome) as advogado_nome,
  bool_and(sem_oab) as sem_oab,
  count(distinct processo_id) as n_processos,
  count(distinct incidente_id) as n_incidentes,
  count(distinct incidente_id) filter (where tipo_previsto = 'Precatorio'::text) as n_prec,
  count(distinct incidente_id) filter (where tipo_previsto = 'RPV'::text) as n_rpv,
  count(distinct incidente_id) filter (where tipo_previsto = 'Indefinido'::text) as n_indef,
  count(distinct incidente_id) filter (where ente_esfera = 'Estadual'::text) as n_estadual,
  count(distinct incidente_id) filter (where ente_esfera = 'Municipal'::text) as n_municipal,
  -- VALOR = saldo real dos precatórios do advogado (dedup por processo_depre)
  coalesce(sum(saldo_depre), 0::numeric) as valor_total,
  -- proxy antigo preservado
  coalesce(sum(valor_acao), 0::numeric) as valor_acao_total,
  count(distinct incidente_id) filter (where saldo_depre is not null) as n_com_saldo,
  count(distinct incidente_id) filter (where macrofase = any (array['precatorio_efetivo'::text, 'rpv_efetivo'::text])) as n_efetivo,
  count(distinct incidente_id) filter (where macrofase = 'direito_creditorio'::text) as n_em_formacao,
  count(distinct incidente_id) filter (where elegivel) as n_eleg,
  count(distinct incidente_id) filter (where possivelmente_pago) as n_pago,
  count(distinct incidente_id) filter (where fase = 'calculo'::text) as f_calculo,
  count(distinct incidente_id) filter (where fase = 'incidente'::text) as f_incidente,
  count(distinct incidente_id) filter (where fase = 'termo'::text) as f_termo,
  count(distinct incidente_id) filter (where fase = 'depre'::text) as f_depre,
  count(distinct incidente_id) filter (where fase = 'oficio'::text) as f_oficio,
  count(distinct incidente_id) filter (where fase = 'oc'::text) as f_oc,
  case
    when count(*) filter (where ente_esfera = 'Estadual'::text) >= count(*) filter (where ente_esfera = 'Municipal'::text) then 'Estadual'::text
    else 'Municipal'::text
  end as esfera_predominante
 from adv
 group by adv_key;

refresh materialized view public.mv_advogado_carteira;
