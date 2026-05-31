import { createFileRoute } from "@tanstack/react-router";
import { findByCnpj, maskCnpjPartial } from "@/lib/search";
import { mockPrecatorios } from "@/data/mockData";
import { GroupedResults } from "@/components/grouped-results";

export const Route = createFileRoute("/resultado/cnpj/$cnpj")({
  head: () => ({
    meta: [
      { title: "Resultado por CNPJ — Consulta Precatório SP" },
      { name: "description", content: "Veja todos os precatórios vinculados ao CNPJ informado." },
    ],
  }),
  component: ResultadoCnpj,
});

function ResultadoCnpj() {
  const { cnpj } = Route.useParams();
  const results = findByCnpj(cnpj, mockPrecatorios);
  const formatted =
    cnpj.length === 14
      ? `${cnpj.slice(0, 2)}.${cnpj.slice(2, 5)}.${cnpj.slice(5, 8)}/${cnpj.slice(8, 12)}-${cnpj.slice(12)}`
      : cnpj;
  return (
    <GroupedResults
      kind="CNPJ"
      maskedId={maskCnpjPartial(formatted)}
      results={results}
    />
  );
}
