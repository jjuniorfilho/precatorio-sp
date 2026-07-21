-- FOR-70/74 — DEPRE (.0500) por número: persistir publicações DJEN .0500 e relacionar
-- o saldo aos incidentes pelo número (numero_depre = precatorios.processo_depre).
-- Aplicar no SQL Editor.

-- 1) Registro das publicações DJEN de precatório (.0500). Não são champeáveis no cpopg;
--    ficam aqui para relacionar quando um incidente crawleado referenciar o mesmo número.
create table if not exists public.djen_depre (
  id                    bigint generated always as identity primary key,
  cnj                   text not null,
  cnj_normalizado       text not null unique,
  numero_processo       text,
  link                  text,
  nome_orgao            text,
  nome_classe           text,
  data_disponibilizacao date,
  created_at            timestamptz not null default now()
);
alter table public.djen_depre enable row level security;
drop policy if exists djen_depre_authenticated_all on public.djen_depre;
create policy djen_depre_authenticated_all on public.djen_depre
  for all to authenticated using (true) with check (true);

-- (recomendado) índice para o join do saldo, se ainda não existir:
create index if not exists idx_precatorios_processo_depre on public.precatorios (processo_depre);

-- 2) Detalhe do processo: relaciona o saldo por incidente via numero_depre.
--    Cada incidente ganha saldo_depre / depre_status / depre_valor_pago quando o
--    numero_depre casa com precatorios.processo_depre (senão, null = "sem saldo").
create or replace function public.buscar_processo_detalhe(p_incidente_id uuid)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with raiz as (
    select pr.id as processo_id
    from public.incidentes i
    join public.processos pr on pr.id = i.processo_id
    where i.id = p_incidente_id
  ),
  incs as (
    select id from public.incidentes where processo_id = (select processo_id from raiz)
  )
  select jsonb_build_object(
    'processo',     (select to_jsonb(pr) from public.processos pr where pr.id = (select processo_id from raiz)),
    'cumprimentos', coalesce((select jsonb_agg(to_jsonb(c))
                     from public.cumprimentos c where c.processo_id = (select processo_id from raiz)), '[]'::jsonb),
    'incidentes',   coalesce((select jsonb_agg(
                       to_jsonb(i) || jsonb_build_object(
                         'saldo_depre',      pc.saldo_depre,
                         'depre_status',     pc.status,
                         'depre_valor_pago', pc.valor_pago
                       ))
                     from public.incidentes i
                     left join public.precatorios pc on pc.processo_depre = i.numero_depre
                     where i.processo_id = (select processo_id from raiz)), '[]'::jsonb),
    'partes',       coalesce((select jsonb_agg(jsonb_build_object(
                       'id', pt.id, 'incidente_id', pt.incidente_id, 'papel', pt.papel,
                       'nome', pt.nome, 'advogado_nome', pt.advogado_nome, 'oab', pt.oab))
                     from public.partes pt where pt.incidente_id in (select id from incs)), '[]'::jsonb),
    'andamentos',   coalesce((select jsonb_agg(to_jsonb(a) order by a.data desc nulls last)
                     from public.andamentos a where a.incidente_id in (select id from incs)), '[]'::jsonb)
  );
$$;

grant execute on function public.buscar_processo_detalhe(uuid) to anon, authenticated;
