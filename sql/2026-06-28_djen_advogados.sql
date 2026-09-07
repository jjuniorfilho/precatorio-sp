-- FOR-70/71 — Staging estruturado dos advogados do DJEN (fonte de verdade de nome+OAB+UF).
-- O ingest-djen persiste aqui ao flaguear o CNJ; o crawler lê daqui (DJEN-first) e
-- reconcilia por nome com a parte ativa do e-SAJ p/ atribuir a OAB ao advogado do autor.
-- Dedup por (cnj_normalizado, chave_advogado), chave = oab_normalizada ou NOME em maiúsculo.
-- Aplicar no SQL Editor.

create table if not exists public.djen_advogados (
  id               bigint generated always as identity primary key,
  cnj              text not null,
  cnj_normalizado  text not null,
  advogado_nome    text not null,
  oab_numero       text,
  uf_oab           text,
  oab              text,          -- formatado "305848/SP"
  oab_normalizada  text,          -- "305848SP"
  chave_advogado   text not null, -- dedup: oab_normalizada || upper(nome)
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (cnj_normalizado, chave_advogado)
);

create index if not exists idx_djen_advogados_cnj_norm on public.djen_advogados (cnj_normalizado);
create index if not exists idx_djen_advogados_oab_norm on public.djen_advogados (oab_normalizada);

alter table public.djen_advogados enable row level security;

-- O worker (login admin → role authenticated) lê e escreve.
drop policy if exists djen_advogados_authenticated_all on public.djen_advogados;
create policy djen_advogados_authenticated_all on public.djen_advogados
  for all to authenticated using (true) with check (true);
