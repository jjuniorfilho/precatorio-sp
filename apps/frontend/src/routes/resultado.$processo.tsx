import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { Lock, Loader2, Search, MessageCircle } from "lucide-react";
import { PublicNavbar, PublicFooter } from "@/components/public-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Badge } from "@/components/ui/badge";
import { Separator } from "@/components/ui/separator";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { useSearch, useLead } from "@/contexts/AppProviders";
import { findPrecatorio, formatCurrency, normalizeProcesso, maskProcesso, firstName, maskCpf } from "@/lib/format";
import { mockPrecatorios, type Precatorio } from "@/data/mockData";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/resultado/$processo")({
  head: () => ({
    meta: [
      { title: "Resultado da consulta — Consulta Precatório SP" },
      { name: "description", content: "Veja o saldo do seu precatório SP grátis." },
    ],
  }),
  component: ResultadoPage,
});

function ResultadoPage() {
  const { processo } = Route.useParams();
  const navigate = useNavigate();
  const { setQuery, query } = useSearch();
  const { setLeadData } = useLead();
  const [localQuery, setLocalQuery] = useState(query || processo);
  const [loading, setLoading] = useState(true);
  const [result, setResult] = useState<Precatorio | null>(null);

  useEffect(() => {
    setLoading(true);
    const t = setTimeout(() => {
      setResult(findPrecatorio(processo, mockPrecatorios));
      setLoading(false);
    }, 400);
    return () => clearTimeout(t);
  }, [processo]);

  const handleNewSearch = (e: React.FormEvent) => {
    e.preventDefault();
    if (!localQuery.trim()) return;
    setQuery(localQuery);
    navigate({ to: "/resultado/$processo", params: { processo: normalizeProcesso(localQuery) } });
  };

  const goToCadastro = () => {
    if (result) {
      setLeadData({
        processo: result.processo_depre,
        saldo: result.saldo_depre,
        devedora: result.devedora,
      });
    }
    navigate({ to: "/cadastro" });
  };

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNavbar />
      <main className="mx-auto w-full max-w-lg flex-1 px-4 pt-7 pb-16">
        <form onSubmit={handleNewSearch} className="mb-6 flex gap-2">
          <Input
            value={localQuery}
            onChange={(e) => setLocalQuery(e.target.value)}
            className="h-10 flex-1"
            placeholder="Número do processo"
          />
          <Button type="submit" variant="outline" size="sm" className="h-10">
            <Search className="mr-1.5 h-4 w-4" /> Nova busca
          </Button>
        </form>

        {loading ? (
          <div className="rounded-lg border bg-card p-10 text-center shadow-sm">
            <Loader2 className="mx-auto h-6 w-6 animate-spin text-muted-foreground" />
            <p className="mt-2 text-sm text-muted-foreground">Consultando base DEPRE...</p>
          </div>
        ) : !result ? (
          <NotFoundVariant onRetry={() => navigate({ to: "/" })} />
        ) : result.suspenso ? (
          <SuspendedVariant precatorio={result} onCta={goToCadastro} />
        ) : result.saldo_depre === 0 ? (
          <NoBalanceVariant precatorio={result} />
        ) : (
          <ActiveVariant precatorio={result} onCta={goToCadastro} />
        )}

        <p className="mt-6 text-center text-xs text-muted-foreground">
          Não é o seu processo? <Link to="/" className="text-primary hover:underline">Tente outro número</Link>
        </p>
      </main>
      <PublicFooter />
    </div>
  );
}

function StatusDot({ tone }: { tone: "success" | "muted" | "warning" | "error" }) {
  const colors = {
    success: "bg-success",
    muted: "bg-muted-foreground",
    warning: "bg-warning",
    error: "bg-error",
  };
  return <span className={cn("inline-block h-2 w-2 rounded-full", colors[tone])} />;
}

function CardHeader({ tone, label, right }: { tone: "success" | "muted" | "warning" | "error"; label: string; right?: React.ReactNode }) {
  return (
    <div className="flex items-center gap-2 px-5 pt-5">
      <StatusDot tone={tone} />
      <span className="text-xs font-medium uppercase tracking-wide text-muted-foreground">{label}</span>
      {right && <span className="ml-auto text-xs text-muted-foreground">{right}</span>}
    </div>
  );
}

function FieldRow({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="flex items-center justify-between gap-3 py-2">
      <span className="text-sm text-muted-foreground">{label}</span>
      <span className="text-right text-sm font-medium">{value}</span>
    </div>
  );
}

function ActiveVariant({ precatorio: p, onCta }: { precatorio: Precatorio; onCta: () => void }) {
  return (
    <article className="rounded-lg border bg-card shadow-sm">
      <CardHeader tone="success" label="Precatório encontrado" right="DEPRE · mai/2026" />
      <div className="px-5 pt-4">
        <p className="text-xs font-medium uppercase tracking-wide text-muted-foreground">Saldo DEPRE</p>
        <p className="text-[36px] font-bold leading-none text-success">{formatCurrency(p.saldo_depre)}</p>
      </div>
      <Separator className="my-5" />
      <div className="px-5">
        <FieldRow label="Processo" value={<code className="font-mono text-sm font-semibold text-primary">{maskProcesso(p.processo_depre)}</code>} />
        <FieldRow label="Autor" value={`${firstName(p.autor)} ●●●`} />
        <FieldRow label="CPF" value={<code className="font-mono text-sm">{maskCpf(p.cpf)}</code>} />
        <FieldRow label="Devedora" value={p.devedora} />
        <FieldRow
          label="Natureza"
          value={
            <Badge className={p.natureza === "Alimentar" ? "bg-success-bg text-success" : ""} variant={p.natureza === "Alimentar" ? undefined : "secondary"}>
              {p.natureza}
            </Badge>
          }
        />
        <FieldRow label="Status" value={<Badge className="bg-success-bg text-success">Ativo</Badge>} />
      </div>

      <div className="mx-5 mt-5 rounded-lg bg-muted/40 p-4">
        <div className="mb-2 flex items-center gap-2 text-xs font-medium text-muted-foreground">
          <Lock className="h-3.5 w-3.5" /> Dados completos — requer cadastro gratuito
        </div>
        <div className="space-y-1.5 text-sm">
          <div className="flex justify-between"><span className="text-muted-foreground">Advogado</span><span className="font-mono">Dr. ██████████</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Expedição</span><span className="font-mono">██/██/████</span></div>
          <div className="flex justify-between"><span className="text-muted-foreground">Ano base</span><span className="font-mono">████</span></div>
        </div>
      </div>

      <div className="p-5 pt-4">
        <Button onClick={onCta} size="lg" className="w-full">
          Receber detalhes completos grátis →
        </Button>
        <p className="mt-2 text-center text-xs text-muted-foreground">
          Por e-mail e WhatsApp. Sem spam.
        </p>
        <Alert className="mt-4 border-info/30 bg-info-bg text-foreground">
          <AlertDescription className="text-xs">
            Saldo sem atualização monetária. O valor real pode ser diferente.
          </AlertDescription>
        </Alert>
      </div>
    </article>
  );
}

function NoBalanceVariant({ precatorio: p }: { precatorio: Precatorio }) {
  return (
    <article className="rounded-lg border bg-card shadow-sm">
      <CardHeader tone="muted" label="Processo encontrado" />
      <div className="px-5 pb-5 pt-4">
        <FieldRow label="Processo" value={<code className="font-mono text-sm font-semibold text-primary">{maskProcesso(p.processo_depre)}</code>} />
        <FieldRow label="Autor" value={`${firstName(p.autor)} ●●●`} />
        <FieldRow label="CPF" value={<code className="font-mono text-sm">{maskCpf(p.cpf)}</code>} />
        <FieldRow label="Devedora" value={p.devedora} />
        <FieldRow label="Status" value={<Badge variant="secondary">Sem saldo</Badge>} />
        <Alert className="mt-4 border-info/30 bg-info-bg">
          <AlertDescription className="text-sm">
            Este processo consta na base DEPRE, mas não possui saldo registrado no momento. Pode
            ter sido pago ou ainda não expedido como precatório.
          </AlertDescription>
        </Alert>
        <Button variant="outline" className="mt-4 w-full">
          <MessageCircle className="mr-2 h-4 w-4" /> Falar com especialista via WhatsApp
        </Button>
      </div>
    </article>
  );
}

function SuspendedVariant({ precatorio: p, onCta }: { precatorio: Precatorio; onCta: () => void }) {
  return (
    <article className="rounded-lg border bg-card shadow-sm">
      <CardHeader tone="warning" label="Processo suspenso" />
      <div className="px-5 pb-5 pt-4">
        <FieldRow label="Processo" value={<code className="font-mono text-sm font-semibold text-primary">{maskProcesso(p.processo_depre)}</code>} />
        <FieldRow label="Autor" value={`${firstName(p.autor)} ●●●`} />
        <FieldRow label="CPF" value={<code className="font-mono text-sm">{maskCpf(p.cpf)}</code>} />
        <FieldRow label="Devedora" value={p.devedora} />
        <FieldRow label="Saldo DEPRE" value={<span className="font-semibold text-foreground">{formatCurrency(p.saldo_depre)}</span>} />
        <FieldRow label="Status" value={<Badge className="bg-warning-bg text-warning-dark">Suspenso</Badge>} />
        <Alert className="mt-4 border-warning/30 bg-warning-bg">
          <AlertDescription className="text-sm">
            <strong>Este processo está temporariamente suspenso.</strong> Pode haver ação judicial em curso. Recomendamos consultar o advogado responsável.
          </AlertDescription>
        </Alert>
        <Button onClick={onCta} className="mt-4 w-full">Receber análise especializada grátis</Button>
        <Button variant="ghost" size="sm" className="mt-2 w-full" asChild>
          <Link to="/">Nova consulta</Link>
        </Button>
      </div>
    </article>
  );
}

function NotFoundVariant({ onRetry }: { onRetry: () => void }) {
  return (
    <article className="rounded-lg border bg-card shadow-sm">
      <CardHeader tone="error" label="Não encontrado" />
      <div className="px-5 pb-5 pt-4">
        <Alert className="border-error/30 bg-error-bg">
          <AlertDescription className="text-sm">
            <strong>Não encontramos este processo na nossa base.</strong> Verifique o número e tente novamente. Formato esperado: 0000000-00.0000.0.00.0000
          </AlertDescription>
        </Alert>
        <Button onClick={onRetry} className="mt-4 w-full">Tentar com outro número</Button>
        <Button variant="outline" className="mt-2 w-full">
          <MessageCircle className="mr-2 h-4 w-4" /> Falar com suporte via WhatsApp
        </Button>
        <Separator className="my-4" />
        <p className="text-xs text-muted-foreground">
          Seu processo pode não estar na base se foi movido em outra comarca, ainda não foi
          homologado como precatório, ou o número está em formato diferente.
        </p>
      </div>
    </article>
  );
}
