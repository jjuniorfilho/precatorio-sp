// FOR-173 — Reporter de PROGRESSO da consulta de valor pago ao portal TJSP.
//
// Publica o andamento da consulta em `pagamentos_consultas_progresso` (uma linha por DEPRE) para o admin
// mostrar uma barra de progresso real. Regras que não podem ser quebradas:
//   * NUNCA lança nem atrasa a consulta: progresso é auxiliar. Erro do registrar vai só para o console.
//   * Escritas SAEM EM ORDEM (cadeia serial de promises), nunca em paralelo — senão um passo atrasado
//     poderia sobrescrever o estado final.
//   * `etapa` = etapa EM ANDAMENTO. O coletor registra os passos DEPOIS de concluídos, então "concluí X"
//     vira "agora está em PROXIMA[X]"; `tentativa(n)` marca `busca` em andamento com a tentativa N.
//   * `detalhe` nunca leva texto de passo `erro` (traz mensagem crua de exceção); só os textos curados dos
//     passos `ok`/`info`. A falha é comunicada por `etapa_falha`.
import type { Etapa, EventoColetor, PassosCollector } from "./pagamentos-passos.js";
import type { RegistroProgressoPagamento } from "./supabase.js";

export type RegistrarProgresso = (r: RegistroProgressoPagamento) => Promise<void>;

export interface OpcoesReporter {
  processoDepre: string;
  origem: RegistroProgressoPagamento["origem"];
  maxTentativas: number;
  registrar: RegistrarProgresso;
  /** Destino do erro engolido do `registrar` (default: console.error). Injetável para teste. */
  log?: (msg: string, err: unknown) => void;
}

export interface ProgressoReporter {
  /** Cria a linha em `na_fila` (renova `iniciada_em`). Chamar ANTES de entrar na fila do Playwright. */
  naFila(): void;
  /** Observa o coletor de passos da consulta. */
  ligar(passos: PassosCollector): void;
  /** Consulta terminou com resultado válido. */
  concluir(resultado: "encontrado" | "nao_consta"): void;
  /** Consulta falhou; `etapaFalha` = etapa em que parou. */
  falhar(etapaFalha: string | null): void;
  /** Espera as escritas pendentes (com teto) para o estado final não ser ultrapassado por um passo atrasado. */
  drenar(timeoutMs?: number): Promise<void>;
}

/** Etapa em andamento logo depois de `etapa` ter sido concluída com sucesso. */
const PROXIMA: Record<Etapa, string> = {
  abrir_portal: "obter_link",
  obter_link: "abrir_pesquisa",
  abrir_pesquisa: "busca",
  busca: "busca", // (passo `info`: captcha rejeitado → próxima tentativa; o passo `ok` é tratado em proximaEtapa)
  resultado_carregou: "ler_resultado",
  ler_resultado: "extrair_pagamentos", // no `nao_consta` não há extração e o próximo trabalho real já é persistir (ms)
  extrair_pagamentos: "persistir",
  persistir: "persistir",
  desconhecida: "desconhecida",
};

/** Etapa em andamento depois de um passo concluído. `busca` + `ok` = a busca passou → carregar resultado. */
export function proximaEtapa(etapa: Etapa, status: "ok" | "erro" | "info"): string {
  if (etapa === "busca" && status === "ok") return "resultado_carregou";
  return PROXIMA[etapa];
}

export function criarReporter(op: OpcoesReporter): ProgressoReporter {
  const log = op.log ?? ((msg, err) => console.error(`[progresso] ${msg} (${op.processoDepre}):`, err));
  let cadeia: Promise<void> = Promise.resolve();
  let tentativaAtual = 0;

  const enfileirar = (r: Omit<RegistroProgressoPagamento, "processoDepre" | "maxTentativas" | "origem">): void => {
    const registro: RegistroProgressoPagamento = {
      processoDepre: op.processoDepre,
      maxTentativas: op.maxTentativas,
      origem: op.origem,
      ...r,
    };
    // A cadeia nunca rejeita: cada escrita engole o próprio erro. Sequencial por construção.
    cadeia = cadeia.then(() => op.registrar(registro)).catch((e) => log("registrar falhou", e));
  };

  const emAndamento = (etapa: string, detalhe: string | null): void =>
    enfileirar({ estado: "em_andamento", etapa, tentativa: tentativaAtual, detalhe, resultado: null, etapaFalha: null, nova: false });

  return {
    naFila() {
      enfileirar({ estado: "na_fila", etapa: "na_fila", tentativa: 0, detalhe: null, resultado: null, etapaFalha: null, nova: true });
    },
    ligar(passos: PassosCollector) {
      passos.observar((e: EventoColetor) => {
        if (e.tipo === "iniciar") {
          emAndamento("iniciando", null);
        } else if (e.tipo === "tentativa") {
          tentativaAtual = e.tentativa;
          emAndamento("busca", `Tentativa ${e.tentativa} de ${op.maxTentativas}`);
        } else {
          tentativaAtual = e.tentativas;
          // Passo de erro: não publica (a falha sai por falhar(), sem a mensagem crua da exceção).
          if (e.passo.status === "erro") return;
          emAndamento(proximaEtapa(e.passo.etapa, e.passo.status), e.passo.detalhe ?? null);
        }
      });
    },
    concluir(resultado) {
      enfileirar({ estado: "concluida", etapa: "persistir", tentativa: tentativaAtual, detalhe: null, resultado, etapaFalha: null, nova: false });
    },
    falhar(etapaFalha) {
      enfileirar({ estado: "falha", etapa: etapaFalha ?? "desconhecida", tentativa: tentativaAtual, detalhe: null, resultado: "falha", etapaFalha, nova: false });
    },
    async drenar(timeoutMs = 3000) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      const teto = new Promise<void>((res) => {
        timer = setTimeout(res, timeoutMs);
      });
      try {
        await Promise.race([cadeia, teto]);
      } finally {
        if (timer) clearTimeout(timer);
      }
    },
  };
}
