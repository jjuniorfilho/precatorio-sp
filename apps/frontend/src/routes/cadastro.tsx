import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { PublicFooter } from "@/components/public-layout";
import { ForjurisLogo } from "@/components/forjuris-logo";
import { StepIndicator } from "@/components/step-indicator";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from "@/components/ui/select";
import { Checkbox } from "@/components/ui/checkbox";
import { Separator } from "@/components/ui/separator";
import { useLead } from "@/contexts/AppProviders";
import { formatCurrency, maskPhone } from "@/lib/format";

export const Route = createFileRoute("/cadastro")({
  head: () => ({ meta: [{ title: "Receba os detalhes — Consulta Precatório SP" }] }),
  component: CadastroPage,
});

function CadastroPage() {
  const navigate = useNavigate();
  const lead = useLead();
  const [nome, setNome] = useState(lead.nome);
  const [email, setEmail] = useState(lead.email);
  const [telefone, setTelefone] = useState(lead.telefone);
  const [relacao, setRelacao] = useState(lead.relacao);
  const [consent, setConsent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const valid =
    nome.trim().split(/\s+/).length >= 2 &&
    /\S+@\S+\.\S+/.test(email) &&
    telefone.replace(/\D/g, "").length >= 10 &&
    relacao &&
    consent;

  const submit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!valid) {
      setError("Preencha todos os campos e aceite os termos.");
      return;
    }
    lead.setLeadData({ nome, email, telefone, relacao });
    navigate({ to: "/verificar/email" });
  };

  return (
    <div className="flex min-h-screen flex-col bg-muted">
      <header className="px-6 py-4">
        <Link to="/" aria-label="Forjuris — página inicial">
          <ForjurisLogo variant="default" size="sm" />
        </Link>
      </header>
      <main className="mx-auto w-full max-w-sm flex-1 px-4 pb-12">
        <div className="rounded-xl border bg-card p-6 shadow-sm">
          <StepIndicator current={2} />

          {lead.processo && (
            <div className="mb-5 grid grid-cols-2 gap-3 rounded-lg bg-muted px-4 py-3">
              <div>
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Processo</p>
                <p className="font-mono text-sm">
                  {lead.processo.replace(/\d(?=.*\d{4}$)/g, "•")}
                </p>
              </div>
              <div className="text-right">
                <p className="text-[10px] uppercase tracking-wide text-muted-foreground">Saldo DEPRE</p>
                <p className="text-base font-bold text-success">
                  {lead.saldo != null ? formatCurrency(lead.saldo) : "—"}
                </p>
              </div>
            </div>
          )}

          <h1 className="text-lg font-semibold">Receba os detalhes completos</h1>
          <p className="mt-1 text-sm text-muted-foreground">
            Informe seus dados para receber o relatório gratuitamente. Sem spam.
          </p>

          <form onSubmit={submit} className="mt-5 space-y-4">
            <div>
              <Label htmlFor="nome">Nome completo</Label>
              <Input
                id="nome"
                value={nome}
                onChange={(e) => setNome(e.target.value)}
                placeholder="Maria Aparecida da Silva"
                className="mt-1"
              />
            </div>
            <div>
              <Label htmlFor="email">E-mail</Label>
              <Input
                id="email"
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="seu@email.com"
                className="mt-1"
              />
              <p className="mt-1 text-xs text-muted-foreground">Enviaremos o relatório para este e-mail.</p>
            </div>
            <div>
              <Label htmlFor="telefone">WhatsApp</Label>
              <Input
                id="telefone"
                type="tel"
                value={telefone}
                onChange={(e) => setTelefone(maskPhone(e.target.value))}
                placeholder="(11) 99999-9999"
                className="mt-1"
              />
              <p className="mt-1 text-xs text-muted-foreground">Para enviar o código de verificação.</p>
            </div>
            <div>
              <Label>Relação com o processo</Label>
              <Select value={relacao} onValueChange={setRelacao}>
                <SelectTrigger className="mt-1 w-full">
                  <SelectValue placeholder="Selecione..." />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="titular">Sou o titular do precatório</SelectItem>
                  <SelectItem value="herdeiro">Sou herdeiro do titular</SelectItem>
                  <SelectItem value="advogado">Sou advogado do titular</SelectItem>
                </SelectContent>
              </Select>
            </div>

            <Separator />

            <div className="flex items-start gap-2">
              <Checkbox id="consent" checked={consent} onCheckedChange={(v) => setConsent(!!v)} />
              <label htmlFor="consent" className="text-xs leading-snug text-muted-foreground">
                Concordo em receber informações sobre este precatório por e-mail e WhatsApp. Posso solicitar exclusão dos meus dados a qualquer momento.{" "}
                <a href="#" className="text-primary hover:underline">Política de privacidade (LGPD)</a>.
              </label>
            </div>

            {error && !valid && <p className="text-xs text-error">{error}</p>}

            <Button type="submit" size="lg" className="w-full">
              Receber detalhes e verificar identidade →
            </Button>
          </form>
        </div>
      </main>
      <PublicFooter />
    </div>
  );
}
