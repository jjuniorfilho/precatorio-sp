-- FOR-102 (extensão) — Titular (Reqte/requerente) do requisitório .0500.
-- A ficha do .0500 (mesma show.do da Consulta de Requisitórios) sempre traz o nome do
-- requerente em "PARTES DO PROCESSO" — o crawler já parseia isso (extractPartes/parte_ativa)
-- mas até aqui descartava o nome ao persistir em djen_depre (persistRequisitorio só gravava
-- a parte passiva/devedora). titular_documento não vem da ficha (TJSP não expõe CPF/CNPJ
-- ali) — só é preenchido quando o próprio titular informa o documento numa busca pública
-- (buscar-precatorio) que bate nesse numero_depre. Aplicar no SQL Editor. Re-executável.

ALTER TABLE public.djen_depre
  ADD COLUMN IF NOT EXISTS titular_nome      TEXT,
  ADD COLUMN IF NOT EXISTS titular_documento TEXT;
