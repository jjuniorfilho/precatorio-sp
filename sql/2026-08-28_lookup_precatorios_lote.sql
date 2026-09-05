-- Consulta ad-hoc: dado um lote de números de processo .0500 (depre_process_number),
-- identifica se cada um está na base (incidentes/precatorios) e traz o ano_oc (ano de ordem
-- cronológica) de cada um. Usado só pra gerar um relatório pontual (planilha) — RPC fica
-- disponível pra reuso futuro do mesmo tipo de conferência, mesmo padrão de
-- security definer + grant anon já usado em todas as outras RPCs de leitura do projeto
-- (RLS bloqueia SELECT direto nessas tabelas pro client público).
--
-- numero_depre NÃO é único em incidentes (achado real do FOR-143) — por isso o rn/row_number
-- abaixo, preferindo sempre o match direto por cnj_normalizado (a própria linha .0500) antes
-- de cair pro match por numero_depre.
--
-- Aplicar no SQL Editor.

create or replace function public.lookup_precatorios_lote(p_numeros text[])
returns table(
  numero_informado text,
  numero_normalizado text,
  existe_incidente boolean,
  existe_precatorio boolean,
  incidente_cnj text,
  incidente_numero_depre text,
  macrofase text,
  fase text,
  status text,
  ano_oc integer,
  data_oficio_expedido date,
  valor_acao bigint,
  saldo_depre bigint,
  valor_pago bigint,
  dt_ensejo_ordem date
)
language sql stable security definer set search_path = public
as $$
  with entrada as (
    select distinct numero_informado, regexp_replace(numero_informado, '\D', '', 'g') as numero_normalizado
      from unnest(p_numeros) as numero_informado
  ),
  -- MATERIALIZED força o Postgres a computar isso 1 única vez (1 scan de incidentes,
  -- ~305k linhas). Sem isso, o planner não sabe a cardinalidade real de unnest(p_numeros)
  -- em tempo de plano e pode escolher um nested loop que reavalia esta normalização POR
  -- ITEM da lista (2000+ full scans em vez de 1) — foi isso que estourou o statement
  -- timeout nas duas primeiras versões desta função.
  incidentes_norm as materialized (
    select id, cnj, numero_depre, macrofase, fase, status, ano_oc, data_oficio_expedido, valor_acao,
           cnj_normalizado, regexp_replace(coalesce(numero_depre, ''), '\D', '', 'g') as numero_depre_norm
      from incidentes
  ),
  -- Dois joins de igualdade separados (em vez de 1 join com OR) — cada um é um hash join
  -- limpo contra incidentes_norm já materializada.
  por_cnj as (
    select n.numero_normalizado, i.id, i.cnj, i.numero_depre, i.macrofase, i.fase, i.status,
           i.ano_oc, i.data_oficio_expedido, i.valor_acao, 0 as prioridade
      from entrada n
      join incidentes_norm i on i.cnj_normalizado = n.numero_normalizado
  ),
  por_depre as (
    select n.numero_normalizado, i.id, i.cnj, i.numero_depre, i.macrofase, i.fase, i.status,
           i.ano_oc, i.data_oficio_expedido, i.valor_acao, 1 as prioridade
      from entrada n
      join incidentes_norm i on i.numero_depre_norm = n.numero_normalizado and i.numero_depre is not null
  ),
  inc as (
    select *, row_number() over (partition by numero_normalizado order by prioridade, id) as rn
      from (select * from por_cnj union all select * from por_depre) u
  )
  select e.numero_informado, e.numero_normalizado,
         inc.id is not null as existe_incidente,
         pr.processo_depre is not null as existe_precatorio,
         inc.cnj as incidente_cnj, inc.numero_depre as incidente_numero_depre,
         inc.macrofase, inc.fase, inc.status, inc.ano_oc, inc.data_oficio_expedido, inc.valor_acao,
         pr.saldo_depre, pr.valor_pago, pr.dt_ensejo_ordem
    from entrada e
    left join inc on inc.numero_normalizado = e.numero_normalizado and inc.rn = 1
    left join precatorios pr on pr.processo_depre = e.numero_informado;
$$;

grant execute on function public.lookup_precatorios_lote(text[]) to anon, authenticated;

-- Verificação (rodar após aplicar) — troque pelo seu processo_depre real:
-- select * from lookup_precatorios_lote(array['0015141-02.2020.8.26.0053']);
