// FOR-171 — Classificação do resultado da busca no portal TJSP "Pagamentos Precatórios".
// Função PURA sobre o HTML da página de resultado (testada com fixtures reais em
// src/__fixtures__/pagamentos/, capturadas em 25/09/2026).
//
// Sinais (validados no portal real):
//  - Linha da grade `span_PRP_SITUACAO_ANDAMENTO_*`: existe só quando há resultado.
//  - Mensagem `span#TXTNENHUM` ("Não foram encontrados Processos…"): está SEMPRE no HTML, mas só
//    fica visível quando não há resultado (sem resultado: visível; com resultado: display:none).
//    O estado GeneXus serializado (`TXTNENHUM_Visible`: "1"/"0") é o sinal server-side, indep. de CSS.
//  - Rodapé "Data da Consulta" aparece nos DOIS casos: só prova que a busca terminou, não discrimina.
// Regra: encontrado = linha da grade; nao_consta = URL de resultado + TXTNENHUM visível
// (server-side E inline) + grade vazia + rodapé; qualquer outra coisa = falha (default seguro).
import { load } from "cheerio";

export type ResultadoConsulta = "encontrado" | "nao_consta" | "falha";

export interface Classificacao {
  resultado: ResultadoConsulta;
  situacao: string | null;
  /** "dd/mm/aaaa" (+ " hh:mm:ss" se o portal informar a hora) do rodapé Data da Consulta. */
  dataConsultaPortal: string | null;
  /** Explicação curta (vai para o passo "ler_resultado" do log). */
  motivo: string;
}

const RESULTADO_URL_RE = /pesquisainternetnumanoep\.aspx/;

/** Lê `TXTNENHUM_Visible` do GXState (entidades HTML já decodificadas pelo cheerio, ou cru). */
function gxTxtNenhumVisible(html: string): "0" | "1" | null {
  const m = /TXTNENHUM_Visible(?:&quot;|")\s*:\s*(?:&quot;|")([01])(?:&quot;|")/.exec(html);
  return m ? (m[1] as "0" | "1") : null;
}

export function classificarHtml(html: string, url: string): Classificacao {
  const falha = (motivo: string): Classificacao => ({ resultado: "falha", situacao: null, dataConsultaPortal: null, motivo });

  if (!RESULTADO_URL_RE.test(url)) return falha(`URL fora do padrão de resultado (${url})`);

  const $ = load(html);
  const rodape = $("#TEXTBLOCK3").text().includes("Data da Consulta") || /Data da Consulta/i.test($("body").text());
  const data = ($("#vDATA_CONSULTA").attr("value") ?? "").trim();
  const hora = ($("#vHORA_CONSULTA").attr("value") ?? "").trim();
  const dataConsultaPortal = data ? (hora ? `${data} ${hora}` : data) : null;

  const linha = $('span[id^="span_PRP_SITUACAO_ANDAMENTO_"]').first();
  if (linha.length > 0) {
    return { resultado: "encontrado", situacao: linha.text().trim() || null, dataConsultaPortal, motivo: "linha da grade encontrada" };
  }

  if (!rodape) return falha('rodapé "Data da Consulta" ausente (página incompleta ou inesperada)');

  const msg = $("#TXTNENHUM");
  if (msg.length === 0) return falha("mensagem TXTNENHUM ausente e grade vazia");
  const gx = gxTxtNenhumVisible(html);
  const inlineOculto = /display\s*:\s*none/i.test(msg.attr("style") ?? "");
  if (gx !== "1") return falha(`mensagem "não encontrados" não visível (TXTNENHUM_Visible=${gx ?? "ausente"}) e grade vazia`);
  if (inlineOculto) return falha("sinais divergentes: TXTNENHUM_Visible=1 mas a mensagem está com display:none");

  return {
    resultado: "nao_consta",
    situacao: null,
    dataConsultaPortal,
    motivo: 'mensagem "Não foram encontrados" visível, grade vazia, rodapé presente',
  };
}
