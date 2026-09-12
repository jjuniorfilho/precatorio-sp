-- FOR-156 — vínculo reverso .0500 → incidente de origem por número de incidente.
--
-- Achado real (0003201-62.2017.8.26.0500, ver conversa): a ficha do requisitório traz
-- "Processo de Origem: 0410665-90.1996.8.26.0053/0001" — o sufixo "/0001" identifica QUAL
-- dos vários "Precatório - 0000X" da ação de origem gerou esse .0500. Sem esse sufixo, o
-- único jeito de ligar numero_depre era extractDepre() reachar o próprio .0500 na página
-- do incidente de origem — o que NUNCA acontece em processos de execução coletiva antiga
-- (o requisitório simplesmente não é citado lá, confirmado ao vivo pra esse caso: fase='oc'
-- nos 6 incidentes, numero_depre vazio nos 6). O worker (parse.ts/crawl.ts/supabase.ts)
-- agora captura esse sufixo e grava em djen_depre.origem_incidentes; esta função faz o
-- UPDATE reverso quando o CNJ de origem é (re)crawleado (chamada em index.ts logo após
-- persistTree+classifyProcesso). Aplicar no SQL Editor.

alter table public.djen_depre add column if not exists origem_incidentes jsonb;

create or replace function public.vincular_numero_depre_reverso(p_origem_cnj text, p_processo_id uuid)
returns integer
language plpgsql security definer set search_path = public
as $$
declare
  n int := 0;
begin
  with candidatos as (
    select d.cnj as numero_depre, (elem->>'numero_incidente') as numero_incidente
      from djen_depre d, jsonb_array_elements(d.origem_incidentes) elem
     where elem->>'cnj' = p_origem_cnj
  )
  update incidentes i
     set numero_depre = c.numero_depre
    from candidatos c
   where i.processo_id = p_processo_id
     and i.numero_depre is null
     and i.numero_incidente is not null
     and regexp_replace(i.numero_incidente, '\D', '', 'g') <> ''
     and regexp_replace(c.numero_incidente, '\D', '', 'g') <> ''
     and regexp_replace(i.numero_incidente, '\D', '', 'g')::int = regexp_replace(c.numero_incidente, '\D', '', 'g')::int;
  get diagnostics n = row_count;
  return n;
end;
$$;

grant execute on function public.vincular_numero_depre_reverso(text, uuid) to anon, authenticated, service_role;

-- Backfill: aplica retroativamente pros CNJs de origem que JÁ foram crawleados antes
-- dessa mudança existir (ex.: os 6 incidentes de 0410665-90.1996.8.26.0053, que já têm
-- processo_id mas nenhum origem_incidentes gravado ainda nesse momento — rodar de novo
-- depois que o worker reprocessar esses .0500 e persistRequisitorio gravar
-- origem_incidentes). Deixado como comentário porque não tem efeito até o próximo
-- crawlRequisitorio rodar pra cada .0500 pendente:
--
-- select public.vincular_numero_depre_reverso(origem_cnj, p.id)
--   from djen_depre d, jsonb_array_elements(d.origem_incidentes) elem
--   join processos p on p.cnj_normalizado = regexp_replace(elem->>'cnj', '\D', '', 'g')
--   cross join lateral (select elem->>'cnj' as origem_cnj) x;
