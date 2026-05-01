# Feature: SEO e Performance

## Resumo
Estrutura robusta de SEO integrada em toda a arquitetura do site, desde meta tags e schema markup ate paginas otimizadas por termo de busca. SEO e o canal principal de aquisicao e deve ser tratado como funcionalidade core, nao como camada adicional.

## Fase
**Fase 1 - MVP**

## Prioridade
**P0 - Critica** (canal principal de aquisicao)

---

## Descricao Funcional

### Arquitetura SEO

#### Estrutura de URLs
| Pagina | URL | Objetivo SEO |
|--------|-----|--------------|
| Home / Landing | / | "consultar precatorio SP" |
| Resultado de busca | /consulta/{numero-processo} | Indexacao de resultados (futuro) |
| Como funciona | /como-funciona | "como consultar precatorio" |
| FAQ | /perguntas-frequentes | Long-tail keywords |
| Sobre nos | /sobre | Trust + branding |
| Politica de privacidade | /privacidade | Compliance |
| Termos de uso | /termos | Compliance |
| Blog (Fase 2) | /blog/{slug} | Trafego informacional |

#### Meta Tags por Pagina
**Home**:
```html
<title>Consulte Gratis o Valor do Seu Precatorio SP | [Nome]</title>
<meta name="description" content="Descubra o saldo atualizado do seu precatorio 
do Estado de Sao Paulo. Consulta gratuita por numero do processo. Base com mais 
de 200 mil processos DEPRE." />
```

**Como Funciona**:
```html
<title>Como Consultar Seu Precatorio em SP | Passo a Passo</title>
<meta name="description" content="Aprenda como consultar o valor do seu 
precatorio do Estado de SP. Busca por numero do processo DEPRE ou numero 
dos autos. Resultado em segundos." />
```

**FAQ**:
```html
<title>Perguntas Frequentes sobre Precatorios SP | [Nome]</title>
<meta name="description" content="Tire suas duvidas sobre precatorios do 
Estado de Sao Paulo: valor, pagamento, prazo, como vender e mais." />
```

### Schema Markup (Structured Data)

#### Organization Schema
```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "[Nome da Empresa]",
  "description": "Consulta gratuita de precatorios do Estado de SP",
  "url": "https://[dominio]",
  "contactPoint": {
    "@type": "ContactPoint",
    "contactType": "customer service",
    "availableLanguage": "Portuguese"
  }
}
```

#### FAQ Schema (pagina FAQ)
```json
{
  "@context": "https://schema.org",
  "@type": "FAQPage",
  "mainEntity": [
    {
      "@type": "Question",
      "name": "Como consultar o valor do meu precatorio?",
      "acceptedAnswer": {
        "@type": "Answer",
        "text": "..."
      }
    }
  ]
}
```

#### WebApplication Schema
```json
{
  "@context": "https://schema.org",
  "@type": "WebApplication",
  "name": "Consulta de Precatorios SP",
  "applicationCategory": "FinanceApplication",
  "operatingSystem": "Web"
}
```

### Conteudo SEO por Pagina

#### Pagina FAQ (Perguntas-Chave)
1. O que e um precatorio?
2. Como consultar o valor do meu precatorio em SP?
3. Quando o Estado de SP vai pagar meus precatorios?
4. Qual a diferenca entre precatorio alimentar e comum?
5. Como vender meu precatorio?
6. O que e cessao de credito de precatorio?
7. Precatorio de herdeiro: como funciona?
8. O que e DEPRE?
9. Meu precatorio esta suspenso, o que significa?
10. Como saber se meu precatorio ja foi pago?

#### Pagina "Como Funciona" (Conteudo Educativo)
- Passo a passo visual da consulta
- Explicacao dos dados exibidos
- O que fazer apos consultar
- Glossario de termos (DEPRE, cessao, desagio, etc.)

---

## Requisitos Tecnicos

### Core Web Vitals
| Metrica | Meta | Importancia |
|---------|------|-------------|
| LCP (Largest Contentful Paint) | < 2.5s | Ranking factor |
| FID (First Input Delay) | < 100ms | Interatividade |
| CLS (Cumulative Layout Shift) | < 0.1 | Estabilidade visual |
| TTFB (Time to First Byte) | < 800ms | Performance servidor |

### Checklist Tecnico SEO
- [ ] Sitemap XML automatico
- [ ] robots.txt configurado
- [ ] Canonical tags em todas as paginas
- [ ] Open Graph tags (compartilhamento social)
- [ ] Favicon e apple-touch-icon
- [ ] SSL/HTTPS obrigatorio
- [ ] Responsive design (mobile-first)
- [ ] Heading hierarchy (H1 > H2 > H3) correto
- [ ] Alt text em todas as imagens
- [ ] URLs amigaveis (sem IDs, com keywords)
- [ ] Breadcrumbs com schema markup
- [ ] 404 page customizada
- [ ] Redirect 301 para URLs com/sem trailing slash
- [ ] Compressao GZIP/Brotli
- [ ] Lazy loading de imagens
- [ ] Font display: swap (evitar FOIT)

### Integracao com Ferramentas
| Ferramenta | Fase | Motivo |
|-----------|------|--------|
| Google Search Console | Fase 1 | Monitorar indexacao e posicionamento |
| Google Analytics 4 | Fase 1 | Metricas de trafego e conversao |
| Google Tag Manager | Fase 1 | Gestao de tags e eventos |

---

## Metricas de Sucesso
| Metrica | Meta | Prazo |
|---------|------|-------|
| Paginas indexadas | 100% das paginas publicas | 30 dias |
| Posicao media (termos-chave) | Top 10 | 3 meses |
| Posicao media (termos-chave) | Top 5 | 6 meses |
| Trafego organico/mes | 5.000 visitas | 3 meses |
| Core Web Vitals | Todos "Good" | Lancamento |
| Mobile usability | 0 erros | Lancamento |
