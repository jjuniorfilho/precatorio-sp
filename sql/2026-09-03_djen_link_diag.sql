-- FOR-143/coleta — instrumenta o roteamento do DJEN pra diagnosticar os erros restantes de
-- "busca não retornou página de detalhe" em crawler_queue (origem dje_diario/backfill, ~5.475
-- em 2026-09-03). sistemaFromLink() (ingest-djen.ts) só detecta "eproc" positivamente — tudo
-- que não é claramente eproc (inclusive "outro": link vazio ou de sistema desconhecido) cai no
-- mesmo caminho de "esaj" e vai pro crawler, mesmo sem evidência de que o processo esteja
-- mesmo no e-SAJ. Suspeita: uma fatia dos erros vem daí. Hoje não dá pra confirmar
-- retroativamente porque o `link` original só é persistido pro ramo eproc (eproc_pendentes) e
-- pro .0500 (djen_depre) — o ramo que vai pro crawler nunca grava o link. Essa tabela fecha
-- essa lacuna: puramente aditiva/diagnóstica, não muda nenhum comportamento de roteamento.
-- Aplicar no SQL Editor.

create table if not exists public.djen_link_diag (
  id                     bigint generated always as identity primary key,
  cnj                    text not null,
  link                   text,
  sistema_detectado      text not null,  -- 'esaj' | 'eproc' | 'outro'
  origem                 text not null,  -- 'dje_diario' | 'backfill'
  data_disponibilizacao  date not null,
  created_at             timestamptz not null default now()
);
alter table public.djen_link_diag enable row level security;
drop policy if exists djen_link_diag_authenticated_all on public.djen_link_diag;
create policy djen_link_diag_authenticated_all on public.djen_link_diag
  for all to authenticated using (true) with check (true);

create index if not exists idx_djen_link_diag_cnj on public.djen_link_diag (cnj);
create index if not exists idx_djen_link_diag_sistema on public.djen_link_diag (sistema_detectado);
