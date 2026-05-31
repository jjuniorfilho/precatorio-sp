import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { TrendingUp, TrendingDown, Users, Search, CheckCircle2, Percent } from "lucide-react";
import { AdminShell } from "@/components/admin-shell";
import { Button } from "@/components/ui/button";
import { Badge } from "@/components/ui/badge";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { CrmBadge } from "@/components/crm-badge";
import { mockCrmPipeline, mockFunnelStats, crmStatusOrder } from "@/data/mockData";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/admin/funil")({
  head: () => ({ meta: [{ title: "Visão geral · Admin" }] }),
  component: AdminFunilPage,
});

const fmt = (n: number) => n.toLocaleString("pt-BR");

function AdminFunilPage() {
  const [period, setPeriod] = useState("7");
  const [view, setView] = useState<"chart" | "table">("chart");
  const s = mockFunnelStats;

  const steps = [
    { label: "Visitantes", value: s.visitantes, pctTop: 100, pctPrev: null },
    { label: "Buscas realizadas", value: s.buscas, pctTop: 62.0, pctPrev: 62.0 },
    { label: "Resultados encontrados", value: s.resultados, pctTop: 45.0, pctPrev: 72.6 },
    { label: "Cadastros iniciados", value: s.cadastrosIniciados, pctTop: 18.0, pctPrev: 40.0 },
    { label: "Tokens validados", value: s.tokensValidados, pctTop: 10.0, pctPrev: 55.5 },
    { label: "Lead completo", value: s.leadsCompletos, pctTop: 5.0, pctPrev: 50.0, highlight: true },
  ];

  return (
    <AdminShell
      title="Visão geral"
      subtitle="Últimos 7 dias · Atualizado agora"
      actions={
        <div className="hidden gap-1 sm:flex">
          {[
            { v: "today", l: "Hoje" },
            { v: "7", l: "7 dias" },
            { v: "30", l: "30 dias" },
          ].map((o) => (
            <Button key={o.v} size="sm" variant={period === o.v ? "default" : "outline"} onClick={() => setPeriod(o.v)}>
              {o.l}
            </Button>
          ))}
        </div>
      }
    >
      {/* Metric cards */}
      <div className="mb-6 grid grid-cols-2 gap-4 lg:grid-cols-4">
        <MetricCard label="Visitantes" value={fmt(s.visitantes)} delta="+18% vs semana" up icon={Users} tone="primary" />
        <MetricCard label="Consultas" value={fmt(s.buscas)} delta="+12%" up icon={Search} tone="primary" />
        <MetricCard label="Leads completos" value={fmt(s.leadsCompletos)} delta="+8%" up icon={CheckCircle2} tone="success" />
        <MetricCard label="Conversão total" value="5,0%" delta="-0,2pp" up={false} icon={Percent} tone="primary" />
      </div>

      {/* Funnel */}
      <div className="rounded-lg border bg-card shadow-sm">
        <div className="flex items-center justify-between border-b p-4">
          <div>
            <h2 className="text-base font-semibold">Funil de conversão</h2>
            <p className="text-xs text-muted-foreground">Últimos 7 dias</p>
          </div>
          <div className="flex gap-1">
            <Button size="sm" variant={view === "chart" ? "default" : "outline"} onClick={() => setView("chart")}>Gráfico</Button>
            <Button size="sm" variant={view === "table" ? "default" : "outline"} onClick={() => setView("table")}>Tabela</Button>
          </div>
        </div>

        <div className="p-4">
          {view === "chart" ? (
            <div className="space-y-3">
              {steps.map((step, i) => {
                const width = (step.value / steps[0].value) * 100;
                const opacity = 1 - i * 0.08;
                return (
                  <div key={step.label} className="grid grid-cols-[140px_1fr_60px] items-center gap-3">
                    <span className="text-xs font-medium text-muted-foreground">{step.label}</span>
                    <div className="relative h-8 rounded-md bg-muted">
                      <div
                        className={cn(
                          "flex h-full items-center rounded-md px-3 text-xs font-semibold text-white",
                          step.highlight ? "bg-success" : "bg-primary",
                        )}
                        style={{ width: `${Math.max(width, 8)}%`, opacity: step.highlight ? 1 : opacity }}
                      >
                        {fmt(step.value)}
                      </div>
                    </div>
                    <span className="text-right text-xs text-muted-foreground">{step.pctTop}%</span>
                  </div>
                );
              })}
            </div>
          ) : (
            <table className="w-full text-sm">
              <thead className="border-b text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
                <tr><th className="py-2">Etapa</th><th className="py-2">Total</th><th className="py-2">% anterior</th><th className="py-2">% topo</th></tr>
              </thead>
              <tbody>
                {steps.map((step) => (
                  <tr key={step.label} className={cn("border-b last:border-0", step.highlight && "bg-success-bg")}>
                    <td className={cn("py-2.5", step.highlight && "font-semibold")}>{step.label}</td>
                    <td className={cn("py-2.5", step.highlight && "font-semibold")}>{fmt(step.value)}</td>
                    <td className="py-2.5">
                      {step.pctPrev != null ? (
                        <Badge className={step.pctPrev >= 60 ? "bg-success-bg text-success" : "bg-warning-bg text-warning-dark"}>
                          {step.pctPrev.toFixed(1)}%
                        </Badge>
                      ) : (
                        <span className="text-muted-foreground">—</span>
                      )}
                    </td>
                    <td className={cn("py-2.5", step.highlight && "font-semibold")}>{step.pctTop}%</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
          <Alert className="mt-4 border-warning/30 bg-warning-bg">
            <AlertDescription className="text-sm">
              <strong>Gargalo:</strong> Resultado → Cadastro iniciado (40%). Oportunidade de melhoria na CTA pós-resultado.
            </AlertDescription>
          </Alert>
        </div>
      </div>

      {/* CRM Pipeline */}
      <div className="mt-6 rounded-lg border bg-card shadow-sm">
        <div className="flex items-center justify-between border-b p-4">
          <h2 className="text-base font-semibold">Pipeline CRM</h2>
          <a href="/admin/leads" className="text-xs font-medium text-primary hover:underline">Ver todos →</a>
        </div>
        <div className="flex flex-wrap gap-3 p-4">
          {crmStatusOrder.filter((s) => s !== "descartado").map((s) => (
            <div key={s} className="min-w-[110px] flex-1 rounded-lg border p-3">
              <p className="text-[22px] font-bold leading-none">{mockCrmPipeline[s]}</p>
              <div className="mt-2"><CrmBadge status={s} /></div>
            </div>
          ))}
        </div>
      </div>
    </AdminShell>
  );
}

function MetricCard({
  label,
  value,
  delta,
  up,
  icon: Icon,
  tone,
}: {
  label: string;
  value: string;
  delta: string;
  up: boolean;
  icon: React.ComponentType<{ className?: string }>;
  tone: "primary" | "success";
}) {
  return (
    <div className="flex items-center justify-between rounded-lg border bg-card p-4 shadow-sm">
      <div>
        <p className="text-xs font-medium text-muted-foreground">{label}</p>
        <p className="mt-1 text-2xl font-bold">{value}</p>
        <p className={cn("mt-1 inline-flex items-center text-xs", up ? "text-success" : "text-error")}>
          {up ? <TrendingUp className="mr-1 h-3 w-3" /> : <TrendingDown className="mr-1 h-3 w-3" />}
          {delta}
        </p>
      </div>
      <div className={cn("flex h-10 w-10 items-center justify-center rounded-full", tone === "success" ? "bg-success-bg text-success" : "bg-primary-50 text-primary")}>
        <Icon className="h-5 w-5" />
      </div>
    </div>
  );
}
