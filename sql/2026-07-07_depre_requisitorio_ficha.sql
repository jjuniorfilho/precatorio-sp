-- FOR-70 — DEPRE (.0500) nunca é processo principal.
-- Estende djen_depre para guardar a FICHA + ANDAMENTOS do requisitório .0500,
-- persistidos quando o crawler visita a Consulta de Requisitórios. O vínculo com
-- o processo principal continua por numero_depre (o incidente do principal que
-- referencia o .0500). Aplicar no SQL Editor.

alter table public.djen_depre
  add column if not exists valor_acao        bigint,      -- centavos
  add column if not exists status            text,        -- ativo/suspenso/extinto/arquivado (bruto)
  add column if not exists classe            text,
  add column if not exists data_base         date,
  add column if not exists devedora          text,        -- parte passiva (ente devedor)
  add column if not exists origem_cnjs       text[],      -- CNJ(s) do processo de origem (principal)
  add column if not exists andamentos        jsonb,       -- movimentações do requisitório [{data,descricao,arquivo_url}]
  add column if not exists ficha_crawled_at  timestamptz; -- quando a ficha do .0500 foi coletada

-- índice para localizar o .0500 a partir do numero_depre do incidente do principal
create index if not exists idx_djen_depre_cnj_norm on public.djen_depre (cnj_normalizado);
