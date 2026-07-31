-- FOR-72 (revisão, fix) — a CHECK constraint incidentes_fase_check só permitia os 6
-- valores originais de fase (calculo, incidente, termo, depre, oficio, oc). A revisão
-- introduziu 'inicial' (fallback genuíno) e 'oficio_deferido' (nova fase) — sem isso,
-- classify_processo falha com "violates check constraint incidentes_fase_check" pra
-- qualquer incidente que caia nesses dois valores novos. Aplicar no SQL Editor.

ALTER TABLE incidentes DROP CONSTRAINT IF EXISTS incidentes_fase_check;
ALTER TABLE incidentes ADD CONSTRAINT incidentes_fase_check
  CHECK (fase IS NULL OR fase IN
    ('inicial','calculo','incidente','termo','oficio_deferido','depre','oficio','oc'));
