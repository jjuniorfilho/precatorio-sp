import { createFileRoute } from "@tanstack/react-router";
import { findByCpf, maskCpfPartial } from "@/lib/search";
import { mockPrecatorios } from "@/data/mockData";
import { GroupedResults } from "@/components/grouped-results";

export const Route = createFileRoute("/resultado/cpf/$cpf")({
  head: () => ({
    meta: [
      { title: "Resultado por CPF — Consulta Precatório SP" },
      { name: "description", content: "Veja todos os precatórios vinculados ao CPF informado." },
    ],
  }),
  component: ResultadoCpf,
});

function ResultadoCpf() {
  const { cpf } = Route.useParams();
  const results = findByCpf(cpf, mockPrecatorios);
  const formatted =
    cpf.length === 11
      ? `${cpf.slice(0, 3)}.${cpf.slice(3, 6)}.${cpf.slice(6, 9)}-${cpf.slice(9)}`
      : cpf;
  return (
    <GroupedResults
      kind="CPF"
      maskedId={maskCpfPartial(formatted)}
      results={results}
    />
  );
}
