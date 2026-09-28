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

/** FOR-173 — eventos que o coletor publica para observadores (o reporter de progresso).
 * `passo`: uma etapa CONCLUÍDA (é registrada depois de terminar); `iniciar`: a vez na fila do Playwright
 * chegou (não vira passo do log); `tentativa`: a tentativa N de captcha COMEÇOU (idem, não vira passo). */
export type EventoColetor =
  | { tipo: "passo"; passo: Passo; tentativas: number }
  | { tipo: "iniciar" }
  | { tipo: "tentativa"; tentativa: number };
export type ObservadorColetor = (e: EventoColetor) => void;

export class PassosCollector {
  readonly passos: Passo[] = [];
  tentativas = 0;
  private readonly observadores: ObservadorColetor[] = [];

  /** Registra um observador. Exceção de observador NUNCA propaga: observar é auxiliar e não pode
   * derrubar a consulta (FOR-173). */
  observar(cb: ObservadorColetor): void {
    this.observadores.push(cb);
  }

  private notificar(e: EventoColetor): void {
    for (const o of this.observadores) {
      try {
        o(e);
      } catch {
        /* observador é best-effort */
      }
    }
  }

  passo(etapa: Etapa, status: PassoStatus, detalhe?: string): void {
    const p: Passo = { etapa, status, at: new Date().toISOString(), ...(detalhe ? { detalhe } : {}) };
    this.passos.push(p);
    this.notificar({ tipo: "passo", passo: p, tentativas: this.tentativas });
  }

  /** A vez na fila do Playwright chegou (a consulta vai começar de fato). Não acrescenta passo. */
  iniciar(): void {
    this.notificar({ tipo: "iniciar" });
  }

  /** A tentativa `n` de captcha vai começar. Atribui `tentativas` e notifica SEM acrescentar passo, para o
   * log do FOR-171 ficar idêntico ao de antes. */
  tentativa(n: number): void {
    this.tentativas = n;
    this.notificar({ tipo: "tentativa", tentativa: n });
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
