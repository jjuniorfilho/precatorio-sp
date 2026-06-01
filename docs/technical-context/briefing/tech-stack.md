# Stack Tecnológica — Consulta Precatório SP

---

## Frontend (existente)

| Camada | Tecnologia | Versão | Status |
|--------|-----------|--------|--------|
| Framework | React | 19.2.0 | ✅ Produção |
| Roteamento | TanStack Router | 1.168.25 | ✅ Produção |
| Build | Vite | latest | ✅ Produção |
| UI Components | shadcn/ui | latest | ✅ Produção |
| CSS | Tailwind CSS | latest | ✅ Produção |
| Tipagem | TypeScript | latest | ✅ Produção |
| Deploy | Lovable (CDN) | — | ✅ Produção |

**Fontes**: Sora (headings) + Inter (body) + Fira Code (mono) via Google Fonts

**Repositório**: `jjuniorfilho/sp-precat-rios-simples-c2fc47c1`
**Branch Lovable**: `jjuniorfilho/precatorio-sp`

---

## Backend (a implementar)

| Camada | Tecnologia | Versão | Status |
|--------|-----------|--------|--------|
| BaaS | Supabase | latest | ❌ Pendente |
| Banco | PostgreSQL | 15+ | ❌ Pendente |
| Auth | Supabase Auth | — | ❌ Pendente |
| Realtime | Supabase Realtime | — | ❌ Pendente |
| Storage | Supabase Storage | — | ❌ Pendente (futuro) |
| SDK Frontend | @supabase/supabase-js | 2.x | ❌ Pendente instalar |

---

## Infraestrutura / Crawlers (VPS)

| Camada | Tecnologia | Status |
|--------|-----------|--------|
| Runtime | Python 3.x | ✅ Scripts existem em `bin/` |
| Crawler DEPRE | Python (collect_homologacoes.py) | ✅ Existe |
| Extração DEPRE | Python (extract_depre.py) | ✅ Existe |
| Match DEPRE-CSV | Python (match_depre_csv.py) | ✅ Existe |
| Agendamento | Cron (VPS) | ❌ Pendente configurar |
| Destino dos dados | Supabase PostgreSQL | ❌ Pendente (schema + import) |

**Scripts em**: `~/projetos/consulta-precatorio/bin/`

---

## Integrações externas (a contratar)

| Serviço | Finalidade | Status |
|---------|-----------|--------|
| Resend ou SendGrid | Envio de token por e-mail | ❌ Pendente |
| Twilio / Z-API / Evolution API | Envio de token por WhatsApp | ❌ Pendente |
| Google Analytics | Métricas de tráfego | ❌ Pendente (Fase 2) |
| Google Search Console | SEO | ❌ Pendente (Fase 2) |

---

## Variáveis de ambiente necessárias

```env
# Supabase
SUPABASE_URL=
SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=   # apenas backend/crawlers

# E-mail
RESEND_API_KEY=

# WhatsApp
WHATSAPP_API_URL=
WHATSAPP_API_TOKEN=

# Admin
ADMIN_EMAIL=admin@forjuris.com.br
```
