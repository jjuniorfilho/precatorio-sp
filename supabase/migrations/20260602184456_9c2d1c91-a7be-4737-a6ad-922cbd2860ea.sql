CREATE TABLE public.blog_posts (
  id UUID NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  slug TEXT NOT NULL UNIQUE,
  title TEXT NOT NULL,
  excerpt TEXT NOT NULL DEFAULT '',
  content TEXT NOT NULL DEFAULT '',
  category TEXT NOT NULL DEFAULT 'Guia',
  author TEXT NOT NULL DEFAULT 'Equipe Forjuris',
  reading_minutes INTEGER NOT NULL DEFAULT 3,
  published BOOLEAN NOT NULL DEFAULT false,
  published_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT ON public.blog_posts TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.blog_posts TO authenticated;
GRANT ALL ON public.blog_posts TO service_role;

ALTER TABLE public.blog_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anon_read_published_posts"
ON public.blog_posts
FOR SELECT
TO anon
USING (published = true);

CREATE POLICY "authenticated_read_published_posts"
ON public.blog_posts
FOR SELECT
TO authenticated
USING (
  published = true
  OR (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin')
);

CREATE POLICY "admin_write_posts"
ON public.blog_posts
FOR ALL
TO authenticated
USING (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin')
WITH CHECK (((auth.jwt() -> 'app_metadata') ->> 'role') = 'admin');

CREATE TRIGGER trg_blog_posts_updated_at
BEFORE UPDATE ON public.blog_posts
FOR EACH ROW
EXECUTE FUNCTION public.update_updated_at();

CREATE INDEX idx_blog_posts_published_at
ON public.blog_posts (published, published_at DESC);

INSERT INTO public.blog_posts (slug, title, excerpt, content, category, author, reading_minutes, published, published_at) VALUES
(
  'como-consultar-saldo-precatorio-sp',
  'Como consultar o saldo do seu precatório em São Paulo',
  'Passo a passo para encontrar o saldo atualizado do seu precatório no DEPRE/TJSP usando apenas o número do processo, CPF ou CNPJ.',
  E'Consultar o saldo de um precatório do Estado de São Paulo é mais simples do que parece. O DEPRE (Departamento de Execuções de Precatórios) do TJSP publica dados oficiais sobre cada processo.\n\nNeste guia, você vai entender:\n- O que é o número DEPRE e onde encontrá-lo\n- Como pesquisar pelo CPF do beneficiário ou CNPJ da empresa\n- Como interpretar o saldo, a ordem cronológica e a natureza (alimentar ou comum)\n\nNo Forjuris, unificamos a busca: basta digitar o processo, CPF ou CNPJ na home e recebemos a base atualizada do DEPRE em segundos.',
  'Guia',
  'Equipe Forjuris',
  4,
  true,
  '2026-05-26T12:00:00Z'
),
(
  'diferenca-cessao-antecipacao-precatorio',
  'Cessão x antecipação de precatório: qual a diferença?',
  'Entenda quando faz sentido ceder o crédito do precatório e quando a antecipação é a melhor saída — com vantagens e riscos de cada modelo.',
  E'Muitos titulares de precatório confundem cessão e antecipação. Os dois caminhos antecipam o recebimento, mas funcionam de forma diferente.\n\nNa cessão, você transfere o crédito para um terceiro mediante deságio. Na antecipação, recebe um valor adiantado mantendo o título.\n\nEste artigo explica os impactos jurídicos, tributários e o que considerar antes de assinar.',
  'Análise',
  'Equipe Forjuris',
  6,
  true,
  '2026-05-19T12:00:00Z'
),
(
  'acordo-direto-precatorio-sp-2026',
  'Acordo direto de precatório SP em 2026: o que esperar',
  'A janela de acordos diretos com o Estado de SP segue ativa em 2026. Veja prazos, descontos típicos e como se preparar.',
  E'A EC 109/2021 abriu caminho para acordos diretos entre credores e entes públicos. Em São Paulo, a PGE-SP segue conduzindo rodadas com descontos significativos.\n\nNeste post: prazos, faixa de deságio observada, perfil de credor priorizado e checklist de documentos.',
  'Notícia',
  'Equipe Forjuris',
  5,
  true,
  '2026-05-12T12:00:00Z'
);