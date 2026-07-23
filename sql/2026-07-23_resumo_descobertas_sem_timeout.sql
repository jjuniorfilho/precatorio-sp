-- FOR-104 (extensão) — resumo_descobertas também estourava statement timeout (57014),
-- mesma causa raiz da buscar_processos. O frontend engolia o erro silenciosamente
-- (fetchResumoDescobertas captura e devolve zerado) — por isso os totalizadores do
-- admin/processos apareciam como "0 descobertos" com todas as dimensões em "—", parecendo
-- só "não calculado" em vez de erro.
--
-- Tentativa 1 (sargable filter em created_at + índice) não bastou sozinha: verificado ao
-- vivo que 38.850 dos 305.168 incidentes (~13%) foram criados nos últimos 7 dias (backfill
-- ativo essa semana) — filtro de data não é seletivo agora. A causa real é a função
-- referenciar a CTE `per` 4x (total/esfera/instrumento/fase) sem MATERIALIZED — o Postgres
-- pode estar recalculando o JOIN inteiro contra esse conjunto grande em cada uma das 4
-- passagens. Fix: força materialização de `base`/`per` (calcula uma vez só; as 4 agregações
-- viram GROUP BY baratos em memória sobre o resultado já pronto). Aplicar no SQL Editor
-- (idx_incidentes_created_at desta migration precisa já ter sido aplicado antes).

create or replace function public.resumo_descobertas()
returns table(periodo text, dimensao text, chave text, n bigint)
language sql stable security definer set search_path to 'public'
as $function$
  with base as materialized (
    select i.tipo_previsto, i.fase, coalesce(p.ente_esfera,'Outro') as esfera, i.created_at
      from incidentes i
      join processos p on p.id = i.processo_id
     where p.flag_sp
       and i.created_at >= (date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo') - interval '6 days'
  ),
  per as materialized (
    select 'dia'::text as periodo, tipo_previsto, fase, esfera from base
      where created_at >= (date_trunc('day', now() at time zone 'America/Sao_Paulo') at time zone 'America/Sao_Paulo')
    union all
    select 'semana'::text, tipo_previsto, fase, esfera from base
  )
  select periodo, 'total'::text, 'total'::text, count(*) from per group by periodo
  union all select periodo, 'esfera', esfera, count(*) from per group by periodo, esfera
  union all select periodo, 'instrumento', coalesce(tipo_previsto,'Indefinido'), count(*) from per group by periodo, tipo_previsto
  union all select periodo, 'fase', coalesce(fase,'(sem fase)'), count(*) from per group by periodo, fase;
$function$;
