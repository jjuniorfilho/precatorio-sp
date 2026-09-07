// FOR-102 — Endpoint HTTP síncrono: POST /valor-pago { processo_depre }.
// Chamado pela edge function `buscar-precatorio` (busca pública, síncrono — Fase 6) e pelo
// disparo manual do admin (Fase 7). Node `http` nativo — sem framework novo, um endpoint só.
//
// Exposição: nesta fase o servidor só escuta em 127.0.0.1 (teste local via curl na VPS). A
// exposição pública (nginx + decisão de segurança/HTTPS) fica pra Fase 6, quando o
// buscar-precatorio (fora da VPS) de fato precisar alcançá-lo pela internet.
import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { config } from "./config.js";
import { consultarEPersistirPagamentos } from "./pagamentos-tjsp.js";

const MAX_BODY_BYTES = 10_000;

function json(res: ServerResponse, status: number, data: unknown): void {
  const body = JSON.stringify(data);
  res.writeHead(status, { "Content-Type": "application/json; charset=utf-8" });
  res.end(body);
}

async function readBody(req: IncomingMessage): Promise<string> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    size += (chunk as Buffer).length;
    if (size > MAX_BODY_BYTES) throw new Error("corpo da requisição excede o limite");
    chunks.push(chunk as Buffer);
  }
  return Buffer.concat(chunks).toString("utf-8");
}

async function handleValorPago(req: IncomingMessage, res: ServerResponse): Promise<void> {
  let body: { processo_depre?: string };
  try {
    body = JSON.parse(await readBody(req));
  } catch {
    return json(res, 400, { error: "JSON inválido" });
  }

  const processoDepre = (body.processo_depre ?? "").trim();
  if (!/\.8\.26\.0500$/.test(processoDepre)) {
    return json(res, 400, { error: "processo_depre inválido (esperado terminar em .8.26.0500)" });
  }

  try {
    const resultado = await consultarEPersistirPagamentos(processoDepre);
    return json(res, 200, resultado);
  } catch (err) {
    console.error(`[http-server] /valor-pago falhou (${processoDepre}):`, err);
    return json(res, 502, { error: "falha ao consultar o portal TJSP", detalhe: String(err) });
  }
}

export function startHttpServer(): void {
  const server = createServer((req, res) => {
    void (async () => {
      if (config.httpSecret) {
        const auth = req.headers["x-worker-secret"];
        if (auth !== config.httpSecret) return json(res, 401, { error: "não autorizado" });
      }

      if (req.method === "POST" && req.url === "/valor-pago") {
        return handleValorPago(req, res);
      }
      json(res, 404, { error: "não encontrado" });
    })().catch((err) => {
      console.error("[http-server] erro não tratado:", err);
      if (!res.headersSent) json(res, 500, { error: "erro interno" });
    });
  });

  server.listen(config.httpPort, "127.0.0.1", () => {
    console.log(`[http-server] ouvindo em 127.0.0.1:${config.httpPort} (POST /valor-pago)`);
  });
}
