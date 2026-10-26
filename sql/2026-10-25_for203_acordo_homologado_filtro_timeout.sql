-- FOR-203 — filtro "Acordo homologado" em /admin/processo-incidente estourava timeout
-- (57014) com sim/nao: EXISTS contra djen_depre comparando regexp_replace(i.numero_depre)
-- por linha de incidentes, sem índice btree na expressão. Reescrito pra partir de
-- djen_depre (poucas linhas com acordo) e entrar em incidentes pelo btree de numero_depre.
--
-- Só _where_processo_incidente muda (mesma assinatura -> CREATE OR REPLACE, sem DROP);
-- buscar/contar a chamam e ficam intactas. Base = definição de
-- sql/2026-10-21_for202_rpcs_cessao_credito_enum.sql (capturada ao vivo em 2026-10-21).
--
-- Addendum (mesmo arquivo, re-executável): busca p_q com menos de 3 dígitos devolve vazio
-- (antes '%%' casava tudo -> timeout).
--
-- Premissa: incidentes.numero_depre está no formato 0000000-00.0000.0.00.0000. Conferir
-- antes/depois (deve dar 0 ou um número desprezível):
--   select count(*) from incidentes where numero_depre is not null
--      and numero_depre !~ '^\d{7}-\d{2}\.\d{4}\.\d\.\d{2}\.\d{4}$';
--
-- Índice: em tabela com carga, criar fora do horário dos refresh de MV. Se o SQL Editor
-- não aceitar CONCURRENTLY dentro de transação, rodar o CREATE INDEX sozinho.

create index if not exists idx_djen_depre_acordo_cnj
  on public.djen_depre (acordo_homologado, cnj_normalizado)
  where acordo_homologado is not null;

create or replace function public._where_processo_incidente(
  p_esfera text, p_tipo text, p_fase text, p_macrofase text, p_status text,
  p_valor_min bigint, p_valor_max bigint, p_elegivel boolean,
  p_fase_desde_de date, p_fase_desde_ate date, p_ano_oc integer,
  p_ente_devedor text, p_em_cumprimento boolean,
  p_q text, p_advogado text, p_oab text,
  p_crawler_data_de date default null, p_crawler_data_ate date default null,
  p_crawleado boolean default null,
  -- FOR-202: era boolean (3 valores de filtro, mas a coluna não distinguia "não
  -- verificado" de "não" — e o bloco que usava este parâmetro nem existia mais, ver
  -- nota no cabeçalho). Vira enum texto, mesmo padrão de p_acordo_homologado.
  p_cessao_credito text default null,
  p_acordo_homologado text default null
) returns text
language plpgsql
stable
as $function$
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
  -- FOR-202: coluna direta em incidentes, sem JOIN — nunca interpolado como literal na
  -- SQL dinâmica (resolvido em PL/pgSQL puro via IF/ELSIF, mesmo espírito defensivo do
  -- resto desta função); valor fora do enum esperado é no-op silencioso.
  if p_cessao_credito = 'sim' then
    v_where := v_where || ' and i.cessao_credito = true';
  elsif p_cessao_credito = 'nao' then
    v_where := v_where || ' and i.cessao_credito = false';
  elsif p_cessao_credito = 'nao_verificado' then
    v_where := v_where || ' and i.cessao_credito is null';
  end if;
  -- FOR-203: o filtro antigo comparava regexp_replace(i.numero_depre,...) com
  -- djen_depre.cnj_normalizado linha a linha de incidentes (sem btree na expressão) ->
  -- timeout 57014 com acordo=sim. Agora parte do lado pequeno (djen_depre, índice parcial
  -- idx_djen_depre_acordo_cnj) e entra em incidentes por idx_incidentes_numero_depre,
  -- reformatando cnj_normalizado (20 dígitos) pro formato com pontuação de numero_depre.
  if p_acordo_homologado = 'sim' then
    v_where := v_where || $sql$ and i.numero_depre in (
      select regexp_replace(d.cnj_normalizado, '^(\d{7})(\d{2})(\d{4})(\d)(\d{2})(\d{4})$', '\1-\2.\3.\4.\5.\6')
        from djen_depre d where d.acordo_homologado = true
    )$sql$;
  elsif p_acordo_homologado = 'nao' then
    v_where := v_where || $sql$ and i.numero_depre in (
      select regexp_replace(d.cnj_normalizado, '^(\d{7})(\d{2})(\d{4})(\d)(\d{2})(\d{4})$', '\1-\2.\3.\4.\5.\6')
        from djen_depre d where d.acordo_homologado = false
    )$sql$;
  elsif p_acordo_homologado = 'nao_verificado' then
    v_where := v_where || $sql$ and (
      i.numero_depre is null
      or i.numero_depre not in (
        select regexp_replace(d.cnj_normalizado, '^(\d{7})(\d{2})(\d{4})(\d)(\d{2})(\d{4})$', '\1-\2.\3.\4.\5.\6')
          from djen_depre d where d.acordo_homologado is not null
      )
    )$sql$;
  end if;
  if p_q is not null then
    v_digits := regexp_replace(p_q, '\D', '', 'g');
    v_pattern := '%' || v_digits || '%';
    -- FOR-203 (addendum): sem dígitos suficientes o padrão vira '%%' (casa com tudo) e a
    -- busca varre a base inteira -> timeout 57014 (ex.: q='abc'). Menos de 3 dígitos não
    -- identifica processo/DEPRE: devolve vazio em vez de varrer.
    if length(v_digits) < 3 then
      v_where := v_where || ' and false';
    else
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

-- Validação (SQL Editor, depois de aplicar):
-- select contar_processos_incidente(p_cessao_credito := 'nao', p_acordo_homologado := 'sim');
-- select count(*) from buscar_processos_incidente(p_cessao_credito := 'nao', p_acordo_homologado := 'sim');
