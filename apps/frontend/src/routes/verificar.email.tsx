import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Mail } from "lucide-react";
import { VerifyTokenScreen } from "@/components/verify-token-screen";
import { useLead } from "@/contexts/AppProviders";

export const Route = createFileRoute("/verificar/email")({
  head: () => ({ meta: [{ title: "Verificar e-mail — Consulta Precatório SP" }] }),
  component: VerificarEmailPage,
});

function VerificarEmailPage() {
  const navigate = useNavigate();
  const lead = useLead();
  return (
    <VerifyTokenScreen
      icon={<Mail className="h-6 w-6 text-primary" />}
      iconBg="bg-primary-50"
      title="Verifique seu e-mail"
      destinationLabel="Enviamos um código de 6 dígitos para"
      destination={lead.email || "seu e-mail"}
      onConfirm={() => navigate({ to: "/verificar/whatsapp" })}
    />
  );
}
