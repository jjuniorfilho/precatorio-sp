-- FOR-189: corrige timeout (57014) em buscar_processos_incidente/contar_processos_incidente
-- quando p_q está preenchido.
--
-- Causa raiz (confirmada via EXPLAIN ANALYZE em produção, read-only, 2026-10-01): o filtro
-- de p_q era montado como
--
--   and (
--     i.processo_id in (select ... from processos/cumprimentos ...)
--     or i.id in (select ... from incidentes ... numero_depre ...)
--   )
--
-- O Postgres NUNCA converte um OR entre dois IN(subquery) em semi-join — ele sempre avalia
-- como "SubPlan hasheado + filtro aplicado linha a linha", o que obriga a tocar as ~761 mil
-- linhas de `incidentes` inteiras pra aplicar o filtro, não importa a estratégia de scan
-- escolhida (confirmado com 3 planos distintos, todos "Rows Removed by Filter: ~761.8xx").
-- Os 3 índices GIN trigram que suportariam essa busca já existem
-- (idx_processos_cnj_normalizado_trgm, idx_cumprimentos_cnj_normalizado_trgm,
-- idx_incidentes_numero_depre_digits_trgm) — o problema nunca foi índice faltando, foi essa
-- forma específica de combinar os dois IN via OR.
--
-- Em `buscar_processos_incidente` (tem ORDER BY valor_acao LIMIT) isso é INTERMITENTE: o
-- planner aposta que vai achar LIMIT matches rápido escaneando em ordem de valor_acao — pra
-- buscas muito seletivas (ex.: 1 match em 761 mil, caso real do DEPRE legado
-- 0436868-90.2025.8.26.0500) a aposta falha e ele varre a tabela inteira em ordem de índice
-- (I/O aleatório) → 15,2s medidos. Em `contar_processos_incidente` (sem LIMIT) é sempre
-- lento quando p_q está ativo, não intermitente.
--
-- Correção: reescrever como um único IN sobre um UNION, em vez de OR entre dois INs.
-- Equivalência garantida por álgebra relacional (id é chave primária):
--
--   i.processo_id in A or i.id in B  <=>  i.id in ({x.id : x.processo_id in A} union B)
--
-- Prova: se i.processo_id ∈ A, então i.id está no conjunto à direita tomando x=i. Se i.id
-- está nesse conjunto, existe x com x.id=i.id e x.processo_id∈A — como id é PK, x=i, logo
-- i.processo_id∈A. Reescrita pura, sem mudança de semântica.
--
-- Validado em produção (read-only, mesma reescrita testada via EXPLAIN ANALYZE inline
-- antes de tocar a função):
--   - Caso real (1 match): 15.197ms -> 528ms (~29x). Diff de resultado = 0 linhas.
--   - Caso de múltiplos matches (5.639 linhas, padrão "20258260500" — bem mais amplo que
--     qualquer busca real de usuário): completa em 3,8s sem erro.
--
-- Muda só esta função. Mesma assinatura exata (21 parâmetros, mesmos nomes/tipos/defaults
-- da versão viva capturada em 2026-10-01_for189_baseline_where_processo_incidente_live.sql)
-- — CREATE OR REPLACE substitui no lugar, não cria overload novo (ver nota de processo no
-- arquivo de baseline sobre o incidente de PGRST203 causado por um overload acidental nesta
-- mesma função, nesta mesma sessão).

CREATE OR REPLACE FUNCTION public._where_processo_incidente(p_esfera text, p_tipo text, p_fase text, p_macrofase text, p_status text, p_valor_min bigint, p_valor_max bigint, p_elegivel boolean, p_fase_desde_de date, p_fase_desde_ate date, p_ano_oc integer, p_ente_devedor text, p_em_cumprimento boolean, p_q text, p_advogado text, p_oab text, p_crawler_data_de date DEFAULT NULL::date, p_crawler_data_ate date DEFAULT NULL::date, p_crawleado boolean DEFAULT NULL::boolean, p_cessao_credito boolean DEFAULT NULL::boolean, p_acordo_homologado text DEFAULT NULL::text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
declare
  v_where text := 'p.flag_sp';
  v_digits text;
  v_pattern text;
  v_advogado_norm text;
  v_oab_norm text;
begin
  if p_esfera is not null then
    v_where := v_where || format(' and p.ente_esfera = %L', p_esfera);
  end if;
  if p_tipo is not null then
    v_where := v_where || format(' and i.tipo_previsto = %L', p_tipo);
  end if;
  if p_fase is not null then
    v_where := v_where || format(' and i.fase = %L', p_fase);
  end if;
  if p_macrofase is not null then
    v_where := v_where || format(' and i.macrofase = %L', p_macrofase);
  end if;
  if p_status is not null then
    v_where := v_where || format(' and i.status = %L', p_status);
  end if;
  if p_valor_min is not null then
    v_where := v_where || format(
      $sql$ and least(i.valor_acao, (select max(pr.saldo_depre) from precatorios pr where pr.processo_depre = i.numero_depre)) >= %L::bigint$sql$,
      p_valor_min);
  end if;
  if p_valor_max is not null then
    v_where := v_where || format(
      $sql$ and least(i.valor_acao, (select max(pr.saldo_depre) from precatorios pr where pr.processo_depre = i.numero_depre)) <= %L::bigint$sql$,
      p_valor_max);
  end if;
  if p_elegivel is not null then
    v_where := v_where || format(' and i.elegivel = %L::boolean', p_elegivel);
  end if;
  if p_fase_desde_de is not null then
    v_where := v_where || format(' and i.fase_desde >= %L::date', p_fase_desde_de);
  end if;
  if p_fase_desde_ate is not null then
    v_where := v_where || format(' and i.fase_desde <= %L::date', p_fase_desde_ate);
  end if;
  if p_ano_oc is not null then
    v_where := v_where || format(' and i.ano_oc = %L::integer', p_ano_oc);
  end if;
  if p_ente_devedor is not null then
    v_where := v_where || format(
      $sql$ and i.processo_id in (select pp.processo_id from partes pp where pp.papel = 'passiva' and pp.nome = %L)$sql$,
      p_ente_devedor);
  end if;
  if p_em_cumprimento is not null then
    v_where := v_where || format(' and i.em_cumprimento_real = %L::boolean', p_em_cumprimento);
  end if;
  if p_crawler_data_de is not null then
    v_where := v_where || format(' and p.last_crawled_at >= %L::timestamptz', p_crawler_data_de);
  end if;
  if p_crawler_data_ate is not null then
    v_where := v_where || format(' and p.last_crawled_at < %L::timestamptz', (p_crawler_data_ate + 1));
  end if;
  if p_crawleado is not null then
    if p_crawleado then
      v_where := v_where || ' and p.last_crawled_at is not null';
    else
      v_where := v_where || ' and p.last_crawled_at is null';
    end if;
  end if;
  if p_acordo_homologado = 'sim' then
    v_where := v_where || $sql$ and i.numero_depre is not null and exists (
      select 1 from djen_depre d
       where d.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
         and d.acordo_homologado = true
    )$sql$;
  elsif p_acordo_homologado = 'nao' then
    v_where := v_where || $sql$ and i.numero_depre is not null and exists (
      select 1 from djen_depre d
       where d.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
         and d.acordo_homologado = false
    )$sql$;
  elsif p_acordo_homologado = 'nao_verificado' then
    v_where := v_where || $sql$ and (
      i.numero_depre is null
      or not exists (
        select 1 from djen_depre d
         where d.cnj_normalizado = regexp_replace(i.numero_depre, '\D', '', 'g')
           and d.acordo_homologado is not null
      )
    )$sql$;
  end if;
  if p_q is not null then
    v_digits := regexp_replace(p_q, '\D', '', 'g');
    v_pattern := '%' || v_digits || '%';
    -- FOR-189: era "i.processo_id in (...) OR i.id in (...)" — reescrito como um IN único
    -- sobre um UNION (ver explicação completa no cabeçalho do arquivo da migration).
    v_where := v_where || format(
      $sql$ and i.id in (
        select ii2.id
          from incidentes ii2
          join (
            select pp.id as processo_id from processos pp where pp.cnj_normalizado ilike %L
            union
            select ii.processo_id from incidentes ii
            join cumprimentos cc on cc.id = ii.cumprimento_id
             where cc.cnj_normalizado ilike %L
          ) mp on mp.processo_id = ii2.processo_id
        union
        select iii.id from incidentes iii
         where regexp_replace(coalesce(iii.numero_depre,''), '\D', '', 'g') ilike %L
      )$sql$,
      v_pattern, v_pattern, v_pattern);
  end if;
  if p_advogado is not null then
    v_advogado_norm := '%' || btrim(regexp_replace(replace(p_advogado, chr(160), ' '), '\s+', ' ', 'g')) || '%';
    v_where := v_where || format(
      $sql$ and exists (
        select 1 from partes a where a.incidente_id = i.id and a.papel='ativa'
          and btrim(regexp_replace(replace(a.advogado_nome, chr(160), ' '), '\s+', ' ', 'g')) ilike %L
      )$sql$,
      v_advogado_norm);
  end if;
  if p_oab is not null then
    v_oab_norm := upper(regexp_replace(p_oab, '[^0-9A-Za-z]', '', 'g'));
    v_where := v_where || format(
      $sql$ and exists (
        select 1 from partes a where a.incidente_id = i.id and a.papel='ativa' and a.oab_normalizada = %L
      )$sql$,
      v_oab_norm);
  end if;

  return v_where;
end;
$function$;
