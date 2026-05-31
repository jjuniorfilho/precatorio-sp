// Mock data for Consulta Precatório SP

export type CrmStatus =
  | "novo"
  | "contatado"
  | "qualificado"
  | "interessado"
  | "proposta"
  | "negociacao"
  | "fechado"
  | "descartado";

export type Relacao = "titular" | "herdeiro" | "advogado";

export interface Precatorio {
  id: string;
  processo_depre: string;
  autos: string;
  devedora: string;
  saldo_depre: number;
  natureza: string;
  status: string;
  suspenso: boolean;
  data_protocolo: string;
  autor: string;
  cpf: string;
}

export interface Lead {
  id: string;
  nome: string;
  email: string;
  telefone: string;
  relacao: Relacao;
  processo_depre: string;
  saldo_consultado: number;
  devedora: string;
  status_crm: CrmStatus;
  notas: string;
  token_email_validado: boolean;
  token_telefone_validado: boolean;
  created_at: string;
}

export interface LeadIncompleto {
  session_id: string;
  processo_buscado: string;
  saldo_encontrado: number;
  etapa_abandono: string;
  dispositivo: string;
  data: string;
}

export const mockPrecatorios: Precatorio[] = [
  {
    id: "1",
    processo_depre: "0122089-09.2025.8.26.0500",
    autos: "0122089-09.2025.8.26.0500",
    devedora: "Fazenda do Estado de SP",
    saldo_depre: 14783200,
    natureza: "Alimentar",
    status: "Ativo",
    suspenso: false,
    data_protocolo: "2025-03-15",
    autor: "Maria Aparecida da Silva",
    cpf: "123.456.789-09",
  },
  {
    id: "2",
    processo_depre: "0033421-14.2023.8.26.0100",
    autos: "0033421-14.2023.8.26.0100",
    devedora: "SPPREV",
    saldo_depre: 0,
    natureza: "Outras",
    status: "Sem saldo",
    suspenso: false,
    data_protocolo: "2023-07-20",
    autor: "João Carlos Pereira",
    cpf: "987.654.321-00",
  },
  {
    id: "3",
    processo_depre: "0006248-79.2024.8.26.0506",
    autos: "0006248-79.2024.8.26.0506",
    devedora: "CBPM",
    saldo_depre: 8920000,
    natureza: "Outras",
    status: "Suspenso",
    suspenso: true,
    data_protocolo: "2024-01-10",
    autor: "Roberto Henrique Almeida",
    cpf: "456.789.123-45",
  },
];

export const mockLeads: Lead[] = [
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
    notas:
      "Ligou às 15h. Demonstrou interesse em antecipar. Pediu para ligar amanhã pela manhã.",
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
];

export const mockLeadsIncompletos: LeadIncompleto[] = [
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
];

export const mockFunnelStats = {
  visitantes: 8420,
  buscas: 5220,
  resultados: 3790,
  cadastrosIniciados: 1516,
  tokensValidados: 842,
  leadsCompletos: 421,
};

export const mockLeadTimeline: Record<
  string,
  { evento: string; tempo: string; tipo: "success" | "default" | "muted" }[]
> = {
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
};

export const mockCrmPipeline: Record<CrmStatus, number> = {
  novo: 12,
  contatado: 48,
  qualificado: 21,
  interessado: 15,
  proposta: 8,
  negociacao: 4,
  fechado: 183,
  descartado: 36,
};

export const crmStatusOrder: CrmStatus[] = [
  "novo",
  "contatado",
  "qualificado",
  "interessado",
  "proposta",
  "negociacao",
  "fechado",
  "descartado",
];

export const crmStatusLabel: Record<CrmStatus, string> = {
  novo: "Novo",
  contatado: "Contatado",
  qualificado: "Qualificado",
  interessado: "Interessado",
  proposta: "Proposta",
  negociacao: "Negociação",
  fechado: "Fechado",
  descartado: "Descartado",
};
