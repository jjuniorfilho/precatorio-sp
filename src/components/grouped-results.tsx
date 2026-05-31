import { Link, useNavigate } from "@tanstack/react-router";
import { PublicNavbar, PublicFooter } from "@/components/public-layout";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { formatCurrency, maskProcesso } from "@/lib/format";
import { useLead } from "@/contexts/AppProviders";
import type { Precatorio } from "@/data/mockData";
import { Search } from "lucide-react";

interface Props {
  kind: "CPF" | "CNPJ";
  maskedId: string;
  results: Precatorio[];
}

export function GroupedResults({ kind, maskedId, results }: Props) {
  const navigate = useNavigate();
  const { setLeadData } = useLead();
  const total = results.reduce((sum, p) => sum + (p.saldo_depre ?? 0), 0);

  const goToCadastro = () => {
    if (results[0]) {
      setLeadData({
        processo: results[0].processo_depre,
        saldo: total,
        devedora: results[0].devedora,
      });
    }
    navigate({ to: "/cadastro" });
  };

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNavbar />
      <main className="mx-auto w-full max-w-lg flex-1 px-4 pt-7 pb-16">
        <Button variant="outline" size="sm" className="mb-6 h-10" asChild>
          <Link to="/"><Search className="mr-1.5 h-4 w-4" /> Nova busca</Link>
        </Button>

        {results.length === 0 ? (
          <article className="rounded-lg border bg-card p-6 shadow-sm">
            <Alert className="border-info/30 bg-info-bg">
              <AlertDescription className="text-sm">
                <strong>Não encontramos precatórios vinculados a este {kind}.</strong>
                <br />
                Verifique o número informado: <code className="font-mono">{maskedId}</code>
              </AlertDescription>
            </Alert>
            <Button asChild className="mt-4 w-full">
              <Link to="/">Tentar outro número</Link>
            </Button>
          </article>
        ) : (
          <>
            <header className="mb-4">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                {results.length} precatório{results.length > 1 ? "s" : ""} encontrado{results.length > 1 ? "s" : ""}
              </p>
              <h1 className="mt-1 text-lg font-semibold">
                {kind}: <code className="font-mono text-primary">{maskedId}</code>
              </h1>
            </header>

            <article className="mb-5 rounded-lg border bg-card p-5 shadow-sm">
              <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">
                Saldo DEPRE total
              </p>
              <p className="mt-1 text-[32px] font-bold leading-none text-success">
                {formatCurrency(total)}
              </p>
              <p className="mt-2 text-xs text-muted-foreground">
                Soma de {results.length} processo{results.length > 1 ? "s" : ""}.
              </p>
            </article>

            <ul className="space-y-3">
              {results.map((p) => (
                <li
                  key={p.id}
                  className="rounded-lg border bg-card p-4 shadow-sm"
                >
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <code className="font-mono text-sm font-semibold text-primary">
                        {maskProcesso(p.processo_depre)}
                      </code>
                      <p className="mt-1 text-sm text-muted-foreground">{p.devedora}</p>
                    </div>
                    <StatusBadge p={p} />
                  </div>
                  <Separator className="my-3" />
                  <div className="flex items-center justify-between gap-3 text-sm">
                    <div className="flex items-center gap-2">
                      <Badge
                        variant={p.natureza === "Alimentar" ? undefined : "secondary"}
                        className={p.natureza === "Alimentar" ? "bg-success-bg text-success" : ""}
                      >
                        {p.natureza}
                      </Badge>
                    </div>
                    <span className="font-semibold">{formatCurrency(p.saldo_depre)}</span>
                  </div>
                </li>
              ))}
            </ul>

            <div className="mt-6">
              <Button onClick={goToCadastro} size="lg" className="w-full">
                Receber detalhes completos grátis →
              </Button>
              <p className="mt-2 text-center text-xs text-muted-foreground">
                Por e-mail e WhatsApp. Sem spam.
              </p>
            </div>
          </>
        )}
      </main>
      <PublicFooter />
    </div>
  );
}

function StatusBadge({ p }: { p: Precatorio }) {
  if (p.suspenso) return <Badge className="bg-warning-bg text-warning-dark">Suspenso</Badge>;
  if (p.saldo_depre === 0) return <Badge variant="secondary">Sem saldo</Badge>;
  return <Badge className="bg-success-bg text-success">Ativo</Badge>;
}
