// Smoke test do caminho de requisitório (.0500). NÃO persiste nada — só faz a busca
// na Consulta de Requisitórios, parseia a ficha e imprime o resultado p/ conferência.
// Uso (na VPS, IP liberado pelo e-SAJ):
//   tsx src/smoke-requisitorio.ts                         -> caso Capano de exemplo
//   tsx src/smoke-requisitorio.ts 0056238-23.2025.8.26.0500
// Casos Capano (adv. Fernando Fabiani Capano) p/ comparar:
//   0249561-37.2018.8.26.0500  (default, c/ histórico)  0056238-23.2025.8.26.0500  0056242-60.2025.8.26.0500
import { crawlRequisitorio } from "./crawl.js";
import { isDepre } from "./esaj.js";

const seed = (process.argv[2] ?? "0249561-37.2018.8.26.0500").trim();

function resumo(adv: any[]): string {
  return adv.length
    ? adv.map((a) => `${a.nome}${a.oab ? ` (OAB ${a.oab})` : " (sem OAB)"}`).join("; ")
    : "—";
}

async function main() {
  if (!isDepre(seed)) {
    console.error(`✗ ${seed} não é um requisitório .0500 (foro deve terminar em .8.26.0500).`);
    process.exit(1);
  }
  console.log(`→ buscando requisitório ${seed} na Consulta de Requisitórios...\n`);
  const { tree, origem, precatorio } = await crawlRequisitorio(seed);
  const inc = tree.cumprimentos[0]?.incidentes[0];

  console.log("── CAPA ───────────────────────────────────────────────");
  console.log(`CNJ           : ${tree.cnj ?? "(não achou)"}`);
  console.log(`Classe        : ${tree.classe}`);
  console.log(`Foro          : ${tree.foro}`);
  console.log(`Status        : ${tree.status ?? "—"}`);
  console.log(`Valor da ação : ${precatorio.valor_acao != null ? `R$ ${(precatorio.valor_acao / 100).toLocaleString("pt-BR", { minimumFractionDigits: 2 })}` : "—"}`);
  console.log("\n── PARTES ─────────────────────────────────────────────");
  console.log(`Credor (ativa): ${inc?.parte_ativa?.nome ?? "—"}`);
  console.log(`  Advogado(s) : ${resumo(inc?.parte_ativa?.advogados ?? [])}`);
  console.log(`Ente devedora : ${precatorio.devedora ?? "—"}`);
  console.log("\n── ORIGEM (será enfileirada p/ o cpopg) ───────────────");
  console.log(origem.length ? origem.map((c) => `  • ${c}`).join("\n") : "  (nenhum CNJ de origem encontrado)");
  console.log("\n── ANDAMENTOS (últimos 5) ─────────────────────────────");
  for (const a of (inc?.andamentos ?? []).slice(0, 5)) console.log(`  ${a.data ?? "??"}  ${a.descricao.slice(0, 80)}`);
  console.log(`  ... total: ${inc?.andamentos?.length ?? 0} andamentos`);

  console.log("\n── JSON COMPLETO ──────────────────────────────────────");
  console.log(JSON.stringify({ tree, origem, precatorio }, null, 2));
  console.log("\n✓ smoke test concluído (nada foi gravado no banco).");
}

main().catch((err) => {
  console.error("\n✗ falhou:", err);
  process.exit(1);
});
