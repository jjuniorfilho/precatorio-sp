import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { Search, Check, Monitor, Phone, Loader2 } from "lucide-react";
import { PublicNavbar, PublicFooter } from "@/components/public-layout";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import {
  Accordion,
  AccordionContent,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import { useSearch } from "@/contexts/AppProviders";
import { normalizeProcesso } from "@/lib/format";
import { detectInputType, normalizeInput } from "@/lib/search";
import { mockPrecatorios } from "@/data/mockData";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Consulta Precatório SP — Consulte grátis o saldo do seu precatório" },
      {
        name: "description",
        content:
          "Consulte grátis o saldo do seu precatório do Estado de SP. Base com mais de 200 mil processos do DEPRE. Resultado em segundos.",
      },
    ],
  }),
  component: LandingPage,
});

function LandingPage() {
  const navigate = useNavigate();
  const { query, setQuery, setResult } = useSearch();
  const [loading, setLoading] = useState(false);

  const [error, setError] = useState<string | null>(null);

  const handleSearch = async (e?: React.FormEvent) => {
    e?.preventDefault();
    if (!query.trim()) return;
    const type = detectInputType(query);
    if (type === "desconhecido") {
      setError("Formato não reconhecido. Use processo, CPF ou CNPJ.");
      return;
    }
    setError(null);
    setLoading(true);
    setResult("loading");
    await new Promise((r) => setTimeout(r, 600));
    setLoading(false);
    if (type === "cpf") {
      navigate({ to: "/resultado/cpf/$cpf", params: { cpf: normalizeInput(query) } });
    } else if (type === "cnpj") {
      navigate({ to: "/resultado/cnpj/$cnpj", params: { cnpj: normalizeInput(query) } });
    } else {
      // ensure mockPrecatorios import is used downstream
      void mockPrecatorios;
      navigate({ to: "/resultado/$processo", params: { processo: normalizeProcesso(query) } });
    }
  };

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNavbar />

      {/* Hero */}
      <section className="px-5 py-12 text-center sm:px-6 sm:py-[72px]">
        <div className="mx-auto max-w-3xl">
          <span className="inline-flex items-center rounded-full border border-primary/20 bg-primary-50 px-3 py-1 text-xs font-medium text-primary">
            Dados públicos oficiais do DEPRE · Gratuito · Resultado em segundos
          </span>
          <h1 className="mt-5 text-[clamp(28px,5vw,40px)] font-bold leading-tight tracking-tight">
            Consulte Gratis o Valor do Seu Precatório SP
          </h1>
          <p className="mx-auto mt-3 max-w-md text-base text-muted-foreground">
            Base com mais de 200 mil processos do DEPRE. Resultado em segundos.
          </p>

          <form
            onSubmit={handleSearch}
            className="mx-auto mt-7 flex max-w-lg flex-col gap-2 sm:flex-row"
          >
            <Input
              value={query}
              onChange={(e) => {
                setQuery(e.target.value);
                if (error) setError(null);
              }}
              placeholder="Processo, CPF ou CNPJ"
              className="h-12 rounded-lg shadow-sm sm:flex-1"
              aria-invalid={!!error}
            />
            <Button
              type="submit"
              disabled={loading || !query.trim()}
              className="h-12 rounded-lg px-6"
            >
              {loading ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" /> Consultando...
                </>
              ) : (
                <>
                  <Search className="mr-2 h-4 w-4" /> Consultar Agora
                </>
              )}
            </Button>
          </form>
          <p className="mx-auto mt-2 max-w-lg text-xs text-muted-foreground">
            Ex: 0122089-09.2025.8.26.0500 · 123.456.789-00 · 12.345.678/0001-90
          </p>
          {error && (
            <p className="mx-auto mt-2 max-w-lg text-sm text-error">{error}</p>
          )}

          <div className="mt-6 flex flex-wrap justify-center gap-x-5 gap-y-2 text-xs text-muted-foreground">
            <span className="inline-flex items-center gap-1.5">
              <Check className="h-3.5 w-3.5 text-success" /> Sem cadastro prévio
            </span>
            <span className="inline-flex items-center gap-1.5">
              <Check className="h-3.5 w-3.5 text-success" /> Dados do TJSP/DEPRE
            </span>
            <span className="inline-flex items-center gap-1.5">
              <Check className="h-3.5 w-3.5 text-success" /> CNPJ 12.345.678/0001-90
            </span>
          </div>
        </div>
      </section>

      {/* Stats strip */}
      <div className="border-y bg-muted/40 px-6 py-3 text-center text-sm text-muted-foreground">
        <div className="mx-auto flex max-w-3xl flex-wrap justify-center gap-x-6 gap-y-1">
          <span><strong className="font-semibold text-foreground">4.821</strong> consultas hoje</span>
          <span className="hidden sm:inline">·</span>
          <span><strong className="font-semibold text-foreground">200.000+</strong> processos na base</span>
          <span className="hidden sm:inline">·</span>
          <span>Resultado em <strong className="font-semibold text-foreground">&lt; 2 segundos</strong></span>
        </div>
      </div>

      {/* Como funciona */}
      <section id="como-funciona" className="bg-muted px-6 py-16">
        <div className="mx-auto max-w-5xl text-center">
          <h2 className="text-2xl font-bold tracking-tight sm:text-3xl">Como funciona</h2>
          <p className="mt-2 text-muted-foreground">Simples, rápido, sem burocracia</p>
          <div className="mt-10 grid gap-4 sm:grid-cols-3">
            {[
              {
                icon: Search,
                title: "1. Informe o número",
                body:
                  "Digite o número do processo DEPRE ou o número de Autos. Aceitamos os dois formatos.",
              },
              {
                icon: Monitor,
                title: "2. Veja o saldo",
                body:
                  "Resultado instantâneo com saldo DEPRE, status, natureza e devedora. Grátis, sem compromisso.",
              },
              {
                icon: Phone,
                title: "3. Receba os detalhes",
                body:
                  "Se quiser mais informações, informe seus dados e receba o relatório completo no e-mail e WhatsApp.",
              },
            ].map((c) => (
              <div key={c.title} className="rounded-lg border bg-card p-6 text-left shadow-sm">
                <div className="mb-4 inline-flex h-10 w-10 items-center justify-center rounded-full bg-primary-50 text-primary">
                  <c.icon className="h-5 w-5" />
                </div>
                <h3 className="font-semibold">{c.title}</h3>
                <p className="mt-1 text-sm text-muted-foreground">{c.body}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* FAQ */}
      <section id="faq" className="px-6 py-16">
        <div className="mx-auto max-w-2xl">
          <h2 className="text-center text-2xl font-bold tracking-tight sm:text-3xl">
            Dúvidas frequentes
          </h2>
          <Accordion type="single" collapsible className="mt-8">
            {[
              {
                q: "O que é um precatório?",
                a: "Precatório é um documento emitido pela Justiça determinando que o Estado deve pagar uma dívida reconhecida por sentença judicial. O pagamento é feito em ordem cronológica.",
              },
              {
                q: "A consulta é realmente gratuita?",
                a: "Sim. A consulta do saldo DEPRE é 100% gratuita e sem compromisso. Você não precisa nem se cadastrar para ver o resultado.",
              },
              {
                q: "O que é o DEPRE?",
                a: "DEPRE é o Departamento de Precatórios do Tribunal de Justiça de São Paulo. Nossa base usa os dados oficiais do DEPRE com mais de 200 mil processos.",
              },
              {
                q: "Por que o saldo pode estar diferente do que recebi?",
                a: "O saldo exibido é o da base DEPRE sem atualização monetária. O valor real corrigido pela SELIC pode ser diferente.",
              },
              {
                q: "Meus dados estão seguros?",
                a: "Sim. Seus dados são protegidos pela LGPD. Você pode solicitar exclusão a qualquer momento.",
              },
            ].map((item, i) => (
              <AccordionItem key={i} value={`item-${i}`}>
                <AccordionTrigger className="text-left">{item.q}</AccordionTrigger>
                <AccordionContent className="text-muted-foreground">{item.a}</AccordionContent>
              </AccordionItem>
            ))}
          </Accordion>
        </div>
      </section>

      <PublicFooter />
    </div>
  );
}
