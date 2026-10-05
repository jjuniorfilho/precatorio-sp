-- FOR-199 — expõe a categorização de erros do FOR-198 (crawler_queue.erro_categoria e
-- pagamentos_consultas_log.erro_categoria) na tela /admin/coleta. Só leitura: nenhuma
-- migration de schema aqui — coluna + CHECK já estão em produção desde o FOR-198.
--
-- 2 funções NOVAS (nomes nunca usados antes) — CREATE OR REPLACE direto, sem DROP, re-executável.
-- Aplicar no SQL Editor do banco que o /admin lê (mesmo banco do worker-crawler).

-- 1) Fila do crawler e-SAJ: breakdown dos erros ATUAIS (status='erro') por categoria.
-- Mesma forma/mesmo padrão de public.crawler_queue_status_counts (sql/2026-07-24_for108_...):
-- `language sql stable security definer`, sem filtro de tempo (estado atual da fila, não
-- janela) — o admin roda anônimo, RLS/GRANT bloqueiam SELECT direto (memória admin-anon-rpc).
-- erro_categoria NULL (erro anterior ao FOR-198, nunca classificado) sai como NULL — o
-- frontend mapeia pra "Não classificado"; não é a mesma coisa que a categoria 'outro'.
create or replace function public.crawler_queue_erro_categoria_counts()
returns table(erro_categoria text, n bigint)
language sql stable security definer set search_path = public
as $function$
  select erro_categoria, count(*)
    from crawler_queue
   where status = 'erro'
   group by erro_categoria;
$function$;

grant execute on function public.crawler_queue_erro_categoria_counts() to anon, authenticated;

-- 2) Consultas de pagamento (TJSP): total/sucesso/falhas das últimas 24h + breakdown de falhas
-- por categoria. Retorna jsonb (mesmo padrão de public.listar_consultas_pagamento,
-- sql/2026-09-25_for171_3_...) porque mistura escalares (total/sucesso/falhas) com um array
-- (breakdown) — `table(...)` obrigaria denormalizar os escalares em cada linha do array.
-- Janela de 24h hardcoded sobre `iniciada_em` (mesmo padrão "sem parâmetro" de
-- public.crawler_ritmo_processamento, que também não parametriza a janela).
-- "sucesso" = resultado <> 'falha' (encontrado/nao_consta são consulta tecnicamente
-- bem-sucedida mesmo quando o processo "não consta"; só 'falha' é falha técnica — mesma
-- semântica de frontend/src/lib/consultas-pagamento.ts::RESULTADO_LABEL).
create or replace function public.pagamentos_consultas_resumo()
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
  v_total   bigint;
  v_sucesso bigint;
  v_falhas  bigint;
  v_por_categoria jsonb;
begin
  select count(*),
         count(*) filter (where resultado <> 'falha'),
         count(*) filter (where resultado = 'falha')
    into v_total, v_sucesso, v_falhas
    from pagamentos_consultas_log
   where iniciada_em >= now() - interval '24 hours';

  select coalesce(jsonb_agg(jsonb_build_object('erro_categoria', erro_categoria, 'n', n)), '[]'::jsonb)
    into v_por_categoria
    from (
      select erro_categoria, count(*) as n
        from pagamentos_consultas_log
       where iniciada_em >= now() - interval '24 hours'
         and resultado = 'falha'
       group by erro_categoria
    ) t;

  return jsonb_build_object(
    'total', coalesce(v_total, 0),
    'sucesso', coalesce(v_sucesso, 0),
    'falhas', coalesce(v_falhas, 0),
    'falhas_por_categoria', v_por_categoria
  );
end;
$$;

-- Mesmo grant de public.listar_consultas_pagamento (tabela tem RLS ligado, sem GRANT direto
-- pra anon/authenticated — acesso só via RPC security definer).
revoke all on function public.pagamentos_consultas_resumo() from public;
grant execute on function public.pagamentos_consultas_resumo() to anon, authenticated, service_role;

notify pgrst, 'reload schema';
