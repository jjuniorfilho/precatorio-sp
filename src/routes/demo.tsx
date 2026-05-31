import { createFileRoute, Link } from "@tanstack/react-router";
import { PublicNavbar, PublicFooter } from "@/components/public-layout";

export const Route = createFileRoute("/demo")({
  head: () => ({
    meta: [{ title: "Demo · Estados do Precatório" }],
  }),
  component: DemoPage,
});

const states = [
  {
    label: "Ativo (com saldo)",
    processo: "0122089-09.2025.8.26.0500",
    description: "Precatório encontrado com saldo de R$ 147.832,00. Mostra CTA de cadastro.",
    tone: "border-emerald-500/40 bg-emerald-500/5",
  },
  {
    label: "Sem saldo",
    processo: "0033421-14.2023.8.26.0100",
    description: "Processo existe mas saldo é zero. Pode ter sido pago ou não expedido.",
    tone: "border-amber-500/40 bg-amber-500/5",
  },
  {
    label: "Suspenso",
    processo: "0006248-79.2024.8.26.0506",
    description: "Processo com saldo, porém suspenso por ação judicial.",
    tone: "border-orange-500/40 bg-orange-500/5",
  },
  {
    label: "Não encontrado",
    processo: "1234567-89.2020.8.26.0000",
    description: "Qualquer número fora da base mock cai neste estado.",
    tone: "border-rose-500/40 bg-rose-500/5",
  },
];

function DemoPage() {
  return (
    <>
      <PublicNavbar />
      <div className="mx-auto max-w-3xl px-4 py-12">
        <div className="mb-8">
          <h1 className="text-3xl font-semibold tracking-tight">Demo · 4 estados do resultado</h1>
          <p className="mt-2 text-muted-foreground">
            Clique em qualquer card para abrir a tela de resultado correspondente.
          </p>
        </div>

        <div className="grid gap-4 sm:grid-cols-2">
          {states.map((s) => (
            <Link
              key={s.processo}
              to="/resultado/$processo"
              params={{ processo: s.processo }}
              className={`block rounded-xl border p-5 transition hover:shadow-md ${s.tone}`}
            >
              <div className="text-sm font-medium uppercase tracking-wide text-muted-foreground">
                {s.label}
              </div>
              <div className="mt-2 font-mono text-sm">{s.processo}</div>
              <p className="mt-3 text-sm text-foreground/80">{s.description}</p>
            </Link>
          ))}
        </div>

        <div className="mt-10 rounded-lg border border-dashed p-4 text-sm text-muted-foreground">
          Dica: você também pode digitar esses números na busca da home (<Link to="/" className="underline">/</Link>) para simular o fluxo completo a partir do início.
        </div>
      </div>
      <PublicFooter />
    </>
  );
}
