-- FOR-70 — /admin/coleta é anônima e lê direto coleta_runs/coleta_config/djen_dias/
-- crawler_queue (RLS bloqueava → painel vazio). Libera SELECT anon nessas tabelas
-- operacionais (sem dado pessoal — logs de coleta, config, status do dia, fila de CNJs).
-- NÃO libera escrita: o toggle de rotina (updateColetaConfig) e requeue seguem exigindo
-- credencial — escrita administrativa deve ficar atrás de auth real. Aplicar no SQL Editor.

do $$
declare t text;
begin
  foreach t in array array['coleta_runs','coleta_config','djen_dias','crawler_queue'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_anon_select', t);
    execute format('create policy %I on public.%I for select to anon, authenticated using (true)', t || '_anon_select', t);
  end loop;
end $$;
