import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect, useState } from "react";
import { Loader2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { Separator } from "@/components/ui/separator";
import { useAuth } from "@/contexts/AppProviders";

export const Route = createFileRoute("/admin/login")({
  head: () => ({ meta: [{ title: "Admin · Login — Consulta Precatório SP" }] }),
  component: AdminLoginPage,
});

function AdminLoginPage() {
  const { login, isAuthenticated } = useAuth();
  const navigate = useNavigate();
  const [email, setEmail] = useState("admin@empresa.com");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    if (isAuthenticated) navigate({ to: "/admin/leads", replace: true });
  }, [isAuthenticated, navigate]);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    setError(null);
    const ok = await login(email, password);
    setLoading(false);
    if (ok) navigate({ to: "/admin/leads" });
    else setError("Credenciais inválidas. Use admin@empresa.com / admin123.");
  };

  return (
    <div className="flex min-h-screen items-center justify-center bg-muted px-4">
      <form onSubmit={submit} className="w-full max-w-sm rounded-xl border bg-card p-6 shadow-md">
        <h1 className="text-base font-bold">Consulta Precatório SP</h1>
        <p className="text-sm text-muted-foreground">Acesso restrito ao painel administrativo</p>

        <div className="mt-5 space-y-3">
          <div>
            <Label htmlFor="email">E-mail</Label>
            <Input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} className="mt-1" />
          </div>
          <div>
            <Label htmlFor="password">Senha</Label>
            <Input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} className="mt-1" placeholder="admin123" />
          </div>
        </div>

        {error && <p className="mt-3 text-xs text-error">{error}</p>}

        <Separator className="my-5" />

        <Button type="submit" size="lg" className="w-full" disabled={loading}>
          {loading ? <><Loader2 className="mr-2 h-4 w-4 animate-spin" /> Entrando...</> : "Entrar no painel"}
        </Button>
        <p className="mt-3 text-center text-xs text-muted-foreground">
          Autenticação via Supabase Auth. Sessão persistente.
        </p>
      </form>
    </div>
  );
}
