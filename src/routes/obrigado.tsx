import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { CheckCircle2 } from "lucide-react";
import { PublicFooter } from "@/components/public-layout";
import { StepIndicator } from "@/components/step-indicator";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { Link } from "@tanstack/react-router";
import { useLead } from "@/contexts/AppProviders";
import { formatCurrency } from "@/lib/format";

export const Route = createFileRoute("/obrigado")({
  head: () => ({ meta: [{ title: "Pronto! — Consulta Precatório SP" }] }),
  component: ObrigadoPage,
});

function ObrigadoPage() {
  const lead = useLead();
  const navigate = useNavigate();
  const firstName = (lead.nome || "").split(" ")[0] || "";
  return (
    <div className="flex min-h-screen flex-col bg-muted">
      <header className="px-6 py-4">
        <Link to="/" className="font-semibold tracking-tight">
          Consulta Precatório SP
        </Link>
      </header>
      <main className="mx-auto w-full max-w-sm flex-1 px-4 pb-12">
        <div className="rounded-xl border bg-card p-6 text-center shadow-sm">
          <StepIndicator current={4} />

          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-success-bg">
            <CheckCircle2 className="h-8 w-8 text-success" />
          </div>

          <h1 className="text-xl font-bold">Tudo pronto{firstName ? `, ${firstName}` : ""}!</h1>
          <p className="mt-2 text-sm text-muted-foreground">
            Enviamos o relatório completo para{" "}
            <strong className="text-foreground">{lead.email || "seu e-mail"}</strong>
            {" "}e WhatsApp{" "}
            <strong className="text-foreground">{lead.telefone || "seu WhatsApp"}</strong>.
          </p>

          {lead.processo && (
            <div className="mt-5 rounded-lg bg-muted p-4 text-left">
              <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Seu precatório</p>
              <div className="mt-2 space-y-1.5 text-sm">
                <div className="flex justify-between"><span className="text-muted-foreground">Processo</span><span className="font-mono">{lead.processo}</span></div>
                <div className="flex justify-between"><span className="text-muted-foreground">Saldo DEPRE</span><span className="font-bold text-success">{lead.saldo != null ? formatCurrency(lead.saldo) : "—"}</span></div>
                {lead.devedora && <div className="flex justify-between"><span className="text-muted-foreground">Devedora</span><span>{lead.devedora}</span></div>}
              </div>
            </div>
          )}

          <Alert className="mt-5 border-info/30 bg-info-bg text-left">
            <AlertDescription className="text-xs">
              Nossa equipe pode entrar em contato para apresentar opções de{" "}
              <strong>antecipação do recebimento</strong>. Sem compromisso — você decide.
            </AlertDescription>
          </Alert>

          <Button variant="outline" className="mt-5 w-full" onClick={() => { lead.reset(); navigate({ to: "/" }); }}>
            Consultar outro processo
          </Button>
        </div>
      </main>
      <PublicFooter />
    </div>
  );
}
