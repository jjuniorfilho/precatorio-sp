# Lovable Prompt — Consulta Precatório SP (Frontend MVP)

> Prompt autocontido. Cole diretamente no Lovable. Sem necessidade de informações adicionais.

---

## VISÃO GERAL DO PROJETO

Construa o frontend completo do **Consulta Precatório SP** — um portal de consulta gratuita de precatórios do Estado de São Paulo com sistema de captura de leads qualificados e painel administrativo com CRM.

**Tagline**: "Consulte Gratis o Valor do Seu Precatório SP"

**Modelo de negócio**: O usuário consulta o saldo do precatório gratuitamente (sem cadastro). Após ver o resultado, é convidado a fornecer seus dados para receber detalhes completos. Isso gera um lead qualificado para a equipe comercial ofertar a cessão de crédito.

**Stack obrigatória**:
- React (TypeScript) via Lovable
- Supabase para banco de dados, autenticação e realtime
- shadcn/ui para todos os componentes
- Tailwind CSS
- React Router v6 para navegação
- Sora (Google Fonts) para headings + Inter para body/UI (ambas via Google Fonts)

---

## DESIGN SYSTEM — IMPLEMENTAR EXATAMENTE

> Referência visual: **BTG Pactual Content Portal** (content.btgpactual.com)
> Três níveis de azul: royal (navbar) → navy (hero/footer) → medium (seções CTA)

### Cores (CSS custom properties no globals.css)

```css
:root {
  --background: hsl(0 0% 100%);
  --foreground: hsl(222 47% 6%);
  --card: hsl(0 0% 100%);
  --card-foreground: hsl(222 47% 6%);

  /* Três azuis BTG */
  --primary: hsl(222 57% 42%);        /* #2B4FA8 — Royal Blue — navbar, botões */
  --primary-dark: hsl(222 57% 34%);
  --primary-light: hsl(222 57% 55%);
  --primary-foreground: hsl(0 0% 100%);
  --primary-50: hsl(222 57% 96%);
  --navy: hsl(225 62% 14%);           /* #0C1B3D — Dark Navy — hero, footer */
  --blue-section: hsl(221 58% 44%);   /* #2F5BB4 — Medium Blue — seções CTA */
  --icon-blue: hsl(219 55% 55%);      /* #4472CA — azul vibrante para ícones */

  --secondary: hsl(214 40% 96%);
  --secondary-foreground: hsl(222 47% 11%);
  --muted: hsl(214 40% 96%);          /* #F0F3F8 — azul-cinza claro */
  --muted-foreground: hsl(215 16% 47%);
  --border: hsl(220 13% 91%);         /* #E5E7EB */
  --input: hsl(220 13% 91%);
  --ring: hsl(222 57% 42%);
  --success: hsl(142 50% 45%);
  --success-bg: hsl(149 80% 96%);
  --warning: hsl(38 70% 50%);
  --warning-dark: hsl(28 92% 45%);
  --warning-bg: hsl(48 100% 97%);
  --error: hsl(0 60% 50%);
  --error-bg: hsl(0 86% 97%);
  --info: hsl(199 60% 45%);
  --info-bg: hsl(210 100% 97%);
  --radius: 0.5rem;
  --shadow-sm: 0 1px 3px rgba(16,24,40,0.1), 0 1px 2px rgba(16,24,40,0.06);
  --shadow-md: 0 4px 8px -2px rgba(16,24,40,0.1), 0 2px 4px -2px rgba(16,24,40,0.06);
}

.dark {
  --background: hsl(225 62% 11%);
  --foreground: hsl(210 40% 98%);
  --card: hsl(225 62% 13%);
  --card-foreground: hsl(210 40% 98%);
  --navy: hsl(225 62% 8%);
  --muted: hsl(222 40% 18%);
  --muted-foreground: hsl(215 20% 65%);
  --border: hsl(222 40% 22%);
  --input: hsl(222 40% 22%);
  --success: hsl(142 50% 55%);
  --success-bg: hsl(142 40% 15%);
  --warning: hsl(38 70% 60%);
  --warning-bg: hsl(38 60% 15%);
  --error: hsl(0 60% 60%);
  --error-bg: hsl(0 50% 15%);
}
```

### Tipografia
- **Headings (h1–h3)**: Sora (Google Fonts) — pesos 600, 700, 800 — `font-family: 'Sora', sans-serif`
- **Body / UI**: Inter (Google Fonts) — pesos 400, 500, 600, 700
- **Código / processo**: Fira Code — pesos 400, 600
- Import: `@import url('https://fonts.googleapis.com/css2?family=Sora:wght@600;700;800&family=Inter:wght@400;500;600;700&family=Fira+Code:wght@400;600&display=swap')`
- Títulos: Sora bold + tracking-tight (-0.025em)
- Escala: 12/13/14/16/20/24/30/36px

### Forma e Espaço
- Border radius padrão: `--radius: 0.5rem` (8px)
- Botões: 6px (`rounded-[6px]`)
- Cards: `rounded-lg` (8px)
- Modais: `rounded-xl` (12px)
- Badges/pills: `rounded-full`
- Sombras: `shadow-sm` em cards padrão, `shadow-md` em hover/modais

### Navbar (portal público)
- `background: var(--primary)` — royal blue #2B4FA8
- Logo e links: texto branco (`text-white`)
- Botão outline no header: borda branca + texto branco (`border-white/75 text-white bg-transparent`)
- Botão filled no header: fundo branco + texto primary (`bg-white text-primary`)

### Hero (landing page)
- `background: var(--navy)` — dark navy #0C1B3D
- Título h1: `text-white font-bold font-sora`
- Subtítulo: `text-white/75`
- Eyebrow badge: `bg-white/12 border-white/20 text-white/90`
- Search bar: fundo branco com shadow-md sobre o hero dark

### Footer (landing page)
- `background: var(--navy)` — dark navy #0C1B3D
- Texto: `text-white/60`
- Links: `text-white/75` → hover: `text-white`
- Brand: `text-white font-bold`

### Sidebar Admin
- Background: `bg-white` (branco puro)
- Border-right: `border-gray-200` (#E5E7EB)
- Item ativo: `bg-[hsl(214_40%_96%)]` = #F0F3F8
- Ícones inativos: `text-[hsl(219_55%_55%)]` = #4472CA (icon-blue)
- Ícones ativos: `text-primary`
- Page background: `bg-muted` = #F0F3F8

### Admin Topbar
- `bg-white border-b border-gray-200`

### Regras de estilo (NUNCA violar)
- Navbar de páginas públicas **sempre** em royal blue (nunca branco ou transparente)
- Hero da landing page **sempre** em dark navy (nunca branco)
- Footer da landing page **sempre** em dark navy
- Sidebar admin **sempre** fundo branco (nunca azul)
- Nunca usar gradientes de fundo coloridos em seções
- Nunca usar border-radius maior que 12px em cards principais
- Cards: `rounded-lg border bg-card shadow-sm`
- Sombras pesadas apenas em modais e popovers

### Padrão de tabelas (rhilo table-row pattern)
```tsx
// Zebra striping
className="[&>tbody>tr:nth-child(even)]:bg-muted/40 [&>tbody>tr:nth-child(odd)]:bg-background"

// Hover com elevação
className="transition-all duration-150 hover:bg-muted/60 hover:shadow-sm hover:-translate-y-px cursor-pointer"

// Quick actions — visíveis apenas no hover
className="opacity-0 group-hover:opacity-100 transition-opacity"
```

### Badges de status CRM
```
novo        → bg-blue-50    text-blue-700
contatado   → bg-cyan-50    text-cyan-700
qualificado → bg-yellow-50  text-yellow-700
interessado → bg-orange-50  text-orange-700
proposta    → bg-purple-50  text-purple-700
negociacao  → bg-pink-50    text-pink-700
fechado     → bg-green-50   text-green-700
descartado  → bg-muted      text-muted-foreground
```

---

## ESTRUTURA DE ROTAS

```
/ ................................ Landing page (portal público)
/resultado/:processo ............. Resultado único — busca por número de processo
/resultado/cpf/:cpf .............. Resultado lista — busca por CPF (1 a N precatórios)
/resultado/cnpj/:cnpj ............ Resultado lista — busca por CNPJ (1 a N precatórios)
/cadastro ........................ Formulário de captura de lead (step 2/4)
/verificar/email ................. Token OTP e-mail (step 3a/4)
/verificar/whatsapp .............. Token OTP WhatsApp (step 3b/4)
/obrigado ........................ Confirmação de cadastro (step 4/4)

/admin/login ..................... Login administrativo
/admin ........................... Redireciona para /admin/leads
/admin/leads ..................... Listagem de leads completos + modal detalhe
/admin/incompletos ............... Leads incompletos (sessões sem cadastro)
/admin/funil ..................... Dashboard metrics + funil de conversão
```

**Proteção de rotas**: Todas as rotas `/admin/*` (exceto `/admin/login`) devem verificar autenticação. Se não autenticado, redirecionar para `/admin/login`. Usar localStorage para mock de auth no MVP: `{ isAuthenticated: boolean, email: string }`.

---

## DADOS MOCK — IMPLEMENTAR COMPLETO

### Arquivo: `src/data/mockData.ts`

```typescript
// Base de precatórios (simula Supabase table: precatorios)
export const mockPrecatorios = [
  {
    id: "1",
    processo_depre: "0122089-09.2025.8.26.0500",
    autos: "0122089-09.2025.8.26.0500",
    cpf_titular: "123.456.789-00",
    cnpj_titular: null,
    devedora: "Fazenda do Estado de SP",
    saldo_depre: 14783200, // centavos
    natureza: "Alimentar",
    status: "Ativo",
    suspenso: false,
    data_protocolo: "2025-03-15",
  },
  {
    id: "2",
    processo_depre: "0033421-14.2023.8.26.0100",
    autos: "0033421-14.2023.8.26.0100",
    cpf_titular: "123.456.789-00", // mesmo CPF — titular com dois precatórios
    cnpj_titular: null,
    devedora: "SPPREV",
    saldo_depre: 0,
    natureza: "Outras",
    status: "Sem saldo",
    suspenso: false,
    data_protocolo: "2023-07-20",
  },
  {
    id: "3",
    processo_depre: "0006248-79.2024.8.26.0506",
    autos: "0006248-79.2024.8.26.0506",
    cpf_titular: "987.654.321-00",
    cnpj_titular: null,
    devedora: "CBPM",
    saldo_depre: 8920000, // centavos
    natureza: "Outras",
    status: "Suspenso",
    suspenso: true,
    data_protocolo: "2024-01-10",
  },
  {
    id: "4",
    processo_depre: "0044122-33.2022.8.26.0200",
    autos: "0044122-33.2022.8.26.0200",
    cpf_titular: null,
    cnpj_titular: "12.345.678/0001-90", // pessoa jurídica
    devedora: "IPESP",
    saldo_depre: 5210000,
    natureza: "Outras",
    status: "Ativo",
    suspenso: false,
    data_protocolo: "2022-09-05",
  },
  {
    id: "5",
    processo_depre: "0089201-44.2021.8.26.0300",
    autos: "0089201-44.2021.8.26.0300",
    cpf_titular: null,
    cnpj_titular: "12.345.678/0001-90", // mesma empresa — dois precatórios
    devedora: "DER",
    saldo_depre: 31254000,
    natureza: "Alimentar",
    status: "Ativo",
    suspenso: false,
    data_protocolo: "2021-04-22",
  },
]

// Leads completos (simula Supabase table: leads)
export const mockLeads = [
  {
    id: "1",
    nome: "Maria Aparecida da Silva",
    email: "maria.silva@gmail.com",
    telefone: "(11) 99182-3344",
    relacao: "titular",
    processo_depre: "0122089-09.2025.8.26.0500",
    saldo_consultado: 14783200,
    devedora: "Fazenda SP",
    status_crm: "novo",
    notas: "Ligou às 15h. Demonstrou interesse em antecipar. Pediu para ligar amanhã pela manhã.",
    token_email_validado: true,
    token_telefone_validado: true,
    created_at: "2026-05-31T14:23:00Z",
  },
  {
    id: "2",
    nome: "Carlos Eduardo Herdeiro",
    email: "carlos.h@email.com",
    telefone: "(21) 98765-4321",
    relacao: "herdeiro",
    processo_depre: "0006248-79.2024.8.26.0506",
    saldo_consultado: 8920000,
    devedora: "SPPREV",
    status_crm: "contatado",
    notas: "",
    token_email_validado: true,
    token_telefone_validado: true,
    created_at: "2026-05-31T11:05:00Z",
  },
  {
    id: "3",
    nome: "Dr. Rodrigo Fernandes",
    email: "rfernandes@adv.com",
    telefone: "(11) 97654-3210",
    relacao: "advogado",
    processo_depre: "0033421-14.2023.8.26.0100",
    saldo_consultado: 31254000,
    devedora: "CBPM",
    status_crm: "proposta",
    notas: "Advogado com 3 clientes. Quer soluções em lote.",
    token_email_validado: true,
    token_telefone_validado: true,
    created_at: "2026-05-30T16:30:00Z",
  },
  {
    id: "4",
    nome: "Aparecida Santos",
    email: "aparecida@hotmail.com",
    telefone: "(11) 95555-0000",
    relacao: "titular",
    processo_depre: "0044122-33.2022.8.26.0200",
    saldo_consultado: 5210000,
    devedora: "IPESP",
    status_crm: "fechado",
    notas: "Cessão concluída. Cliente satisfeita.",
    token_email_validado: true,
    token_telefone_validado: true,
    created_at: "2026-05-23T09:14:00Z",
  },
  {
    id: "5",
    nome: "João Pedro Lima",
    email: "jplima@email.com",
    telefone: "(19) 98811-2233",
    relacao: "titular",
    processo_depre: "0089201-44.2021.8.26.0300",
    saldo_consultado: 420000,
    devedora: "DER",
    status_crm: "descartado",
    notas: "Saldo muito baixo. Não viável para operação.",
    token_email_validado: true,
    token_telefone_validado: true,
    created_at: "2026-05-20T11:00:00Z",
  },
]

// Leads incompletos (simula funnel_events sem conversão)
export const mockLeadsIncompletos = [
  {
    session_id: "sess_abc123",
    processo_buscado: "0122089-09.2025.8.26.0500",
    saldo_encontrado: 14783200,
    etapa_abandono: "Formulário abandonado",
    dispositivo: "Mobile · Chrome · SP",
    data: "2026-05-31T13:44:00Z",
  },
  {
    session_id: "sess_def456",
    processo_buscado: "0055231-77.2024.8.26.0100",
    saldo_encontrado: 22000000,
    etapa_abandono: "Token não confirmado",
    dispositivo: "Mobile · Safari · RJ",
    data: "2026-05-31T11:21:00Z",
  },
  {
    session_id: "sess_ghi789",
    processo_buscado: "0091111-55.2023.8.26.0506",
    saldo_encontrado: 3840000,
    etapa_abandono: "Saiu após resultado",
    dispositivo: "Desktop · Firefox · SP",
    data: "2026-05-30T16:02:00Z",
  },
]

// Métricas do funil de conversão
export const mockFunnelStats = {
  visitantes: 8420,
  buscas: 5220,
  resultados: 3790,
  cadastrosIniciados: 1516,
  tokensValidados: 842,
  leadsCompletos: 421,
}

// Timeline de eventos por lead
export const mockLeadTimeline = {
  "1": [
    { evento: "Lead completo — ambos canais validados", tempo: "2026-05-31T14:23:00Z", tipo: "success" },
    { evento: "Token WhatsApp validado", tempo: "2026-05-31T14:22:00Z", tipo: "success" },
    { evento: "Token e-mail validado", tempo: "2026-05-31T14:18:00Z", tipo: "success" },
    { evento: "Cadastro iniciado", tempo: "2026-05-31T14:15:00Z", tipo: "default" },
    { evento: "Buscou processo 0122089... · Mobile · São Paulo, SP", tempo: "2026-05-31T14:14:00Z", tipo: "muted" },
  ],
  "2": [
    { evento: "Lead completo", tempo: "2026-05-31T11:05:00Z", tipo: "success" },
    { evento: "Token WhatsApp validado", tempo: "2026-05-31T11:04:00Z", tipo: "success" },
    { evento: "Token e-mail validado", tempo: "2026-05-31T11:01:00Z", tipo: "success" },
    { evento: "Cadastro iniciado", tempo: "2026-05-31T10:59:00Z", tipo: "default" },
    { evento: "Buscou processo 0006248... · Mobile · Rio de Janeiro, RJ", tempo: "2026-05-31T10:58:00Z", tipo: "muted" },
  ],
  "3": [
    { evento: "Lead completo", tempo: "2026-05-30T16:30:00Z", tipo: "success" },
    { evento: "Token WhatsApp validado", tempo: "2026-05-30T16:29:00Z", tipo: "success" },
    { evento: "Token e-mail validado", tempo: "2026-05-30T16:26:00Z", tipo: "success" },
    { evento: "Cadastro iniciado", tempo: "2026-05-30T16:24:00Z", tipo: "default" },
    { evento: "Buscou processo 0033421... · Desktop · São Paulo, SP", tempo: "2026-05-30T16:23:00Z", tipo: "muted" },
  ],
}

// CRM pipeline counts
export const mockCrmPipeline = {
  novo: 12,
  contatado: 48,
  qualificado: 21,
  interessado: 15,
  proposta: 8,
  negociacao: 4,
  fechado: 183,
  descartado: 36,
}

// Tipos TypeScript
export type CrmStatus =
  | "novo"
  | "contatado"
  | "qualificado"
  | "interessado"
  | "proposta"
  | "negociacao"
  | "fechado"
  | "descartado"

export type Relacao = "titular" | "herdeiro" | "advogado"

export interface Precatorio {
  id: string
  processo_depre: string
  autos: string
  devedora: string
  saldo_depre: number // centavos
  natureza: string
  status: string
  suspenso: boolean
  data_protocolo: string
}

export interface Lead {
  id: string
  nome: string
  email: string
  telefone: string
  relacao: Relacao
  processo_depre: string
  saldo_consultado: number // centavos
  devedora: string
  status_crm: CrmStatus
  notas: string
  token_email_validado: boolean
  token_telefone_validado: boolean
  created_at: string
}

export interface LeadIncompleto {
  session_id: string
  processo_buscado: string
  saldo_encontrado: number
  etapa_abandono: string
  dispositivo: string
  data: string
}
```

### Utilitário de formatação monetária

```typescript
// src/lib/format.ts
export function formatCurrency(centavos: number): string {
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL",
  }).format(centavos / 100)
}

export function formatDate(iso: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(iso))
}

// Remove máscara de qualquer input
export function normalizeInput(input: string): string {
  return input.replace(/[\s.\-\/]/g, "").toLowerCase()
}

// Detecta o tipo de input automaticamente
export type InputType = "processo" | "cpf" | "cnpj" | "desconhecido"
export function detectInputType(input: string): InputType {
  const digits = input.replace(/\D/g, "")
  if (digits.length === 11) return "cpf"
  if (digits.length === 14) {
    // CNPJ tem 14 dígitos; processo DEPRE normalizado também pode ter ~14+
    // Distinguir: CNPJ puro de dígitos vs número de processo
    if (/^\d{14}$/.test(digits) && !input.includes(".8.26.")) return "cnpj"
  }
  // Padrão de processo: contém ".8.26."
  if (input.includes(".8.26.") || /\d{7}-\d{2}\.\d{4}/.test(input)) return "processo"
  if (digits.length === 11) return "cpf"
  return "desconhecido"
}

// Busca por número de processo (resultado único)
export function findByProcesso(input: string, precatorios: Precatorio[]): Precatorio | null {
  const normalized = normalizeInput(input)
  return precatorios.find(
    (p) =>
      normalizeInput(p.processo_depre) === normalized ||
      normalizeInput(p.autos) === normalized
  ) ?? null
}

// Busca por CPF (retorna lista)
export function findByCpf(cpf: string, precatorios: Precatorio[]): Precatorio[] {
  const normalized = normalizeInput(cpf)
  return precatorios.filter(
    (p) => p.cpf_titular && normalizeInput(p.cpf_titular) === normalized
  )
}

// Busca por CNPJ (retorna lista)
export function findByCnpj(cnpj: string, precatorios: Precatorio[]): Precatorio[] {
  const normalized = normalizeInput(cnpj)
  return precatorios.filter(
    (p) => p.cnpj_titular && normalizeInput(p.cnpj_titular) === normalized
  )
}

// Mascara CPF/CNPJ para exibição (privacidade)
export function maskCpf(cpf: string): string {
  return cpf.replace(/(\d{3})\.\d{3}\.\d{3}-(\d{2})/, "$1.***.***-$2")
}
export function maskCnpj(cnpj: string): string {
  return cnpj.replace(/(\d{2})\.\d{3}\.\d{3}\/(\d{4}-\d{2})/, "$1.***.***/$2")
}
```

---

## SUPERFÍCIE 1 — LANDING PAGE (`/`)

### Estrutura visual (mobile-first)

**Navbar** (sticky top, height 56px, `bg-[hsl(222_57%_42%)]` — royal blue BTG, sem border):
- Esquerda: logotipo "Forjuris" (texto branco, font-semibold)
- Direita: links "Como funciona" e "Dúvidas" (ghost branco, `text-white/85`, hidden em mobile), botão dark mode toggle (ícone sol/lua, cor branca)

**Hero section** (padding 72px 24px desktop, 48px 20px mobile, text-center, `bg-[hsl(225_62%_14%)]` — dark navy BTG):
- Eyebrow badge (pill, `bg-white/12 border border-white/20 text-white/90`): "Dados públicos oficiais do DEPRE · Gratuito · Resultado em segundos"
- H1: **"Consulte Gratis o Valor do Seu Precatório SP"** (font-size: clamp(28px, 5vw, 40px), font-bold, tracking-tight, `text-white`, Sora)
- Subtítulo: **"Base com mais de 200 mil processos do DEPRE. Resultado em segundos."** (`text-white/75`, max-w-md)
- Caixa de busca (max-w-lg, margin auto):
  - Input de texto (height 48px, rounded-lg, **bg-white**, shadow-md, placeholder: "Processo, CPF ou CNPJ")
  - Helper text abaixo do input (text-xs text-muted-foreground): "Ex: 0122089-09.2025.8.26.0500 · 123.456.789-00 · 12.345.678/0001-90"
  - Botão "Consultar Agora" (height 48px, btn-default, no mesmo row em desktop, abaixo em mobile)
  - Em mobile: `flex-col` para input e botão ficarem empilhados com `w-full`
- Trust row abaixo da busca (flex wrap, gap-5, justify-center):
  - "Sem cadastro prévio" (ícone check verde)
  - "Dados do TJSP/DEPRE" (ícone check verde)
  - "Forjuris · CNPJ XX.XXX.XXX/XXXX-XX" (ícone check verde)

**Stats strip** (border-y bg-muted/40, padding 12px 24px):
- "4.821 consultas hoje" | "200.000+ processos na base" | "Resultado em < 2 segundos"
- Em mobile: flex-col ou flex-wrap centralizado

**Seção "Como funciona"** (bg-muted, padding 64px 24px, id="como-funciona"):
- H2: "Como funciona"
- Subtítulo: "Simples, rápido, sem burocracia"
- Grid 3 colunas (1 coluna em mobile):
  1. Card: ícone busca + "1. Informe o número" + "Digite o número do processo DEPRE, número de Autos, CPF ou CNPJ do titular. Detectamos automaticamente."
  2. Card: ícone monitor + "2. Veja o saldo" + "Resultado instantâneo com saldo DEPRE, status, natureza e devedora. Grátis, sem compromisso."
  3. Card: ícone telefone + "3. Receba os detalhes" + "Se quiser mais informações, informe seus dados e receba o relatório completo no e-mail e WhatsApp."

**Seção FAQ** (padding 64px 24px, max-w-2xl, id="faq"):
- H2: "Dúvidas frequentes"
- Accordion shadcn/ui com 5 itens:
  1. "O que é um precatório?" → "Precatório é um documento emitido pela Justiça determinando que o Estado deve pagar uma dívida reconhecida por sentença judicial. O pagamento é feito em ordem cronológica."
  2. "A consulta é realmente gratuita?" → "Sim. A consulta do saldo DEPRE é 100% gratuita e sem compromisso. Você não precisa nem se cadastrar para ver o resultado."
  3. "O que é o DEPRE?" → "DEPRE é o Departamento de Precatórios do Tribunal de Justiça de São Paulo. Nossa base usa os dados oficiais do DEPRE com mais de 200 mil processos."
  4. "Por que o saldo pode estar diferente do que recebi?" → "O saldo exibido é o da base DEPRE sem atualização monetária. O valor real corrigido pela SELIC pode ser diferente."
  5. "Meus dados estão seguros?" → "Sim. Seus dados são protegidos pela LGPD. Você pode solicitar exclusão a qualquer momento."

**Footer** (`bg-[hsl(225_62%_14%)]` — dark navy BTG, padding 32px 24px, text-center, `text-white/60`):
- "Forjuris" (font-bold text-white)
- "Forjuris · CNPJ XX.XXX.XXX/XXXX-XX · Termos de Uso · Privacidade (LGPD)"
- "Dados públicos oficiais do DEPRE/TJSP. Sem relação com o Tribunal de Justiça."

### Comportamento da busca
1. Ao submeter (click no botão ou Enter): mostrar estado loading (spinner no botão, texto "Consultando...")
2. Simular delay de 800ms
3. Usar `detectInputType()` para identificar o tipo de input automaticamente
4. Lógica de roteamento por tipo:
   - `"processo"` → `findByProcesso()` → navegar para `/resultado/:processo` (resultado único)
   - `"cpf"`      → `findByCpf()` → navegar para `/resultado/cpf/:cpf` (lista de precatórios)
   - `"cnpj"`     → `findByCnpj()` → navegar para `/resultado/cnpj/:cnpj` (lista de precatórios)
   - `"desconhecido"` → exibir mensagem de validação inline sem navegar
5. Guardar resultado no contexto/estado global (useContext ou Zustand) para evitar re-busca

---

## SUPERFÍCIE 2 — RESULTADO DA CONSULTA (`/resultado/:processo`)

### Layout
- Navbar igual ao da landing
- Container max-w-lg, margin auto, padding 28px 16px 64px
- Campo de busca preservado no topo (com valor preenchido), botão "Nova busca"

### Estados obrigatórios (4 variantes)

#### Variante A — Saldo ativo (saldo_depre > 0, suspenso = false)
Card principal (`rounded-lg border bg-card shadow-sm`):
- Header: ponto verde (8px) + "PRECATÓRIO ENCONTRADO" (uppercase, text-xs, tracking-wide, text-muted-foreground) + "DEPRE · mai/2026" (margin-left auto)
- **Saldo destaque**:
  - Label: "SALDO DEPRE" (uppercase, text-xs font-medium text-muted-foreground)
  - Valor: formatar como R$ com separador de milhar e vírgula decimal (ex: `R$ 147.832,00`) em font-bold text-success, font-size 36px
- Separador
- Dados do processo (label/valor em linha, justify-between):
  - Processo: número em fonte mono (`font-mono text-sm font-semibold text-primary`)
  - Devedora: text-sm font-medium
  - Natureza: badge success (ex: "Alimentar") ou badge secondary (ex: "Outras")
  - Status: badge success "Ativo"
- **Dados bloqueados** (box com bg-muted/40, rounded-lg, ícone cadeado):
  - Label: "Dados completos — requer cadastro gratuito"
  - Linhas ofuscadas: Advogado(s), Expedição, Ano base (mostrar "Dr. ██████████", "██/██/████")
- **CTA principal** (w-full, btn-default, btn-lg, margin-top 16px):
  - **"Receber detalhes completos grátis →"**
  - Ao clicar: navegar para `/cadastro` passando processo e saldo via state
- Texto abaixo do CTA: "Por e-mail e WhatsApp. Sem spam." (text-xs text-muted-foreground text-center)
- Alert info: "Saldo sem atualização monetária. O valor real pode ser diferente." (mt-4)

#### Variante B — Sem saldo (saldo_depre = 0)
Card:
- Header: ponto cinza + "PROCESSO ENCONTRADO"
- Dados: Processo, Devedora, Status badge-secondary "Sem saldo"
- Alert info: "Este processo consta na base DEPRE, mas não possui saldo registrado no momento. Pode ter sido pago ou ainda não expedido como precatório."
- Botão: "Falar com especialista via WhatsApp" (btn-outline w-full)

#### Variante C — Suspenso (suspenso = true)
Card:
- Header: ponto amarelo/warning + "PROCESSO SUSPENSO"
- Dados: Processo, Devedora, Saldo DEPRE (exibir mesmo suspenso), Status badge-warning "Suspenso"
- Alert warning: **"Este processo está temporariamente suspenso. Pode haver ação judicial em curso."** + "Recomendamos consultar o advogado responsável."
- CTA: "Receber análise especializada grátis" (btn-default w-full)
- Botão secundário: "Nova consulta" (btn-ghost btn-sm w-full)

#### Variante D — Não encontrado
Card:
- Header: ponto vermelho + "NÃO ENCONTRADO"
- Alert error: **"Não encontramos este processo na nossa base. Verifique o número e tente novamente."** + dica de formato
- Botões: "Tentar com outro número" (btn-default w-full) + "Falar com suporte via WhatsApp" (btn-outline w-full)
- Separador + texto explicativo: "Seu processo pode não estar na base se foi movido em outra comarca, ainda não foi homologado como precatório, ou o número está em formato diferente."

---

## SUPERFÍCIE 2B — RESULTADO POR CPF (`/resultado/cpf/:cpf`) e CNPJ (`/resultado/cnpj/:cnpj`)

### Layout
- Navbar igual ao da landing
- Container max-w-2xl, margin auto, padding 28px 16px 64px
- Campo de busca preservado no topo (com valor mascarado), botão "Nova busca"

### Cabeçalho de resultado
- Linha superior (flex justify-between):
  - Esquerda: ponto verde + texto "X precatório(s) encontrado(s)" (text-sm font-semibold text-success)
  - Direita: "CPF: 123.***.***-00" ou "CNPJ: 12.***.***0001-90" (text-sm font-mono text-muted-foreground)
- Saldo total (somar todos os saldos_depre): label "Saldo total DEPRE" + valor grande em text-success (font-bold, text-2xl)
- Separador

### Lista de cards (1 card por precatório)
Cada card (`rounded-lg border bg-card shadow-sm`, padding 16px):
- Header do card: ponto colorido por status (verde=Ativo, amarelo=Suspenso, cinza=Sem saldo) + badge de status
- Linha: "Processo" / número em font-mono text-xs
- Linha: "Devedora" / nome
- Linha: "Saldo DEPRE" / valor formatado (font-semibold text-success se > 0, text-muted-foreground se = 0)
- Linha: "Natureza" / badge (Alimentar = badge-success, Outras = badge-secondary)
- Se suspenso: Alert warning inline no card

### CTA único ao final da lista
- Separador
- Texto: "Quer receber os detalhes completos de todos os seus precatórios?" (text-sm text-center text-muted-foreground)
- Botão: "Receber todos os detalhes grátis →" (btn-default btn-full btn-lg)
- Helper: "Por e-mail e WhatsApp. Sem spam." (text-xs text-center text-muted-foreground)

### Estado: CPF/CNPJ sem resultados
- Card único com alert info: "Não encontramos precatórios vinculados a este CPF/CNPJ na nossa base. Se você acredita que tem um precatório, verifique se o processo está em nome do titular correto ou consulte pelo número do processo."
- Botão: "Consultar por número de processo" (btn-outline)

---

## SUPERFÍCIE 3 — CAPTURA DE LEAD (`/cadastro`) — Step 2/4

### Layout
- Sem navbar completa (manter apenas logo). Fundo bg-muted
- Container centralizado max-w-sm (card), margin auto, padding 32px 16px

### Step indicator (4 passos, exibido no topo do card)
```
[✓] ——— [2] Seus dados ——— [3] Verificar ——— [4]
```
- Step 1 (completed): círculo verde com ✓
- Step 2 (active): círculo azul preenchido com "2" + label "Seus dados"
- Step 3 (pending): círculo cinza com "3" + label "Verificar"
- Step 4 (pending): círculo cinza com "4"
- Linhas conectoras entre steps (completed = verde, pending = cinza)

### Context card (bg-muted rounded-lg, padding 12px 14px)
Mostrar processo e saldo consultado em duas colunas:
- Esquerda: "Processo" (text-xs muted) / número em font-mono text-sm
- Direita: "Saldo DEPRE" (text-xs muted, text-right) / valor em font-bold text-success (16px)

### Formulário
- H2: "Receba os detalhes completos" (font-size 18px)
- Subtítulo: "Informe seus dados para receber o relatório gratuitamente. Sem spam." (text-sm muted)
- 4 campos obrigatórios:
  1. Nome completo (placeholder: "Maria Aparecida da Silva")
  2. E-mail (type email, helper: "Enviaremos o relatório para este e-mail")
  3. WhatsApp (type tel, mask (XX) XXXXX-XXXX, helper: "Para enviar o código de verificação")
  4. Relação com o processo (Select shadcn): "Selecione..." / "Sou o titular do precatório" / "Sou herdeiro do titular" / "Sou advogado do titular"

### Consentimento LGPD
- Separador
- Checkbox + label (text-xs): "Concordo em receber informações sobre este precatório por e-mail e WhatsApp. Posso solicitar exclusão dos meus dados a qualquer momento. [Política de privacidade (LGPD)]."

### CTA
- Botão: "Receber detalhes e verificar identidade →" (btn-default btn-full btn-lg)
- Validação inline: nome min 2 palavras, e-mail válido, telefone 10-11 dígitos, relação selecionada, consentimento marcado

---

## SUPERFÍCIE 4 — TOKEN EMAIL (`/verificar/email`) — Step 3a/4

### Layout igual ao `/cadastro`

### Step indicator
```
[✓] ——— [✓] ——— [3] Verificar ——— [4]
```

### Conteúdo
- Ícone envelope (48px, bg-primary-50 rounded-full, cor primary)
- H2: "Verifique seu e-mail"
- Subtítulo: "Enviamos um código de 6 dígitos para" + e-mail em bold

### Input OTP (6 dígitos)
- 6 inputs separados (48px x 56px cada), `gap-2`, `justify-center`
- font-size 22px, font-bold, text-center
- border-1.5 rounded-lg
- Auto-focus no primeiro campo vazio
- Ao preencher um dígito, focar automaticamente no próximo
- Ao colar (paste), distribuir os dígitos nos campos
- Campo preenchido: border-primary

### Timer
- "Expira em 8:42" (text-xs muted + countdown em font-semibold warning-dark)
- Implementar countdown regressivo de 10 minutos
- Ao chegar em 0, mostrar: "Código expirado. Solicite um novo."

### Botões
- "Confirmar código" (btn-default btn-full btn-lg)
- "Reenviar código · disponível em 45s" (btn-ghost btn-full btn-sm, desabilitado com countdown)
- Ao habilitar reenvio, mudar para "Reenviar código" clicável

### Texto auxiliar
- "Não encontrou? Verifique a pasta de spam."

### Lógica mock
- Token correto simulado: qualquer 6 dígitos numéricos é aceito (mock)
- Ao confirmar: navegar para `/verificar/whatsapp`

---

## SUPERFÍCIE 5 — TOKEN WHATSAPP (`/verificar/whatsapp`) — Step 3b/4

### Layout igual ao `/verificar/email`

### Step indicator igual ao 3a

### Alert de sucesso no topo
- Alert success: "E-mail verificado com sucesso. Agora confirme seu WhatsApp."

### Conteúdo
- Ícone WhatsApp (48px, bg-success-bg rounded-full, ícone verde WhatsApp SVG)
- H2: "Último passo: WhatsApp"
- Subtítulo: "Código enviado para" + telefone em bold

### Input OTP idêntico ao e-mail (6 dígitos)

### Timer e botões equivalentes

### Ao confirmar
- Navegar para `/obrigado`
- Salvar no localStorage: `{ validated: true, email, phone }` (mock de sessão persistente)

---

## SUPERFÍCIE 6 — OBRIGADO (`/obrigado`) — Step 4/4

### Step indicator
```
[✓] ——— [✓] ——— [✓] ——— [✓] Pronto
```
Todos completed (verde).

### Conteúdo (text-center)
- Ícone sucesso (64px, bg-success-bg rounded-full, check verde)
- H2: "Tudo pronto, [Nome]!" (personalizado com nome fornecido)
- Texto: "Enviamos o relatório completo para [email] e WhatsApp [telefone]."

### Resumo do precatório (box bg-muted rounded-lg, text-left)
- Label "SEU PRECATÓRIO" (uppercase text-xs muted)
- Processo (mono), Saldo DEPRE (text-success font-bold), Devedora

### Alert info
- "Nossa equipe pode entrar em contato para apresentar opções de **antecipação do recebimento**. Sem compromisso — você decide."

### CTA
- "Consultar outro processo" (btn-outline btn-full) → navegar para `/`

---

## SUPERFÍCIE 7 — ADMIN LOGIN (`/admin/login`)

### Layout
- Fundo bg-muted, centralizado vertical e horizontalmente
- Card max-w-sm (shadow-md rounded-xl)

### Conteúdo
- Logo: "Forjuris" (font-bold 16px) + "Acesso restrito ao painel administrativo" (text-sm muted)
- Campos: E-mail + Senha (type password)
- Separador
- Botão: "Entrar no painel" (btn-default btn-full btn-lg)
- Texto: "Autenticação via Supabase Auth. Sessão persistente." (text-xs muted text-center)

### Lógica mock
- Credenciais válidas: `admin@forjuris.com.br` / `admin123`
- Ao autenticar: salvar `{ isAuthenticated: true, email: "admin@forjuris.com.br" }` no localStorage
- Redirecionar para `/admin/leads`
- Se já autenticado, redirecionar automaticamente

---

## SUPERFÍCIE 8 — ADMIN LAYOUT (wrapper para /admin/*)

### Estrutura `AdminLayout`
```
┌──────────────────────────────────────────────────────┐
│ SIDEBAR (256px, sticky, height 100vh)                │
│ ┌─────────────────────────────────────────────────┐  │
│ │ Brand: "Forjuris" / "Painel Admin"│  │
│ ├─────────────────────────────────────────────────┤  │
│ │ Nav items:                                      │  │
│ │  ⊞ Visão geral      → /admin/funil             │  │
│ │  👥 Leads completos  → /admin/leads  [badge 12] │  │
│ │  ⚠ Incompletos     → /admin/incompletos        │  │
│ │  📊 Funil           → /admin/funil             │  │
│ ├─────────────────────────────────────────────────┤  │
│ │ User: avatar "A" + "Admin" + email              │  │
│ └─────────────────────────────────────────────────┘  │
│                                                      │
│ MAIN CONTENT (flex-1)                                │
│ ┌─────────────────────────────────────────────────┐  │
│ │ TOPBAR (56px, sticky, border-b)                 │  │
│ │ [Page title + subtitle]   [Actions + Bell badge]│  │
│ └─────────────────────────────────────────────────┘  │
│ [PAGE CONTENT — padding 24px]                        │
└──────────────────────────────────────────────────────┘
```

**Sidebar mobile**: hidden em viewport < 640px (adicionar menu hamburguer no topbar mobile).

**Badge de notificação**:
- Estado global: `newLeadsCount: number` (useState inicializado com 12)
- Incrementar simulando Supabase Realtime: `useEffect` que a cada 45 segundos incrementa 1 (simula novo lead)
- Exibido no sidebar item "Leads completos" e no ícone de sino do topbar
- Ao acessar `/admin/leads`, zerar o contador

**Dark mode toggle**: botão no topbar, funcional via next-themes ou classe `.dark` no `<html>`

---

## SUPERFÍCIE 9 — ADMIN LEADS (`/admin/leads`)

### Topbar
- Título: "Leads completos"
- Subtítulo: "327 leads · 12 novos hoje"
- Ações: botão "Exportar CSV" (ícone download) + sino com badge

### Filtros (card sem padding, border, bg-card)
Row de filtros (flex, gap-2, flex-wrap):
1. Input busca: "Buscar por nome, e-mail, processo..." (max-w-xs, height 36px)
2. Select status CRM: "Todos os status" / todos os 8 status (height 36px)
3. Select período: "7 dias" / "Hoje" / "30 dias" / "Custom" (height 36px)
4. Select faixa de saldo: "Todos os saldos" / "< R$1k" / "R$1k–10k" / "R$10k–100k" / "+R$100k" (height 36px)
5. Select devedora: "Todas" / "Fazenda SP" / "SPPREV" / "CBPM" / "IPESP" / "DER" / "Outros" (height 36px)
6. Select relação: "Todas" / "Titular" / "Herdeiro" / "Advogado" (height 36px)

**Quick filter chips** (abaixo dos filtros, flex gap-2 flex-wrap):
Pills clicáveis com contagem:
- "Todos (327)" (badge-default ativo)
- "Novo (12)" (badge-crm-novo)
- "Contatado (48)" (badge-crm-contatado)
- "Qualificado (21)" (badge-crm-qualificado)
- "Interessado (15)" (badge-crm-interessado)
- "Fechado (183)" (badge-crm-fechado)

### Tabela de leads
**Card** (padding 0, overflow-hidden):

| Nome | Processo | Saldo | Devedora | Relação | Status | Data | (ações) |
|------|----------|-------|----------|---------|--------|------|---------|

- Coluna Nome: nome em font-medium + email e telefone em text-xs muted abaixo
- Coluna Processo: `<code>` ou span com `font-mono text-sm font-semibold text-primary`
- Coluna Saldo: formatado R$ em font-semibold text-success (se > 0)
- Coluna Relação: badge-secondary (titular) / badge-secondary (herdeiro) / badge-default (advogado)
- Coluna Status: badge com cor CRM correspondente
- Coluna Data: text-xs muted ("Hoje 14:23", "Ontem 16:30", "23/05 09:14")
- Coluna ações: botão ícone lápis (quick-action, opacity-0 group-hover:opacity-100)
- **Clicar em qualquer linha**: abrir modal de detalhe do lead

**Comportamento de linha**: hover com elevação (`hover:-translate-y-px hover:shadow-sm`), zebra striping

**Paginação** (border-t, flex justify-between items-center, padding 12px 16px):
- "Mostrando 5 de 327 leads" (text-xs muted)
- Botões "← Anterior" (desabilitado na p1) / "Próxima →"

### Modal de detalhe do lead
Abrir ao clicar na linha. Dialog shadcn/ui (max-w-lg, shadow-xl rounded-xl):

**Header**:
- Título: nome do lead (font-semibold 18px)
- Subtítulo: "Lead #[id] · [data formatada]"
- Botão fechar (X)

**Body**:
1. **Pipeline de status** (flex gap-2 flex-wrap, mb-5):
   - 8 badges clicáveis representando os status (novo→fechado)
   - Status ativo: badge colorido. Inativos: badge-secondary com opacity reduzida
   - Clicar em um status: atualiza o `status_crm` do lead no estado mockado

2. **Dados do lead** (bg-muted rounded-lg, grid 2 colunas, padding 14px 16px):
   - E-mail, WhatsApp, Relação, Processo (mono), Saldo DEPRE (text-success font-bold), Devedora

3. **Notas internas** (textarea shadcn, label "Notas internas", min-h 70px, editável)

4. **Timeline** (seção "TIMELINE" em uppercase text-xs muted):
   - Usar dados de `mockLeadTimeline[lead.id]`
   - Cada item: dot colorido (success=verde, default=azul, muted=cinza) + linha vertical + conteúdo
   - label do evento (font-medium) + timestamp (text-xs muted)

**Footer**:
- "Fechar" (btn-outline btn-sm)
- "Marcar como [próximo status]" (btn-default btn-sm)

### Exportar CSV (mock)
Ao clicar no botão, gerar e baixar um arquivo `leads-[data].csv` com os dados mockados filtrados.

---

## SUPERFÍCIE 10 — ADMIN INCOMPLETOS (`/admin/incompletos`)

### Topbar
- Título: "Leads incompletos"
- Subtítulo: "Sessões que buscaram mas não completaram o cadastro"
- Botão: "Exportar CSV"

### Alert info (mb-4)
"Dados anônimos identificados por session_id. Nenhum dado pessoal exposto — LGPD compliant."

### Tabela

| Processo buscado | Saldo | Etapa de abandono | Dispositivo | Data/Hora |
|-----------------|-------|-------------------|-------------|-----------|

- Processo: font-mono text-sm text-primary
- Saldo: font-semibold text-success
- Etapa: badge-warning "Formulário abandonado" / "Token não confirmado" / badge-secondary "Saiu após resultado"
- Dispositivo: text-xs muted
- Data: text-xs muted

---

## SUPERFÍCIE 11 — ADMIN FUNIL (`/admin/funil`)

### Topbar
- Título: "Visão geral"
- Subtítulo: "Últimos 7 dias · Atualizado agora"
- Filtro de período: toggle de 3 botões ("7 dias" ativo, "30 dias", "Hoje") — btn-default o ativo, btn-outline os inativos
- Sino com badge

### Cards de métricas (grid 4 colunas, gap-4, mb-6 — 2 colunas em mobile)

| Visitantes | Consultas | Leads completos | Conversão total |
|-----------|-----------|----------------|----------------|
| 8.420 | 5.220 | 421 | 5,0% |
| ↑ +18% vs semana | ↑ +12% | ↑ +8% | ↓ -0,2pp |

Cada card: `rounded-lg border bg-card shadow-sm`, layout flex justify-between, ícone circular à direita (bg-primary-50 ou bg-success-bg).

### Card "Funil de conversão"

**Header do card**: título "Funil de conversão" + subtitle "Últimos 7 dias" + **toggle Gráfico/Tabela** (dois botões, o ativo usa btn-default, o inativo usa btn-outline)

#### Visão Gráfico (padrão):
6 linhas de funil horizontal com barras decrescentes:
```
Visitantes      [████████████████████████████] 8.420  100%
Buscas          [████████████████████     ] 5.220   62%
Resultados      [██████████████       ] 3.790   45%
Cadastros init. [█████         ] 1.516   18%
Tokens valid.   [███         ] 842     10%
Lead completo   [█         ] 421       5%  ← barra verde
```
- Barra: bg-primary, opacity decrescente (1.0 → 0.55)
- Última barra (Lead completo): bg-success
- Número absoluto dentro da barra (font-semibold white, font-size 12px)
- Percentual à direita (text-xs muted)

#### Visão Tabela (toggle):
Tabela com colunas: **Etapa** | **Total** | **% anterior** | **% topo**

| Visitantes | 8.420 | — | 100% |
| Buscas realizadas | 5.220 | badge-success 62,0% | 62,0% |
| Resultados encontrados | 3.790 | badge-success 72,6% | 45,0% |
| Cadastros iniciados | 1.516 | badge-warning 40,0% | 18,0% |
| Tokens validados | 842 | badge-warning 55,5% | 10,0% |
| **Lead completo** (bg-success-bg) | **421** | badge-success 50,0% | **5,0%** |

Abaixo da tabela: alert-warning "**Gargalo:** Resultado → Cadastro iniciado (40%). Oportunidade de melhoria na CTA pós-resultado."

### Card "Pipeline CRM"
Header: "Pipeline CRM" + link "Ver todos →" (text-primary)
Flex row, 6-8 mini-cards com contagem por status:

```
[12 Novos] [48 Contat.] [21 Qualif.] [15 Interes.] [8 Proposta] [183 Fechados]
```
Cada mini-card: padding 14px 10px, border-radius lg, cor de fundo correspondente ao CRM status, número em font-size 22px font-bold, label em text-xs font-semibold.

---

## ESTADO GLOBAL E CONTEXTO

### `src/contexts/SearchContext.tsx`
```typescript
interface SearchState {
  query: string
  result: Precatorio | null | "not_found" | "loading"
  setQuery: (q: string) => void
  setResult: (r: SearchState["result"]) => void
}
```

### `src/contexts/LeadContext.tsx`
```typescript
interface LeadState {
  processo: string | null
  saldo: number | null
  nome: string
  email: string
  telefone: string
  relacao: string
  emailValidado: boolean
  setLeadData: (data: Partial<LeadState>) => void
  reset: () => void
}
```

### `src/contexts/AuthContext.tsx` (admin mock)
```typescript
interface AuthState {
  isAuthenticated: boolean
  email: string | null
  login: (email: string, password: string) => Promise<boolean>
  logout: () => void
}
```
Persistir em localStorage com chave `consulta_precatorio_admin_auth`.

### `src/contexts/AdminContext.tsx`
```typescript
interface AdminState {
  leads: Lead[]
  newLeadsCount: number
  updateLeadStatus: (id: string, status: CrmStatus) => void
  updateLeadNotes: (id: string, notes: string) => void
  clearNewLeadsCount: () => void
}
```

---

## COMPONENTES REUTILIZÁVEIS

### Atoms
- `ProcessNumber`: exibição de número de processo em fonte mono
- `CurrencyDisplay`: formata centavos em R$ br
- `StatusBadge`: badge de status de precatório (Ativo/Suspenso/Sem saldo)
- `CrmBadge`: badge com cor correta por status CRM
- `RelacaoBadge`: badge Titular/Herdeiro/Advogado
- `OtpInput`: 6 inputs individuais com auto-focus e paste support

### Molecules
- `SearchBar`: input + botão "Consultar" com estado loading
- `StepIndicator`: stepper 4 passos com estados completed/active/pending
- `ProcessContextCard`: mini-card com processo + saldo (usado no formulário de captura)
- `FunnelChart`: gráfico de funil horizontal com barras
- `FunnelTable`: tabela de funil com conversões
- `LeadTimeline`: componente de timeline com dots e linhas
- `CrmPipeline`: row de mini-cards com contagens por status

### Organisms
- `ResultCard`: card de resultado com 4 variantes (active/no-balance/suspended/not-found)
- `LeadForm`: formulário de captura completo com validação
- `TokenVerificationForm`: OTP inputs + timer + reenvio
- `LeadDetailModal`: modal completo com dados, timeline, notas e pipeline de status
- `LeadsTable`: tabela com filtros, paginação e quick actions
- `IncompleteLeadsTable`: tabela de leads incompletos
- `AdminSidebar`: sidebar completo com navegação e badge
- `AdminTopbar`: topbar com título, ações e sino

---

## DETALHES TÉCNICOS CRÍTICOS

### 1. Busca inteligente com detecção automática de tipo
```typescript
// Único campo aceita 4 tipos de input — detectar automaticamente:
// CPF:    11 dígitos → findByCpf()  → rota /resultado/cpf/:cpf  → lista de precatórios
// CNPJ:   14 dígitos → findByCnpj() → rota /resultado/cnpj/:cnpj → lista de precatórios
// Processo (contém ".8.26."): findByProcesso() → rota /resultado/:processo → resultado único
// Desconhecido: validação inline sem navegar ("Formato não reconhecido. Ex: processo, CPF ou CNPJ")

// Normalizar antes de comparar: remover pontos, hífens, barras, espaços
const normalizeInput = (s: string) => s.replace(/[\s.\-\/]/g, "").toLowerCase()

// CPF/CNPJ exibidos mascarados no resultado (privacidade):
// CPF:  "123.***.***-00"
// CNPJ: "12.***.***\/0001-90"
```

### 2. Input OTP com auto-focus
```typescript
// Ao digitar um dígito, focar no próximo
// Ao apagar com backspace, voltar para o anterior
// Ao colar, distribuir nos campos
// Ao completar todos os 6, não auto-submeter (aguardar click no botão)
```

### 3. Countdown timer
```typescript
// Iniciar em 600 segundos (10 min)
// Exibir como "MM:SS"
// Mostrar em warning-dark quando < 2 min
// Ao zerar: desabilitar botão confirmar, mostrar mensagem de expiração
// Botão reenviar: desabilitado por 60 segundos, depois habilitar
```

### 4. Exportar CSV (mock)
```typescript
function exportToCSV(leads: Lead[]) {
  const headers = ["Nome", "Email", "Telefone", "Relacao", "Processo", "Saldo R$", "Devedora", "Status CRM", "Data"]
  const rows = leads.map(l => [
    l.nome, l.email, l.telefone, l.relacao,
    l.processo_depre, (l.saldo_consultado / 100).toFixed(2).replace(".", ","),
    l.devedora, l.status_crm,
    new Date(l.created_at).toLocaleDateString("pt-BR")
  ])
  const csv = [headers, ...rows].map(r => r.join(";")).join("\n")
  const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" })
  const url = URL.createObjectURL(blob)
  const a = document.createElement("a")
  a.href = url
  a.download = `leads-${new Date().toISOString().slice(0,10)}.csv`
  a.click()
}
```

### 5. Sessão persistente (mock)
```typescript
// Após validação de ambos os canais em /verificar/whatsapp:
const persistSession = (email: string, phone: string) => {
  localStorage.setItem("consulta_session", JSON.stringify({
    validated: true, email, phone,
    validatedAt: new Date().toISOString()
  }))
}

// No formulário /cadastro, verificar se sessão existe:
const session = localStorage.getItem("consulta_session")
if (session) {
  const { validated, email, phone } = JSON.parse(session)
  // Pré-preencher campos, pular validação de token
}
```

### 6. Formatação monetária BR
```typescript
// SEMPRE usar:
new Intl.NumberFormat("pt-BR", { style: "currency", currency: "BRL" }).format(centavos / 100)
// Resultado: "R$ 147.832,00"
// NUNCA usar: toLocaleString com vírgulas manuais
```

### 7. Dark mode
- Implementar via classe `.dark` no `<html>` usando `next-themes` ou classe manual via localStorage
- Botão no navbar público e no topbar admin
- Todos os tokens CSS com variáveis `hsl()` corretamente alternando em `.dark`
- Ícone: sol em modo claro, lua em modo escuro

### 8. Proteção de rotas admin
```typescript
// ProtectedRoute component
function ProtectedRoute({ children }) {
  const { isAuthenticated } = useAuth()
  if (!isAuthenticated) return <Navigate to="/admin/login" replace />
  return children
}

// Rota /admin redireciona para /admin/leads
<Route path="/admin" element={<Navigate to="/admin/leads" replace />} />
```

### 9. Simulação de Supabase Realtime (badge)
```typescript
// No AdminContext, simular novo lead a cada 45 segundos
useEffect(() => {
  const interval = setInterval(() => {
    setNewLeadsCount(prev => prev + 1)
  }, 45000)
  return () => clearInterval(interval)
}, [])
```

### 10. Paginação da tabela
- Estado: `currentPage` (default 1), `pageSize` (default 20)
- Filtros aplicados localmente sobre `mockLeads`
- Mostrar "Mostrando X de Y leads"
- Botões anterior/próximo

---

## ESTRUTURA DE ARQUIVOS SUGERIDA

```
src/
├── components/
│   ├── atoms/
│   │   ├── ProcessNumber.tsx
│   │   ├── CurrencyDisplay.tsx
│   │   ├── StatusBadge.tsx
│   │   ├── CrmBadge.tsx
│   │   └── OtpInput.tsx
│   ├── molecules/
│   │   ├── SearchBar.tsx
│   │   ├── StepIndicator.tsx
│   │   ├── ProcessContextCard.tsx
│   │   ├── FunnelChart.tsx
│   │   ├── FunnelTable.tsx
│   │   └── LeadTimeline.tsx
│   ├── organisms/
│   │   ├── ResultCard.tsx
│   │   ├── LeadForm.tsx
│   │   ├── TokenVerificationForm.tsx
│   │   ├── LeadDetailModal.tsx
│   │   ├── LeadsTable.tsx
│   │   ├── IncompleteLeadsTable.tsx
│   │   ├── AdminSidebar.tsx
│   │   └── AdminTopbar.tsx
│   └── layouts/
│       ├── PublicLayout.tsx
│       └── AdminLayout.tsx
├── contexts/
│   ├── SearchContext.tsx
│   ├── LeadContext.tsx
│   ├── AuthContext.tsx
│   └── AdminContext.tsx
├── pages/
│   ├── LandingPage.tsx
│   ├── ResultadoPage.tsx
│   ├── CadastroPage.tsx
│   ├── VerificarEmailPage.tsx
│   ├── VerificarWhatsappPage.tsx
│   ├── ObrigadoPage.tsx
│   ├── admin/
│   │   ├── AdminLoginPage.tsx
│   │   ├── AdminLeadsPage.tsx
│   │   ├── AdminIncompletosPage.tsx
│   │   └── AdminFunilPage.tsx
├── data/
│   └── mockData.ts
├── lib/
│   ├── format.ts
│   └── utils.ts
└── App.tsx
```

---

## MENSAGENS DE UI — USAR EXATAMENTE

| Contexto | Mensagem exata |
|---------|----------------|
| H1 landing | "Consulte Gratis o Valor do Seu Precatório SP" |
| Subtítulo landing | "Base com mais de 200 mil processos do DEPRE. Resultado em segundos." |
| CTA principal | "Consultar Agora" |
| CTA resultado → cadastro | "Receber detalhes completos grátis" |
| CTA suspenso | "Receber análise especializada grátis" |
| Não encontrado | "Não encontramos este processo na nossa base. Verifique o número e tente novamente." |
| Suspenso | "Este processo está temporariamente suspenso. Pode haver ação judicial em curso." |
| Sem saldo | "Este processo consta na base DEPRE, mas não possui saldo registrado no momento." |
| Token expirado | "O código expirou. Clique em 'Reenviar' para receber um novo código." |
| Token incorreto | "Código incorreto. Verifique e tente novamente." |
| Obrigado título | "Tudo pronto, [Nome]!" |
| Obrigado subtítulo | "Enviamos o relatório completo para [email] e WhatsApp [telefone]." |
| Botão loader | "Consultando..." |
| Botão login | "Entrar no painel" |
| Trust item 1 | "Sem cadastro prévio" |
| Trust item 2 | "Dados do TJSP/DEPRE" |
| Disclaimer saldo | "Saldo sem atualização monetária. O valor real pode ser diferente." |
| Eyebrow landing | "Dados públicos oficiais do DEPRE · Gratuito · Resultado em segundos" |

---

## CHECKLIST DE QUALIDADE

Antes de concluir, verificar que:

- [ ] Todas as 11 superfícies estão implementadas e navegáveis
- [ ] Dark mode funciona em todas as páginas (portal público e admin)
- [ ] Busca aceita número com e sem formatação (pontos e hífens)
- [ ] Formatação monetária usa padrão brasileiro (R$ 147.832,00)
- [ ] Step indicator mostra estados corretos em cada etapa do fluxo
- [ ] OTP inputs: auto-focus, paste support, backspace volta ao anterior
- [ ] Countdown timer decrescente com aviso visual ao ficar vermelho
- [ ] Modal de lead: timeline, pipeline CRM clicável, notas editáveis
- [ ] Tabela de leads: filtros funcionais, busca full-text, ordenação, paginação
- [ ] Toggle Gráfico/Tabela no funil alterna visualmente
- [ ] Badge de notificação incrementa automaticamente (simulação)
- [ ] Clicar no badge leva para /admin/leads filtrado por "Novo"
- [ ] Rota /admin/login redireciona se já autenticado
- [ ] Rotas /admin/* redirecionam para login se não autenticado
- [ ] Exportar CSV gera arquivo com dados formatados corretamente
- [ ] Layout responsivo: todas as telas funcionam em 375px (mobile) e 1440px (desktop)
- [ ] Em mobile: campo de busca e botão empilhados (flex-col w-full)
- [ ] Em mobile: sidebar admin oculta, substituída por menu hamburger
- [ ] Em mobile: modal de lead ocupa 95% da tela (bottom sheet pattern)
- [ ] Animação de loading (skeleton) durante busca
- [ ] Estado vazio na tabela de leads quando filtros não retornam resultados
- [ ] Não há lorem ipsum em nenhum lugar — apenas dados realistas em PT-BR
- [ ] Todos os textos em português, sem mistura com inglês
- [ ] Sora + Inter + Fira Code carregadas corretamente do Google Fonts
- [ ] Headings (h1–h3) usam Sora, body/UI usa Inter, números de processo usam Fira Code

---

## CONFIGURAÇÃO SUPABASE (para integração posterior)

O Lovable deve criar o projeto com Supabase integrado. As seguintes tabelas serão criadas via migration:

```sql
-- Tabela de precatórios (leitura pública)
CREATE TABLE precatorios (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  processo_depre VARCHAR NOT NULL,
  autos VARCHAR,
  natureza VARCHAR,
  suspenso BOOLEAN DEFAULT false,
  data_protocolo DATE,
  devedora VARCHAR NOT NULL,
  natureza_saldo VARCHAR,
  saldo_depre BIGINT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_precatorios_processo ON precatorios(processo_depre);
CREATE INDEX idx_precatorios_autos ON precatorios(autos);
ALTER TABLE precatorios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "public_read" ON precatorios FOR SELECT TO anon, authenticated USING (true);

-- Tabela de leads (acesso somente via Edge Functions)
CREATE TABLE leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nome VARCHAR NOT NULL,
  email VARCHAR NOT NULL,
  telefone VARCHAR,
  relacao VARCHAR CHECK (relacao IN ('titular','herdeiro','advogado')),
  processo_depre VARCHAR REFERENCES precatorios(processo_depre),
  saldo_consultado BIGINT,
  devedora VARCHAR,
  token_email_validado BOOLEAN DEFAULT false,
  token_telefone_validado BOOLEAN DEFAULT false,
  status_crm VARCHAR DEFAULT 'novo',
  notas TEXT,
  consent_comunicacao BOOLEAN DEFAULT false,
  consent_marketing BOOLEAN DEFAULT false,
  origem VARCHAR,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE leads ENABLE ROW LEVEL SECURITY;
-- Somente admin autenticado pode ler
CREATE POLICY "admin_access_leads" ON leads FOR ALL TO authenticated USING (true);

-- Tabela de tokens
CREATE TABLE tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id UUID REFERENCES leads(id),
  canal VARCHAR CHECK (canal IN ('email','telefone')),
  expira_em TIMESTAMPTZ,
  tentativas INT DEFAULT 0,
  validado BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE tokens ENABLE ROW LEVEL SECURITY;

-- Tabela de eventos do funil
CREATE TABLE funnel_events (
  id BIGSERIAL PRIMARY KEY,
  session_id UUID NOT NULL,
  event_name TEXT NOT NULL,
  context JSONB,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX idx_funnel_session ON funnel_events(session_id);
CREATE INDEX idx_funnel_event_name ON funnel_events(event_name);
ALTER TABLE funnel_events ENABLE ROW LEVEL SECURITY;
```

**Variáveis de ambiente necessárias** (configurar no Lovable):
```
VITE_SUPABASE_URL=<url do projeto>
VITE_SUPABASE_ANON_KEY=<chave anon pública>
```

---

## OBSERVAÇÕES FINAIS

1. **Prioridade de fidelidade**: Os protótipos HTML em `docs/prototypes/consulta-precatorio-mvp/` são a referência visual canônica. Replicar a UX exatamente, incluindo espaçamentos, tipografia e comportamentos descritos.

2. **Mock data é lei**: Todos os dados mockados descritos neste prompt devem estar presentes e visíveis. A tabela de leads deve ter exatamente os 5 leads descritos. O funil deve usar os números exatos do `mockFunnelStats`.

3. **Sem placeholder**: Não usar "Lorem ipsum" em nenhum lugar. Todo texto deve ser em português e contextualizado para o produto.

4. **Mobile-first sempre**: O breakpoint de referência para mobile é 375px. Testar que a busca hero, os formulários de OTP e a tabela de leads funcionam corretamente em mobile.

5. **shadcn/ui apenas**: Usar exclusivamente componentes do shadcn/ui (Button, Input, Select, Dialog, Badge, Card, Table, Accordion, Separator, Alert, Textarea). Não criar componentes UI do zero quando existir equivalente no shadcn.

6. **Sem back-end chamadas reais**: Todo o fluxo deve funcionar com dados mock. Os tokens OTP aceitar qualquer 6 dígitos. O login aceitar apenas `admin@forjuris.com.br` / `admin123`. A busca de precatório consultar apenas o array `mockPrecatorios`.

7. **Navegação 100%**: Toda a navegação deve funcionar sem erros de rota. Usar React Router v6 com `<BrowserRouter>`. Todas as rotas listadas devem ser acessíveis.
