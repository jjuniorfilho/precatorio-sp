import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { MessageCircle } from "lucide-react";
import { SuccessAlert, VerifyTokenScreen } from "@/components/verify-token-screen";
import { useLead } from "@/contexts/AppProviders";

export const Route = createFileRoute("/verificar/whatsapp")({
  head: () => ({ meta: [{ title: "Verificar WhatsApp — Consulta Precatório SP" }] }),
  component: VerificarWhatsappPage,
});

function VerificarWhatsappPage() {
  const navigate = useNavigate();
  const lead = useLead();
  return (
    <VerifyTokenScreen
      icon={<MessageCircle className="h-6 w-6 text-success" />}
      iconBg="bg-success-bg"
      title="Último passo: WhatsApp"
      destinationLabel="Código enviado para"
      destination={lead.telefone || "seu WhatsApp"}
      topAlert={<SuccessAlert>E-mail verificado com sucesso. Agora confirme seu WhatsApp.</SuccessAlert>}
      onConfirm={() => {
        try {
          localStorage.setItem(
            "consulta_session",
            JSON.stringify({
              validated: true,
              email: lead.email,
              phone: lead.telefone,
              validatedAt: new Date().toISOString(),
            }),
          );
        } catch {}
        navigate({ to: "/obrigado" });
      }}
    />
  );
}
