// FOR-102 — Fila de concorrência-1 para uso do Playwright.
// A VPS onde o worker roda tem só 1 vCPU / ~2GB de RAM livre, compartilhada com outros
// serviços em produção (comunica-web-api, comunica-saas-api, o próprio precatorio-crawler
// via crawler_queue). Rodar múltiplos Chromiums em paralelo arrisca esgotar memória/CPU e
// degradar tudo que roda na mesma VPS — por isso todo acesso ao módulo de pagamentos passa
// por aqui, serializado (requisições concorrentes esperam na fila em vez de rodar juntas).
let fila: Promise<unknown> = Promise.resolve();

/** Executa `tarefa` depois que qualquer chamada anterior enfileirada tiver terminado. */
export function comFilaPlaywright<T>(tarefa: () => Promise<T>): Promise<T> {
  const vez = fila.then(tarefa, tarefa);
  // evita que uma rejeição quebre a fila pras próximas tarefas
  fila = vez.catch(() => {});
  return vez;
}
