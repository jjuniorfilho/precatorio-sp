// Entrypoint mínimo — SÓ o endpoint HTTP de "valor pago" (POST /valor-pago), sem o loop
// principal de coleta (claim/crawl/persist do crawler_queue) nem nada relacionado a ele.
//
// Contexto (2026-10-03): o worker completo (`index.ts`, pm2 `precatorio-crawler`) está parado a
// pedido do usuário enquanto o FOR-195/196 não é validado — nenhum job do e-SAJ pode ser
// processado. Mas `disparar-valor-pago` (consulta manual de pagamento no admin) depende do MESMO
// servidor HTTP (`http-server.ts`), que por acaso sobe dentro do MESMO processo que o loop
// principal em `index.ts` — então parar o processo inteiro derrubou os dois juntos (502 em
// crawler.forjuris.com.br), mesmo o endpoint de valor-pago sendo tecnicamente independente
// (consultarEPersistirPagamentos não usa claimJobs/crawler_queue nem crawlSeed/e-SAJ cpopg).
//
// Este arquivo existe só pra separar as duas coisas: sobe `startHttpServer()` sozinho, autenticado
// (precisa pra persistir o resultado da consulta no Supabase), SEM nunca chamar `tick()`/
// `claimJobs()`/o loop de `index.ts`. Rodar via pm2 como processo SEPARADO (ex.:
// "precatorio-valor-pago"), nunca substituindo `precatorio-crawler` (que continua parado).
//
// Remover/aposentar este arquivo quando o worker completo for religado — nesse ponto
// `index.ts` já cobre o mesmo endpoint, rodando os dois junto não tem efeito colateral (a
// BIND de porta é que não pode colidir — pare este processo antes de religar o `index.ts`).
import { assertConfig } from "./config.js";
import { ensureAuth } from "./supabase.js";
import { startHttpServer } from "./http-server.js";

async function main(): Promise<void> {
  assertConfig();
  await ensureAuth();
  console.log("http-only: SÓ o endpoint /valor-pago — loop de coleta do e-SAJ NÃO está rodando.");
  startHttpServer();
}

main().catch((err) => {
  console.error("fatal:", err);
  process.exit(1);
});
