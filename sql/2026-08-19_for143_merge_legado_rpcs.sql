-- FOR-143 — RPCs de merge pra reconciliação LEGADO→real (fix do C2 do code review: renomear
-- processo_codigo de uma linha LEGADO- pro código real, sem checar se esse código já existe
-- noutra linha, estoura unique violation e quebra o crawl de um processo não-relacionado).
--
-- merge_legado_processo: quando já existe uma linha REAL (não-LEGADO) pro mesmo cnj_normalizado
-- (import criou um placeholder duplicado, ou o crawler descobriu o CNJ organicamente enquanto o
-- import ainda não tinha rodado essa linha), reaponta incidentes/partes pro processo real e
-- apaga a linha LEGADO- (em vez de tentar renomeá-la, que colidiria com o processo_codigo real).
create or replace function public.merge_legado_processo(p_legado_id uuid, p_real_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_id = p_real_id then return; end if;
  update incidentes set processo_id = p_real_id where processo_id = p_legado_id;
  update partes     set processo_id = p_real_id where processo_id = p_legado_id;
  delete from processos where id = p_legado_id;
end; $$;

-- merge_legado_incidente: mesma ideia pro incidente. numero_depre não é único (confirmado em
-- produção) — dois incidentes de processos diferentes podem compartilhar o mesmo numero_depre.
-- Se já existe uma linha REAL com o processo_codigo de destino, descarta a linha LEGADO- (e-SAJ
-- prevalece: partes/andamentos do incidente real vêm do crawl que disparou este merge).
create or replace function public.merge_legado_incidente(p_legado_id uuid, p_real_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if p_legado_id = p_real_id then return; end if;
  delete from partes     where incidente_id = p_legado_id;
  delete from andamentos where incidente_id = p_legado_id;
  delete from incidentes where id = p_legado_id;
end; $$;

grant execute on function public.merge_legado_processo(uuid, uuid)  to service_role, authenticated;
grant execute on function public.merge_legado_incidente(uuid, uuid) to service_role, authenticated;

-- Verificação (rodar manualmente após aplicar):
-- select proname, prosecdef from pg_proc where proname in ('merge_legado_processo','merge_legado_incidente');
