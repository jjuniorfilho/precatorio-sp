import { createFileRoute } from "@tanstack/react-router";
import { Download } from "lucide-react";
import { AdminShell } from "@/components/admin-shell";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { mockLeadsIncompletos } from "@/data/mockData";
import { formatCurrency, formatDate } from "@/lib/format";

export const Route = createFileRoute("/admin/incompletos")({
  head: () => ({ meta: [{ title: "Leads incompletos · Admin" }] }),
  component: AdminIncompletosPage,
});

function AdminIncompletosPage() {
  return (
    <AdminShell
      title="Leads incompletos"
      subtitle="Sessões que buscaram mas não completaram o cadastro"
      actions={
        <Button size="sm" className="hidden sm:inline-flex">
          <Download className="mr-1.5 h-4 w-4" /> Exportar CSV
        </Button>
      }
    >
      <Alert className="mb-4 border-info/30 bg-info-bg">
        <AlertDescription className="text-sm">
          Dados anônimos identificados por session_id. Nenhum dado pessoal exposto — LGPD compliant.
        </AlertDescription>
      </Alert>

      <div className="overflow-hidden rounded-lg border bg-card shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full text-sm [&>tbody>tr:nth-child(even)]:bg-muted/40">
            <thead className="border-b bg-muted/30 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-4 py-3">Processo buscado</th>
                <th className="px-4 py-3">Saldo</th>
                <th className="px-4 py-3">Etapa de abandono</th>
                <th className="px-4 py-3">Dispositivo</th>
                <th className="px-4 py-3">Data/Hora</th>
              </tr>
            </thead>
            <tbody>
              {mockLeadsIncompletos.map((l) => {
                const variant =
                  l.etapa_abandono === "Formulário abandonado"
                    ? "bg-warning-bg text-warning-dark"
                    : l.etapa_abandono === "Token não confirmado"
                      ? "bg-warning-bg text-warning-dark"
                      : "";
                return (
                  <tr key={l.session_id} className="border-b transition-colors last:border-0 hover:bg-muted/60">
                    <td className="px-4 py-3"><code className="font-mono text-xs text-primary">{l.processo_buscado}</code></td>
                    <td className="px-4 py-3 font-semibold text-success">{formatCurrency(l.saldo_encontrado)}</td>
                    <td className="px-4 py-3">
                      {variant ? (
                        <Badge className={variant}>{l.etapa_abandono}</Badge>
                      ) : (
                        <Badge variant="secondary">{l.etapa_abandono}</Badge>
                      )}
                    </td>
                    <td className="px-4 py-3 text-xs text-muted-foreground">{l.dispositivo}</td>
                    <td className="px-4 py-3 text-xs text-muted-foreground">{formatDate(l.data)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      </div>
    </AdminShell>
  );
}
