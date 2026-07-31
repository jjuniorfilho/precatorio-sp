-- FOR-72 (revisão, fix) — 19 processos "mega" (769 a 8.513 incidentes cada) estouram
-- timeout em classify_processo mesmo um por vez, porque a função reclassifica TODOS os
-- incidentes do processo numa UPDATE só. O índice trigram pra acelerar o ILIKE não
-- conseguiu ser criado via SQL Editor (tabela grande demais pro timeout da própria
-- ferramenta, e CREATE INDEX CONCURRENTLY não roda em transação).
--
-- Contorno: função irmã que reclassifica um LOTE de incidentes (por id), não um processo
-- inteiro — mesma lógica de match/UPDATE de classify_processo, só que escopada por
-- incidente_id em vez de processo_id. Chamada em lotes pequenos (ex.: 100 por vez) desde
-- fora, cada chamada fica pequena o suficiente pra nunca estourar timeout, não importa o
-- tamanho do processo. NÃO atualiza processos.next_crawl_at (isso é responsabilidade do
-- classify_processo normal — usar essa função só como contorno pontual pros mega-casos).
-- Aplicar no SQL Editor.

CREATE OR REPLACE FUNCTION classify_incidentes(p_incidente_ids UUID[])
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  WITH match AS (
    SELECT i.id AS incidente_id,
           i.tipo_previsto,
           (i.numero_depre IS NOT NULL) AS has_depre,
           bool_or(r.flag = 'calculo_homologado')   AS f_calc,
           bool_or(r.flag = 'incidente_instaurado') AS f_incidente,
           bool_or(r.flag = 'termo_declaracao')     AS f_termo,
           bool_or(r.flag = 'oficio_deferido')      AS f_deferido,
           bool_or(r.flag = 'oficio_expedido')      AS f_oficio,
           bool_or(r.flag = 'ordem_cronologica')    AS f_oc,
           bool_or(r.flag = 'possivelmente_pago')   AS f_pago,
           max(a.data) FILTER (WHERE r.flag = 'calculo_homologado')   AS d_calc,
           max(a.data) FILTER (WHERE r.flag = 'incidente_instaurado') AS d_incidente,
           max(a.data) FILTER (WHERE r.flag = 'termo_declaracao')     AS d_termo,
           max(a.data) FILTER (WHERE r.flag = 'oficio_deferido')      AS d_deferido,
           max(a.data) FILTER (WHERE r.flag = 'oficio_expedido')      AS d_oficio,
           max(a.data) FILTER (WHERE r.flag = 'ordem_cronologica')    AS d_oc
      FROM incidentes i
      LEFT JOIN andamentos a ON a.incidente_id = i.id
      LEFT JOIN classificacao_regras r
        ON r.ativo
       AND ( (r.tipo = 'ilike' AND a.descricao ILIKE r.padrao)
          OR (r.tipo = 'regex' AND a.descricao ~* r.padrao) )
     WHERE i.id = ANY(p_incidente_ids)
     GROUP BY i.id, i.tipo_previsto, i.numero_depre
  )
  UPDATE incidentes i SET
    calculo_homologado   = COALESCE(m.f_calc,      false),
    incidente_instaurado = COALESCE(m.f_incidente, false),
    termo_declaracao      = COALESCE(m.f_termo,    false),
    oficio_deferido        = COALESCE(m.f_deferido, false),
    oficio_expedido        = COALESCE(m.f_oficio,   false),
    ordem_cronologica      = COALESCE(m.f_oc,       false),
    possivelmente_pago     = COALESCE(m.f_pago,     false),
    fase = CASE
             WHEN COALESCE(m.f_oc,       false) THEN 'oc'
             WHEN COALESCE(m.f_oficio,   false) THEN 'oficio'
             WHEN m.has_depre                   THEN 'depre'
             WHEN COALESCE(m.f_deferido, false) THEN 'oficio_deferido'
             WHEN COALESCE(m.f_termo,    false) THEN 'termo'
             WHEN COALESCE(m.f_incidente,false) OR i.tipo_previsto <> 'Indefinido' THEN 'incidente'
             WHEN COALESCE(m.f_calc,     false) THEN 'calculo'
             ELSE 'inicial'
           END,
    fase_desde = CASE
             WHEN COALESCE(m.f_oc,       false) THEN m.d_oc
             WHEN COALESCE(m.f_oficio,   false) THEN m.d_oficio
             WHEN m.has_depre                   THEN NULL
             WHEN COALESCE(m.f_deferido, false) THEN m.d_deferido
             WHEN COALESCE(m.f_termo,    false) THEN m.d_termo
             WHEN COALESCE(m.f_incidente,false) THEN m.d_incidente
             WHEN i.tipo_previsto <> 'Indefinido' THEN NULL
             WHEN COALESCE(m.f_calc,     false) THEN m.d_calc
             ELSE NULL
           END,
    macrofase = CASE
                  WHEN COALESCE(m.f_oficio,false) AND i.tipo_previsto = 'RPV'        THEN 'rpv_efetivo'
                  WHEN COALESCE(m.f_oficio,false) AND i.tipo_previsto = 'Precatorio' THEN 'precatorio_efetivo'
                  ELSE 'direito_creditorio'
                END,
    elegivel = COALESCE(m.f_termo,false) AND NOT COALESCE(m.f_pago,false),
    ano_oc = CASE
               WHEN COALESCE(m.f_oc,false) THEN (
                 SELECT COALESCE(
                          (regexp_match(a.descricao, '(20\d{2})'))[1]::int,
                          EXTRACT(YEAR FROM a.data)::int )
                   FROM andamentos a
                   JOIN classificacao_regras r ON r.ativo AND r.flag = 'ordem_cronologica'
                    AND ( (r.tipo='ilike' AND a.descricao ILIKE r.padrao)
                       OR (r.tipo='regex' AND a.descricao ~* r.padrao) )
                  WHERE a.incidente_id = i.id
                  ORDER BY a.data DESC NULLS LAST
                  LIMIT 1 )
               ELSE i.ano_oc
             END,
    updated_at = NOW()
  FROM match m
  WHERE m.incidente_id = i.id;
END; $$;

GRANT EXECUTE ON FUNCTION classify_incidentes(UUID[]) TO service_role, authenticated;
