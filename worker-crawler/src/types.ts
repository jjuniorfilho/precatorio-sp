// Tipos do crawler — espelham o schema FOR-69.

export type Esfera = "Estadual" | "Municipal" | "Outro";
export type TipoPrevisto = "Precatorio" | "RPV" | "Indefinido";
export type StatusBruto = "ativo" | "suspenso" | "extinto" | "arquivado";
export type Fonte = "esaj" | "djen";

export interface QueueJob {
  id: string;
  processo_codigo: string; // SEED: CNJ (numero unificado) — ver README (contrato da fila)
  status: string;
  origem: string | null;
  tentativas: number;
}

export interface Advogado {
  nome: string;
  oab: string | null;
  oab_normalizada: string | null;
  sem_oab: boolean;
}

export interface ParteAtiva {
  nome: string | null;
  documento: string | null; // só dígitos
  advogados: Advogado[];
}

export interface PartePassiva {
  nome: string | null;
  ente_esfera: Esfera;
}

export interface Andamento {
  data: string | null; // ISO yyyy-mm-dd
  descricao: string;
  arquivo_url: string | null;
}

export interface IncidenteData {
  processo_codigo: string;            // código interno e-SAJ do incidente
  numero_incidente: string | null;    // 00001...
  tipo_previsto: TipoPrevisto;
  numero_depre: string | null;        // .8.26.0500
  cnj: string | null;
  status: StatusBruto | null;
  tramitacao_prioritaria: boolean;    // capa (FOR-71)
  valor_acao: number | null;          // centavos
  data_base: string | null;
  parte_ativa: ParteAtiva | null;
  parte_passiva: PartePassiva | null;
  andamentos: Andamento[];
}

export interface CumprimentoData {
  processo_codigo: string;
  cnj: string | null;
  incidentes: IncidenteData[];        // pode conter 1 placeholder 'Indefinido' (Opção A)
}

export interface ProcessoTree {
  processo_codigo: string;            // raiz (código interno e-SAJ)
  cnj: string | null;
  foro: string | null;
  classe: string | null;
  assunto: string | null;
  distribuicao: string | null;
  valor_acao: number | null;
  data_base: string | null;
  status: StatusBruto | null;
  cumprimentos: CumprimentoData[];
}
