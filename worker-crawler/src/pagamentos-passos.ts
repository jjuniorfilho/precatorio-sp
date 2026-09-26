// FOR-171 — Coletor de passos da consulta ao portal TJSP "Pagamentos Precatórios".
// Alimenta o log "Consultas ao TJSP" do admin: cada passo tem horário, status e etapa, de modo
// que uma falha mostre em que etapa parou. Sem dependências (puro, testável).

export type PassoStatus = "ok" | "erro" | "info";

/** Etapas do fluxo (chave estável, o frontend traduz para rótulo). */
export type Etapa =
  | "abrir_portal"
  | "obter_link"
  | "abrir_pesquisa"
  | "busca"
  | "resultado_carregou"
  | "ler_resultado"
  | "extrair_pagamentos"
  | "persistir"
  | "desconhecida";

export interface Passo {
  etapa: Etapa;
  status: PassoStatus;
  at: string; // ISO
  detalhe?: string;
}

export class PassosCollector {
  readonly passos: Passo[] = [];
  tentativas = 0;

  passo(etapa: Etapa, status: PassoStatus, detalhe?: string): void {
    this.passos.push({ etapa, status, at: new Date().toISOString(), ...(detalhe ? { detalhe } : {}) });
  }

  /** Etapa do último passo com erro (ou null). */
  etapaDoErro(): Etapa | null {
    for (let i = this.passos.length - 1; i >= 0; i--) {
      if (this.passos[i]!.status === "erro") return this.passos[i]!.etapa;
    }
    return null;
  }
}

/** Erro de consulta com a etapa em que parou (o http-server devolve `etapa` ao admin). */
export class ConsultaPagamentoErro extends Error {
  constructor(
    message: string,
    readonly etapa: Etapa,
    readonly passos: PassosCollector,
  ) {
    super(message);
    this.name = "ConsultaPagamentoErro";
  }
}
