import { useEffect, useState } from "react";
import { Link } from "@tanstack/react-router";
import { PublicFooter } from "@/components/public-layout";
import { StepIndicator } from "@/components/step-indicator";
import { OtpInput } from "@/components/otp-input";
import { Button } from "@/components/ui/button";
import { Alert, AlertDescription } from "@/components/ui/alert";
import { cn } from "@/lib/utils";

interface VerifyTokenScreenProps {
  icon: React.ReactNode;
  iconBg: string;
  title: string;
  destinationLabel: string;
  destination: string;
  topAlert?: React.ReactNode;
  onConfirm: (code: string) => void;
}

export function VerifyTokenScreen({
  icon,
  iconBg,
  title,
  destinationLabel,
  destination,
  topAlert,
  onConfirm,
}: VerifyTokenScreenProps) {
  const [code, setCode] = useState("");
  const [seconds, setSeconds] = useState(600);
  const [resendIn, setResendIn] = useState(45);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    const i = setInterval(() => setSeconds((s) => (s > 0 ? s - 1 : 0)), 1000);
    return () => clearInterval(i);
  }, []);
  useEffect(() => {
    const i = setInterval(() => setResendIn((s) => (s > 0 ? s - 1 : 0)), 1000);
    return () => clearInterval(i);
  }, []);

  const expired = seconds === 0;
  const mm = String(Math.floor(seconds / 60)).padStart(2, "0");
  const ss = String(seconds % 60).padStart(2, "0");

  const handleConfirm = () => {
    if (expired) return;
    if (code.length !== 6) {
      setError("Digite os 6 dígitos do código.");
      return;
    }
    setError(null);
    onConfirm(code);
  };

  const resend = () => {
    setSeconds(600);
    setResendIn(45);
    setCode("");
  };

  return (
    <div className="flex min-h-screen flex-col bg-muted">
      <header className="px-6 py-4">
        <Link to="/" className="font-semibold tracking-tight">
          Consulta Precatório SP
        </Link>
      </header>
      <main className="mx-auto w-full max-w-sm flex-1 px-4 pb-12">
        <div className="rounded-xl border bg-card p-6 shadow-sm">
          <StepIndicator current={3} />

          {topAlert}

          <div className={cn("mx-auto mb-4 mt-2 flex h-12 w-12 items-center justify-center rounded-full", iconBg)}>
            {icon}
          </div>

          <h1 className="text-center text-lg font-semibold">{title}</h1>
          <p className="mt-1 text-center text-sm text-muted-foreground">
            {destinationLabel} <strong className="text-foreground">{destination}</strong>
          </p>

          <div className="mt-6">
            <OtpInput value={code} onChange={setCode} disabled={expired} />
          </div>

          <p className="mt-3 text-center text-xs text-muted-foreground">
            Expira em{" "}
            <span className={cn("font-semibold", seconds < 120 ? "text-warning-dark" : "text-foreground")}>
              {mm}:{ss}
            </span>
          </p>

          {expired && (
            <p className="mt-2 text-center text-xs text-error">
              Código expirado. Solicite um novo.
            </p>
          )}
          {error && <p className="mt-2 text-center text-xs text-error">{error}</p>}

          <Button size="lg" className="mt-5 w-full" onClick={handleConfirm} disabled={expired || code.length !== 6}>
            Confirmar código
          </Button>

          <Button
            variant="ghost"
            size="sm"
            className="mt-2 w-full"
            disabled={resendIn > 0}
            onClick={resend}
          >
            {resendIn > 0 ? `Reenviar código · disponível em ${resendIn}s` : "Reenviar código"}
          </Button>

          <p className="mt-4 text-center text-xs text-muted-foreground">
            Não encontrou? Verifique a pasta de spam.
          </p>
        </div>
      </main>
      <PublicFooter />
    </div>
  );
}

export function SuccessAlert({ children }: { children: React.ReactNode }) {
  return (
    <Alert className="mb-4 border-success/30 bg-success-bg">
      <AlertDescription className="text-sm text-success">{children}</AlertDescription>
    </Alert>
  );
}
