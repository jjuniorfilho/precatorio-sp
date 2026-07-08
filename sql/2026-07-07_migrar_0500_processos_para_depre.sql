-- FOR-70 — Migração: mover os processos .0500 gravados ERRADO como principal para a
-- tabela DEPRE (djen_depre) e removê-los de `processos`. Nenhum .0500 é principal.
-- Pré-requisito: aplicar antes 2026-07-07_depre_requisitorio_ficha.sql.
--
-- ⚠️ DESTRUTIVO. Rode a seção 1 (DRY-RUN) primeiro e confira os números. Só então
--    rode a seção 2 (dentro de BEGIN/COMMIT). Ideal: fazer backup/snapshot antes.

-- Alvo: processos cujo CNJ é um requisitório .0500 (J=8, TR=26, OOOO=0500).
--   ex.: 0014874-52.2017.8.26.0500  → cnj_normalizado termina em 8260500.

------------------------------------------------------------------------
-- SEÇÃO 1 — DRY-RUN (apenas SELECT; não altera nada)
------------------------------------------------------------------------
-- 1a) Quantos processos .0500 errados existem
select count(*) as processos_0500
from public.processos
where cnj ~ '\.8\.26\.0500$';

-- 1b) Amostra (confira que são todos requisitórios .0500)
select p.id, p.cnj, p.classe, p.status, p.valor_acao,
       (select count(*) from public.incidentes i where i.processo_id = p.id) as n_incidentes,
       (select count(*) from public.andamentos a
          join public.incidentes i on i.id = a.incidente_id where i.processo_id = p.id) as n_andamentos
from public.processos p
where p.cnj ~ '\.8\.26\.0500$'
order by p.valor_acao desc nulls last
limit 30;

------------------------------------------------------------------------
-- SEÇÃO 2 — MIGRAÇÃO (transação). Descomente e rode após validar a seção 1.
------------------------------------------------------------------------
-- begin;

-- with alvo as (
--   select p.id as processo_id, p.cnj, regexp_replace(p.cnj,'\D','','g') as cnj_norm,
--          p.classe, p.status, p.valor_acao, p.data_base
--     from public.processos p
--    where p.cnj ~ '\.8\.26\.0500$'
-- ),
-- passiva as (  -- ente devedor (primeira parte passiva do processo)
--   select distinct on (pt.processo_id) pt.processo_id, pt.nome
--     from public.partes pt
--    where pt.papel = 'passiva'
--    order by pt.processo_id, pt.id
-- ),
-- movs as (     -- andamentos agregados em jsonb
--   select i.processo_id,
--          jsonb_agg(jsonb_build_object('data', a.data, 'descricao', a.descricao,
--                                       'arquivo_url', a.arquivo_url)
--                    order by a.data) as andamentos
--     from public.andamentos a
--     join public.incidentes i on i.id = a.incidente_id
--    where i.processo_id in (select processo_id from alvo)
--    group by i.processo_id
-- )
-- insert into public.djen_depre
--   (cnj, cnj_normalizado, valor_acao, status, classe, data_base, devedora, andamentos, ficha_crawled_at)
-- select al.cnj, al.cnj_norm, al.valor_acao, al.status, al.classe, al.data_base,
--        pa.nome, coalesce(mv.andamentos, '[]'::jsonb), now()
--   from alvo al
--   left join passiva pa on pa.processo_id = al.processo_id
--   left join movs    mv on mv.processo_id = al.processo_id
-- on conflict (cnj_normalizado) do update set
--   valor_acao       = coalesce(excluded.valor_acao, public.djen_depre.valor_acao),
--   status           = coalesce(excluded.status, public.djen_depre.status),
--   classe           = coalesce(excluded.classe, public.djen_depre.classe),
--   data_base        = coalesce(excluded.data_base, public.djen_depre.data_base),
--   devedora         = coalesce(excluded.devedora, public.djen_depre.devedora),
--   andamentos       = coalesce(excluded.andamentos, public.djen_depre.andamentos),
--   ficha_crawled_at = now();

-- -- remove os filhos e os processos .0500 (ordem por FK)
-- with alvo as (select id from public.processos where cnj ~ '\.8\.26\.0500$')
-- delete from public.andamentos a
--  using public.incidentes i
--  where a.incidente_id = i.id and i.processo_id in (select id from alvo);

-- delete from public.partes      where processo_id in (select id from public.processos where cnj ~ '\.8\.26\.0500$');
-- delete from public.incidentes  where processo_id in (select id from public.processos where cnj ~ '\.8\.26\.0500$');
-- delete from public.cumprimentos where processo_id in (select id from public.processos where cnj ~ '\.8\.26\.0500$');
-- delete from public.processos   where cnj ~ '\.8\.26\.0500$';

-- commit;

------------------------------------------------------------------------
-- SEÇÃO 3 — Verificação pós-migração
------------------------------------------------------------------------
-- select count(*) as processos_0500_restantes from public.processos where cnj ~ '\.8\.26\.0500$';  -- deve ser 0
-- select count(*) as depre_com_ficha from public.djen_depre where ficha_crawled_at is not null;
