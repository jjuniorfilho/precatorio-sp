-- FOR-194: corrige timeout (57014) em partes_passivas_mais_comuns, usada pelo combobox
-- "Ente devedor" em /admin/processo-incidente.
--
-- Causa raiz: NÃO é bug de plano de execução (diferente do FOR-189) — é custo genuíno.
-- `partes` tem 1.521.464 linhas, 641.774 são papel='passiva' com nome preenchido,
-- agregando em só 13.399 nomes distintos. `count(distinct processo_id)` por grupo exige
-- tocar todas as ~642k linhas toda vez que a RPC é chamada (confirmado: sempre ~8,3s,
-- bate com o limite de statement_timeout da role authenticated), sem cache nenhum —
-- rodava a cada carregamento da tela.
--
-- Correção: mesmo padrão já em produção para mv_resumo_descobertas (refresh via pg_cron
-- a cada 15min) — materializar o resultado (pequeno: 13.399 linhas) numa MV, e trocar a
-- RPC pra só ler dela com ORDER BY + LIMIT. O ranking de "devedores mais comuns" não muda
-- minuto a minuto; um refresh periódico é mais que suficiente.
--
-- Aplicar no SQL Editor, na ordem abaixo (não dá pra fazer tudo num bloco só por causa do
-- CREATE MATERIALIZED VIEW). Re-executável (CREATE OR REPLACE / IF NOT EXISTS onde dá).

-- 1) A materialized view em si — mesma query que já existia na RPC, sem o LIMIT (guarda
--    todos os 13.399 nomes distintos; a RPC aplica o LIMIT depois, na leitura, que é
--    barata contra uma tabela desse tamanho).
drop materialized view if exists public.mv_partes_passivas_mais_comuns;
create materialized view public.mv_partes_passivas_mais_comuns as
  select pp.nome, count(distinct pp.processo_id) as n_processos
    from public.partes pp
    join public.processos p on p.id = pp.processo_id
   where pp.papel = 'passiva' and pp.nome is not null and p.flag_sp
   group by pp.nome;

-- Índice único exigido por REFRESH MATERIALIZED VIEW CONCURRENTLY (evita lock de leitura
-- durante o refresh, mesmo padrão de mv_resumo_descobertas).
create unique index if not exists idx_mv_partes_passivas_mais_comuns_nome
  on public.mv_partes_passivas_mais_comuns (nome);

-- Suporta o ORDER BY n_processos desc da RPC sem precisar de sort completo (13k linhas é
-- pouco, mas não custa nada).
create index if not exists idx_mv_partes_passivas_mais_comuns_n_processos
  on public.mv_partes_passivas_mais_comuns (n_processos desc);

-- Só o service_role lê a MV diretamente — acesso de verdade é via a RPC security definer
-- abaixo (mesmo padrão de leads_processos/FOR-177, evita exposição acidental via PostgREST
-- por grant default a PUBLIC).
revoke all on public.mv_partes_passivas_mais_comuns from public, anon, authenticated;
grant select on public.mv_partes_passivas_mais_comuns to service_role;

-- 2) Função de refresh, mesmo estilo de refresh_mv_resumo_descobertas.
create or replace function public.refresh_mv_partes_passivas_mais_comuns()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  refresh materialized view concurrently public.mv_partes_passivas_mais_comuns;
end;
$function$;

-- 3) Cron a cada 15min, mesma cadência de refresh-mv-resumo-descobertas.
select cron.schedule(
  'refresh-mv-partes-passivas-mais-comuns',
  '*/15 * * * *',
  $$select public.refresh_mv_partes_passivas_mais_comuns();$$
);

-- 4) A RPC agora só lê da MV (rápido: 13.399 linhas, ORDER BY + LIMIT) em vez de agregar
--    ao vivo. Mesma assinatura exata (sem risco de duplicar overload).
create or replace function public.partes_passivas_mais_comuns(p_limit integer default 10)
returns table(nome text, n_processos bigint)
language sql
stable
security definer
set search_path to 'public'
as $function$
  select mv.nome, mv.n_processos
    from public.mv_partes_passivas_mais_comuns mv
   order by mv.n_processos desc
   limit greatest(p_limit, 1);
$function$;

-- 5) Primeiro refresh manual (a MV nasce vazia até o primeiro REFRESH — sem isso a RPC
--    devolveria 0 linhas até o cron rodar pela 1ª vez, até 15min depois de aplicar).
--    REFRESH CONCURRENTLY exige que a MV já tenha sido populada ao menos uma vez sem
--    CONCURRENTLY (índice único só é útil depois disso) — como ela acabou de ser criada
--    via CREATE MATERIALIZED VIEW AS (já populada de cara, não vazia), um refresh
--    concurrently direto já funciona.
select public.refresh_mv_partes_passivas_mais_comuns();
