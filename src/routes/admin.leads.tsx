import { createFileRoute } from "@tanstack/react-router";
import { useMemo, useState } from "react";
import { Download, Pencil, Search } from "lucide-react";
import { AdminShell } from "@/components/admin-shell";
import { CrmBadge } from "@/components/crm-badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Badge } from "@/components/ui/badge";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { useAdmin } from "@/contexts/AppProviders";
import {
  crmStatusOrder,
  crmStatusLabel,
  mockCrmPipeline,
  mockLeadTimeline,
  type CrmStatus,
  type Lead,
} from "@/data/mockData";
import { formatCurrency, formatRelativeDate, formatDate, normalizeProcesso } from "@/lib/format";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/admin/leads")({
  head: () => ({ meta: [{ title: "Leads completos · Admin" }] }),
  component: AdminLeadsPage,
});

const RELACAO_LABEL: Record<string, string> = {
  titular: "Titular",
  herdeiro: "Herdeiro",
  advogado: "Advogado",
};

function AdminLeadsPage() {
  const { leads, updateLeadStatus, updateLeadNotes } = useAdmin();
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState<CrmStatus | "all">("all");
  const [period, setPeriod] = useState("7");
  const [saldoRange, setSaldoRange] = useState("all");
  const [devedora, setDevedora] = useState("all");
  const [relacao, setRelacao] = useState("all");
  const [selected, setSelected] = useState<Lead | null>(null);

  const filtered = useMemo(() => {
    return leads.filter((l) => {
      if (statusFilter !== "all" && l.status_crm !== statusFilter) return false;
      if (devedora !== "all" && !l.devedora.toLowerCase().includes(devedora.toLowerCase())) return false;
      if (relacao !== "all" && l.relacao !== relacao) return false;
      if (saldoRange !== "all") {
        const s = l.saldo_consultado;
        const ranges: Record<string, [number, number]> = {
          lt1k: [0, 100000],
          "1k10k": [100000, 1000000],
          "10k100k": [1000000, 10000000],
          gt100k: [10000000, Number.POSITIVE_INFINITY],
        };
        const [min, max] = ranges[saldoRange];
        if (s < min || s >= max) return false;
      }
      if (search) {
        const q = search.toLowerCase();
        const qn = normalizeProcesso(search);
        const hit =
          l.nome.toLowerCase().includes(q) ||
          l.email.toLowerCase().includes(q) ||
          normalizeProcesso(l.processo_depre).includes(qn);
        if (!hit) return false;
      }
      return true;
    });
  }, [leads, statusFilter, devedora, relacao, saldoRange, search]);

  const exportCSV = () => {
    const headers = ["Nome", "Email", "Telefone", "Relacao", "Processo", "Saldo R$", "Devedora", "Status CRM", "Data"];
    const rows = filtered.map((l) => [
      l.nome,
      l.email,
      l.telefone,
      l.relacao,
      l.processo_depre,
      (l.saldo_consultado / 100).toFixed(2).replace(".", ","),
      l.devedora,
      l.status_crm,
      new Date(l.created_at).toLocaleDateString("pt-BR"),
    ]);
    const csv = [headers, ...rows].map((r) => r.join(";")).join("\n");
    const blob = new Blob(["\uFEFF" + csv], { type: "text/csv;charset=utf-8;" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `leads-${new Date().toISOString().slice(0, 10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  };

  return (
    <AdminShell
      title="Leads completos"
      subtitle={`${leads.length} leads · 12 novos hoje`}
      actions={
        <Button size="sm" onClick={exportCSV} className="hidden sm:inline-flex">
          <Download className="mr-1.5 h-4 w-4" /> Exportar CSV
        </Button>
      }
    >
      <div className="rounded-lg border bg-card p-4 shadow-sm">
        <div className="flex flex-wrap items-center gap-2">
          <div className="relative">
            <Search className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-muted-foreground" />
            <Input
              placeholder="Buscar por nome, e-mail, processo..."
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              className="h-9 w-56 pl-8 text-sm"
            />
          </div>
          <Select value={statusFilter} onValueChange={(v) => setStatusFilter(v as CrmStatus | "all")}>
            <SelectTrigger className="h-9 w-40 text-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos os status</SelectItem>
              {crmStatusOrder.map((s) => (
                <SelectItem key={s} value={s}>{crmStatusLabel[s]}</SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={period} onValueChange={setPeriod}>
            <SelectTrigger className="h-9 w-32 text-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="today">Hoje</SelectItem>
              <SelectItem value="7">7 dias</SelectItem>
              <SelectItem value="30">30 dias</SelectItem>
              <SelectItem value="custom">Custom</SelectItem>
            </SelectContent>
          </Select>
          <Select value={saldoRange} onValueChange={setSaldoRange}>
            <SelectTrigger className="h-9 w-40 text-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todos os saldos</SelectItem>
              <SelectItem value="lt1k">&lt; R$ 1k</SelectItem>
              <SelectItem value="1k10k">R$ 1k–10k</SelectItem>
              <SelectItem value="10k100k">R$ 10k–100k</SelectItem>
              <SelectItem value="gt100k">+ R$ 100k</SelectItem>
            </SelectContent>
          </Select>
          <Select value={devedora} onValueChange={setDevedora}>
            <SelectTrigger className="h-9 w-36 text-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas</SelectItem>
              <SelectItem value="Fazenda">Fazenda SP</SelectItem>
              <SelectItem value="SPPREV">SPPREV</SelectItem>
              <SelectItem value="CBPM">CBPM</SelectItem>
              <SelectItem value="IPESP">IPESP</SelectItem>
              <SelectItem value="DER">DER</SelectItem>
            </SelectContent>
          </Select>
          <Select value={relacao} onValueChange={setRelacao}>
            <SelectTrigger className="h-9 w-32 text-sm"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Todas</SelectItem>
              <SelectItem value="titular">Titular</SelectItem>
              <SelectItem value="herdeiro">Herdeiro</SelectItem>
              <SelectItem value="advogado">Advogado</SelectItem>
            </SelectContent>
          </Select>
        </div>

        <div className="mt-3 flex flex-wrap gap-2">
          <FilterChip active={statusFilter === "all"} onClick={() => setStatusFilter("all")}>
            Todos ({leads.length})
          </FilterChip>
          {(["novo", "contatado", "qualificado", "interessado", "fechado"] as CrmStatus[]).map((s) => (
            <FilterChip key={s} active={statusFilter === s} onClick={() => setStatusFilter(s)}>
              <CrmBadge status={s} className="mr-1.5" /> ({mockCrmPipeline[s]})
            </FilterChip>
          ))}
        </div>
      </div>

      {/* Table */}
      <div className="mt-4 overflow-hidden rounded-lg border bg-card shadow-sm">
        <div className="overflow-x-auto">
          <table className="w-full text-sm [&>tbody>tr:nth-child(even)]:bg-muted/40">
            <thead className="border-b bg-muted/30 text-left text-xs font-medium uppercase tracking-wide text-muted-foreground">
              <tr>
                <th className="px-4 py-3">Nome</th>
                <th className="px-4 py-3">Processo</th>
                <th className="px-4 py-3">Saldo</th>
                <th className="px-4 py-3">Devedora</th>
                <th className="px-4 py-3">Relação</th>
                <th className="px-4 py-3">Status</th>
                <th className="px-4 py-3">Data</th>
                <th className="px-4 py-3"></th>
              </tr>
            </thead>
            <tbody>
              {filtered.length === 0 && (
                <tr><td colSpan={8} className="px-4 py-10 text-center text-sm text-muted-foreground">Nenhum lead encontrado para os filtros aplicados.</td></tr>
              )}
              {filtered.map((l) => (
                <tr
                  key={l.id}
                  onClick={() => setSelected(l)}
                  className="group cursor-pointer border-b transition-all duration-150 last:border-0 hover:-translate-y-px hover:bg-muted/60 hover:shadow-sm"
                >
                  <td className="px-4 py-3">
                    <p className="font-medium">{l.nome}</p>
                    <p className="text-xs text-muted-foreground">{l.email} · {l.telefone}</p>
                  </td>
                  <td className="px-4 py-3"><code className="font-mono text-xs font-semibold text-primary">{l.processo_depre}</code></td>
                  <td className="px-4 py-3 font-semibold text-success">{formatCurrency(l.saldo_consultado)}</td>
                  <td className="px-4 py-3">{l.devedora}</td>
                  <td className="px-4 py-3"><Badge variant="secondary">{RELACAO_LABEL[l.relacao]}</Badge></td>
                  <td className="px-4 py-3"><CrmBadge status={l.status_crm} /></td>
                  <td className="px-4 py-3 text-xs text-muted-foreground">{formatRelativeDate(l.created_at)}</td>
                  <td className="px-4 py-3 text-right">
                    <Button variant="ghost" size="icon" className="h-7 w-7 opacity-0 transition-opacity group-hover:opacity-100">
                      <Pencil className="h-3.5 w-3.5" />
                    </Button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="flex items-center justify-between border-t px-4 py-3 text-xs text-muted-foreground">
          <span>Mostrando {filtered.length} de {leads.length} leads</span>
          <div className="flex gap-1">
            <Button variant="outline" size="sm" disabled>← Anterior</Button>
            <Button variant="outline" size="sm" disabled>Próxima →</Button>
          </div>
        </div>
      </div>

      <LeadDetailModal
        lead={selected}
        onClose={() => setSelected(null)}
        onStatusChange={(id, s) => {
          updateLeadStatus(id, s);
          setSelected((prev) => (prev ? { ...prev, status_crm: s } : prev));
        }}
        onNotesChange={(id, n) => {
          updateLeadNotes(id, n);
          setSelected((prev) => (prev ? { ...prev, notas: n } : prev));
        }}
      />
    </AdminShell>
  );
}

function FilterChip({ active, onClick, children }: { active?: boolean; onClick: () => void; children: React.ReactNode }) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "inline-flex items-center rounded-full border px-3 py-1 text-xs font-medium transition-colors",
        active ? "border-primary bg-primary-50 text-primary" : "border-border bg-card hover:bg-muted",
      )}
    >
      {children}
    </button>
  );
}

function LeadDetailModal({
  lead,
  onClose,
  onStatusChange,
  onNotesChange,
}: {
  lead: Lead | null;
  onClose: () => void;
  onStatusChange: (id: string, s: CrmStatus) => void;
  onNotesChange: (id: string, n: string) => void;
}) {
  if (!lead) return null;
  const timeline = mockLeadTimeline[lead.id] ?? [];
  const currentIdx = crmStatusOrder.indexOf(lead.status_crm);
  const nextStatus = crmStatusOrder[Math.min(currentIdx + 1, crmStatusOrder.length - 2)];

  return (
    <Dialog open={!!lead} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-lg sm:rounded-xl">
        <DialogHeader>
          <DialogTitle className="text-lg">{lead.nome}</DialogTitle>
          <p className="text-xs text-muted-foreground">Lead #{lead.id} · {formatDate(lead.created_at)}</p>
        </DialogHeader>

        <div className="space-y-5">
          <div>
            <p className="mb-2 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Pipeline</p>
            <div className="flex flex-wrap gap-1.5">
              {crmStatusOrder.map((s) => (
                <button key={s} type="button" onClick={() => onStatusChange(lead.id, s)}>
                  <CrmBadge status={s} muted={s !== lead.status_crm} className="cursor-pointer" />
                </button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3 rounded-lg bg-muted px-4 py-3 text-sm">
            <Field label="E-mail" value={lead.email} />
            <Field label="WhatsApp" value={lead.telefone} />
            <Field label="Relação" value={RELACAO_LABEL[lead.relacao]} />
            <Field label="Processo" value={<code className="font-mono text-xs text-primary">{lead.processo_depre}</code>} />
            <Field label="Saldo DEPRE" value={<span className="font-bold text-success">{formatCurrency(lead.saldo_consultado)}</span>} />
            <Field label="Devedora" value={lead.devedora} />
          </div>

          <div>
            <label className="mb-1 block text-sm font-medium">Notas internas</label>
            <Textarea
              value={lead.notas}
              onChange={(e) => onNotesChange(lead.id, e.target.value)}
              className="min-h-[70px]"
              placeholder="Adicione observações sobre este lead..."
            />
          </div>

          <div>
            <p className="mb-3 text-[10px] font-medium uppercase tracking-wide text-muted-foreground">Timeline</p>
            <ol className="relative space-y-3 border-l-2 border-border pl-5">
              {timeline.map((t, i) => (
                <li key={i} className="relative">
                  <span
                    className={cn(
                      "absolute -left-[26px] top-1 h-3 w-3 rounded-full ring-4 ring-background",
                      t.tipo === "success" && "bg-success",
                      t.tipo === "default" && "bg-primary",
                      t.tipo === "muted" && "bg-muted-foreground",
                    )}
                  />
                  <p className="text-sm font-medium">{t.evento}</p>
                  <p className="text-xs text-muted-foreground">{formatDate(t.tempo)}</p>
                </li>
              ))}
            </ol>
          </div>
        </div>

        <div className="flex justify-end gap-2 border-t pt-4">
          <Button variant="outline" size="sm" onClick={onClose}>Fechar</Button>
          <Button size="sm" onClick={() => onStatusChange(lead.id, nextStatus)}>
            Marcar como {crmStatusLabel[nextStatus]}
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Field({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div>
      <p className="text-[10px] uppercase tracking-wide text-muted-foreground">{label}</p>
      <p className="mt-0.5 text-sm">{value}</p>
    </div>
  );
}
