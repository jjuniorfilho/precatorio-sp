-- FOR-112 — "Ordem Cronológica (OC)" deixa de ser extraída crua do texto do andamento
-- (regex `(20\d{2})` ou ano do andamento — impreciso e incompleto) e passa a ser
-- CALCULADA a partir da data de expedição do ofício requisitório, contra a tabela de
-- janelas legais da issue (Regra Geral Anterior → Transição EC 113/114 → EC 113/114 →
-- Transição EC 136/2025 → Nova Regra EC 136/2025).
--
-- A data de expedição do ofício (`d_oficio`) já era calculada dentro do CTE `match` de
-- classify_processo/classify_incidentes, independente da fase atual do incidente (não
-- precisa de query nova) — só nunca tinha sido persistida como coluna própria, e só era
-- usada pra fase_desde quando fase='oficio' (perdida assim que o incidente avança pra
-- fase='oc'). Agora persiste em `data_oficio_expedido`, sempre, e `ano_oc` vira
-- calcular_oc(data_oficio_expedido) — nulo enquanto o ofício não foi expedido.
--
-- Aplicar no SQL Editor. Depois de aplicar, é preciso reclassificar em massa (script
-- externo, ver worker-crawler ou instruções da sessão — NÃO rodar select classify_all()
-- direto aqui, mesma ressalva do fix FOR-72: ~88k processos numa transação só estoura).

-- -------------------------------------------------------------
-- 1) calcular_oc — lookup puro contra a tabela de janelas legais, sem acesso a banco.
-- -------------------------------------------------------------
create or replace function public.calcular_oc(p_data date)
returns integer
language sql immutable as $function$
  select case
    when p_data is null then null
    when p_data between '2013-07-02' and '2014-07-01' then 2015
    when p_data between '2014-07-02' and '2015-07-01' then 2016
    when p_data between '2015-07-02' and '2016-07-01' then 2017
    when p_data between '2016-07-02' and '2017-07-01' then 2018
    when p_data between '2017-07-02' and '2018-07-01' then 2019
    when p_data between '2018-07-02' and '2019-07-01' then 2020
    when p_data between '2019-07-02' and '2020-07-01' then 2021
    when p_data between '2020-07-02' and '2021-07-01' then 2022
    when p_data between '2021-07-02' and '2022-04-02' then 2023
    when p_data between '2022-04-03' and '2023-04-02' then 2024
    when p_data between '2023-04-03' and '2024-04-02' then 2025
    when p_data between '2024-04-03' and '2025-04-02' then 2026
    when p_data between '2025-04-03' and '2026-02-01' then 2027
    when p_data between '2026-02-02' and '2027-02-01' then 2028
    when p_data between '2027-02-02' and '2028-02-01' then 2029
    else null -- fora da tabela de janelas conhecida (anterior a 2013 ou futuro ainda não normatizado)
  end;
$function$;

-- -------------------------------------------------------------
-- 2) incidentes: coluna nova + índice pro filtro por ano_oc.
-- -------------------------------------------------------------
alter table incidentes
  add column if not exists data_oficio_expedido date;

create index if not exists idx_incidentes_ano_oc on public.incidentes (ano_oc);

-- -------------------------------------------------------------
-- 3) classify_processo — troca o bloco de ano_oc (regex sobre texto do andamento) por
--    data_oficio_expedido + calcular_oc(data_oficio_expedido). Resto da função inalterado.
-- -------------------------------------------------------------
create or replace function classify_processo(p_processo_id UUID)
returns void
language plpgsql security definer set search_path = public as $$
declare
  v_ttl int;
begin
  select coalesce((params->>'ttl_dias')::int, 7) into v_ttl
    from coleta_config where rotina = 'crawler_esaj';
  v_ttl := coalesce(v_ttl, 7);

  with match as (
    select i.id as incidente_id,
           i.tipo_previsto,
           (i.numero_depre is not null) as has_depre,
           bool_or(r.flag = 'calculo_homologado')   as f_calc,
           bool_or(r.flag = 'incidente_instaurado') as f_incidente,
           bool_or(r.flag = 'termo_declaracao')     as f_termo,
           bool_or(r.flag = 'oficio_deferido')      as f_deferido,
           bool_or(r.flag = 'oficio_expedido')      as f_oficio,
           bool_or(r.flag = 'ordem_cronologica')    as f_oc,
           bool_or(r.flag = 'possivelmente_pago')   as f_pago,
           max(a.data) filter (where r.flag = 'calculo_homologado')   as d_calc,
           max(a.data) filter (where r.flag = 'incidente_instaurado') as d_incidente,
           max(a.data) filter (where r.flag = 'termo_declaracao')     as d_termo,
           max(a.data) filter (where r.flag = 'oficio_deferido')      as d_deferido,
           max(a.data) filter (where r.flag = 'oficio_expedido')      as d_oficio,
           max(a.data) filter (where r.flag = 'ordem_cronologica')    as d_oc
      from incidentes i
      left join andamentos a on a.incidente_id = i.id
      left join classificacao_regras r
        on r.ativo
       and ( (r.tipo = 'ilike' and a.descricao ilike r.padrao)
          or (r.tipo = 'regex' and a.descricao ~* r.padrao) )
     where i.processo_id = p_processo_id
     group by i.id, i.tipo_previsto, i.numero_depre
  )
  update incidentes i set
    calculo_homologado   = coalesce(m.f_calc,      false),
    incidente_instaurado = coalesce(m.f_incidente, false),
    termo_declaracao      = coalesce(m.f_termo,    false),
    oficio_deferido        = coalesce(m.f_deferido, false),
    oficio_expedido        = coalesce(m.f_oficio,   false),
    ordem_cronologica      = coalesce(m.f_oc,       false),
    possivelmente_pago     = coalesce(m.f_pago,     false),
    fase = case
             when coalesce(m.f_oc,       false) then 'oc'
             when coalesce(m.f_oficio,   false) then 'oficio'
             when m.has_depre                   then 'depre'
             when coalesce(m.f_deferido, false) then 'oficio_deferido'
             when coalesce(m.f_termo,    false) then 'termo'
             when coalesce(m.f_incidente,false) or i.tipo_previsto <> 'Indefinido' then 'incidente'
             when coalesce(m.f_calc,     false) then 'calculo'
             else 'inicial'
           end,
    fase_desde = case
             when coalesce(m.f_oc,       false) then m.d_oc
             when coalesce(m.f_oficio,   false) then m.d_oficio
             when m.has_depre                   then null
             when coalesce(m.f_deferido, false) then m.d_deferido
             when coalesce(m.f_termo,    false) then m.d_termo
             when coalesce(m.f_incidente,false) then m.d_incidente
             when i.tipo_previsto <> 'Indefinido' then null
             when coalesce(m.f_calc,     false) then m.d_calc
             else null
           end,
    macrofase = case
                  when coalesce(m.f_oficio,false) and i.tipo_previsto = 'RPV'        then 'rpv_efetivo'
                  when coalesce(m.f_oficio,false) and i.tipo_previsto = 'Precatorio' then 'precatorio_efetivo'
                  else 'direito_creditorio'
                end,
    elegivel = coalesce(m.f_termo,false) and not coalesce(m.f_pago,false),
    data_oficio_expedido = m.d_oficio,
    ano_oc = calcular_oc(m.d_oficio),
    updated_at = now()
  from match m
  where m.incidente_id = i.id;

  update processos
     set next_crawl_at = coalesce(last_crawled_at, now()) + (v_ttl || ' days')::interval,
         updated_at = now()
   where id = p_processo_id;
end; $$;

-- -------------------------------------------------------------
-- 4) classify_incidentes — mesma troca, versão em lote (FOR-72 fix, mega-processos).
-- -------------------------------------------------------------
create or replace function classify_incidentes(p_incidente_ids UUID[])
returns void
language plpgsql security definer set search_path = public as $$
begin
  with match as (
    select i.id as incidente_id,
           i.tipo_previsto,
           (i.numero_depre is not null) as has_depre,
           bool_or(r.flag = 'calculo_homologado')   as f_calc,
           bool_or(r.flag = 'incidente_instaurado') as f_incidente,
           bool_or(r.flag = 'termo_declaracao')     as f_termo,
           bool_or(r.flag = 'oficio_deferido')      as f_deferido,
           bool_or(r.flag = 'oficio_expedido')      as f_oficio,
           bool_or(r.flag = 'ordem_cronologica')    as f_oc,
           bool_or(r.flag = 'possivelmente_pago')   as f_pago,
           max(a.data) filter (where r.flag = 'calculo_homologado')   as d_calc,
           max(a.data) filter (where r.flag = 'incidente_instaurado') as d_incidente,
           max(a.data) filter (where r.flag = 'termo_declaracao')     as d_termo,
           max(a.data) filter (where r.flag = 'oficio_deferido')      as d_deferido,
           max(a.data) filter (where r.flag = 'oficio_expedido')      as d_oficio,
           max(a.data) filter (where r.flag = 'ordem_cronologica')    as d_oc
      from incidentes i
      left join andamentos a on a.incidente_id = i.id
      left join classificacao_regras r
        on r.ativo
       and ( (r.tipo = 'ilike' and a.descricao ilike r.padrao)
          or (r.tipo = 'regex' and a.descricao ~* r.padrao) )
     where i.id = any(p_incidente_ids)
     group by i.id, i.tipo_previsto, i.numero_depre
  )
  update incidentes i set
    calculo_homologado   = coalesce(m.f_calc,      false),
    incidente_instaurado = coalesce(m.f_incidente, false),
    termo_declaracao      = coalesce(m.f_termo,    false),
    oficio_deferido        = coalesce(m.f_deferido, false),
    oficio_expedido        = coalesce(m.f_oficio,   false),
    ordem_cronologica      = coalesce(m.f_oc,       false),
    possivelmente_pago     = coalesce(m.f_pago,     false),
    fase = case
             when coalesce(m.f_oc,       false) then 'oc'
             when coalesce(m.f_oficio,   false) then 'oficio'
             when m.has_depre                   then 'depre'
             when coalesce(m.f_deferido, false) then 'oficio_deferido'
             when coalesce(m.f_termo,    false) then 'termo'
             when coalesce(m.f_incidente,false) or i.tipo_previsto <> 'Indefinido' then 'incidente'
             when coalesce(m.f_calc,     false) then 'calculo'
             else 'inicial'
           end,
    fase_desde = case
             when coalesce(m.f_oc,       false) then m.d_oc
             when coalesce(m.f_oficio,   false) then m.d_oficio
             when m.has_depre                   then null
             when coalesce(m.f_deferido, false) then m.d_deferido
             when coalesce(m.f_termo,    false) then m.d_termo
             when coalesce(m.f_incidente,false) then m.d_incidente
             when i.tipo_previsto <> 'Indefinido' then null
             when coalesce(m.f_calc,     false) then m.d_calc
             else null
           end,
    macrofase = case
                  when coalesce(m.f_oficio,false) and i.tipo_previsto = 'RPV'        then 'rpv_efetivo'
                  when coalesce(m.f_oficio,false) and i.tipo_previsto = 'Precatorio' then 'precatorio_efetivo'
                  else 'direito_creditorio'
                end,
    elegivel = coalesce(m.f_termo,false) and not coalesce(m.f_pago,false),
    data_oficio_expedido = m.d_oficio,
    ano_oc = calcular_oc(m.d_oficio),
    updated_at = now()
  from match m
  where m.incidente_id = i.id;
end; $$;

grant execute on function classify_incidentes(UUID[]) to service_role, authenticated;

-- -------------------------------------------------------------
-- 5) listar_processos_para_reclassificar — paginação por keyset (id > cursor) pro script
--    externo de reclassificação em massa. RPC porque SELECT direto em `processos` também
--    esbarra em RLS pro role que o worker usa (anon+login admin, sem service_role na VPS —
--    mesmo motivo de listar_incidentes_para_refresh).
-- -------------------------------------------------------------
create or replace function public.listar_processos_para_reclassificar(
  p_cursor uuid default '00000000-0000-0000-0000-000000000000', p_limit integer default 500)
returns table(processo_id uuid)
language sql stable security definer set search_path = public
as $function$
  select p.id
    from processos p
   where p.flag_sp
     and p.id > p_cursor
   order by p.id
   limit greatest(p_limit, 1);
$function$;

grant execute on function public.listar_processos_para_reclassificar(uuid, integer) to anon, authenticated;
