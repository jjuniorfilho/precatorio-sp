-- FOR-74 — buscar_processos: exibir o CNJ da RAIZ quando o incidente não tem CNJ próprio.
-- Incidentes de RPV/Precatório no e-SAJ não trazem CNJ na folha; só o processo de
-- conhecimento (raiz) tem. Sem isto a lista cai no processo_codigo (código interno e-SAJ).
-- Mudanças vs. versão anterior:
--   1) coluna cnj = COALESCE(i.cnj, p.cnj)  (raiz)
--   2) busca (p_q) também casa pelo cnj_normalizado da raiz
-- Aplicar no SQL Editor.

CREATE OR REPLACE FUNCTION public.buscar_processos(p_q text DEFAULT NULL::text, p_esfera text DEFAULT NULL::text, p_tipo text DEFAULT NULL::text, p_fase text DEFAULT NULL::text, p_macrofase text DEFAULT NULL::text, p_advogado text DEFAULT NULL::text, p_oab text DEFAULT NULL::text, p_valor_min bigint DEFAULT NULL::bigint, p_elegivel boolean DEFAULT NULL::boolean, p_status text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(incidente_id uuid, processo_codigo text, cnj text, numero_incidente text, tipo_previsto text, numero_depre text, macrofase text, fase text, status text, valor_acao bigint, data_base date, ente_nome text, ente_esfera text, autor_nome text, advogados text, oabs text, elegivel boolean, total_count bigint)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH base AS (
    SELECT i.id AS incidente_id, i.processo_codigo, COALESCE(i.cnj, p.cnj) AS cnj,
           i.numero_incidente, i.tipo_previsto,
           i.numero_depre, i.macrofase, i.fase, i.status, i.valor_acao, i.data_base, i.elegivel,
           p.ente_nome, p.ente_esfera, p.cnj_normalizado AS p_cnj_norm
      FROM incidentes i
      JOIN processos p ON p.id = i.processo_id
     WHERE p.flag_sp
       AND (p_esfera    IS NULL OR p.ente_esfera = p_esfera)
       AND (p_tipo      IS NULL OR i.tipo_previsto = p_tipo)
       AND (p_fase      IS NULL OR i.fase = p_fase)
       AND (p_macrofase IS NULL OR i.macrofase = p_macrofase)
       AND (p_status    IS NULL OR i.status = p_status)
       AND (p_valor_min IS NULL OR i.valor_acao >= p_valor_min)
       AND (p_elegivel  IS NULL OR i.elegivel = p_elegivel)
       AND (p_q IS NULL OR i.cnj_normalizado ILIKE '%'||regexp_replace(p_q,'\D','','g')||'%'
            OR p.cnj_normalizado ILIKE '%'||regexp_replace(p_q,'\D','','g')||'%'
            OR EXISTS (SELECT 1 FROM partes d WHERE d.incidente_id = i.id
                        AND d.documento ILIKE '%'||regexp_replace(p_q,'\D','','g')||'%'))
       AND (p_advogado IS NULL OR EXISTS (SELECT 1 FROM partes a WHERE a.incidente_id = i.id
                        AND a.papel='ativa' AND a.advogado_nome ILIKE '%'||p_advogado||'%'))
       AND (p_oab IS NULL OR EXISTS (SELECT 1 FROM partes a WHERE a.incidente_id = i.id
                        AND a.papel='ativa' AND a.oab_normalizada = upper(regexp_replace(p_oab,'[^0-9A-Za-z]','','g'))))
  ),
  ag AS (
    SELECT b.*,
           (SELECT nome FROM partes WHERE incidente_id=b.incidente_id AND papel='ativa' AND nome IS NOT NULL LIMIT 1) AS autor_nome,
           (SELECT string_agg(DISTINCT advogado_nome, ', ') FROM partes WHERE incidente_id=b.incidente_id AND papel='ativa' AND advogado_nome IS NOT NULL) AS advogados,
           (SELECT string_agg(DISTINCT oab, ', ') FROM partes WHERE incidente_id=b.incidente_id AND papel='ativa' AND oab IS NOT NULL) AS oabs,
           count(*) OVER() AS total_count
      FROM base b
  )
  SELECT incidente_id, processo_codigo, cnj, numero_incidente, tipo_previsto, numero_depre,
         macrofase, fase, status, valor_acao, data_base, ente_nome, ente_esfera,
         autor_nome, advogados, oabs, elegivel, total_count
    FROM ag
   ORDER BY valor_acao DESC NULLS LAST
   LIMIT GREATEST(p_limit,1) OFFSET GREATEST(p_offset,0);
$function$;
