import { Link } from "@tanstack/react-router";
import { Moon, Sun } from "lucide-react";
import { useTheme } from "@/contexts/AppProviders";
import { Button } from "@/components/ui/button";

export function PublicNavbar() {
  const { theme, toggle } = useTheme();
  return (
    <header className="sticky top-0 z-40 h-14 border-b bg-background/80 backdrop-blur">
      <div className="mx-auto flex h-full max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link to="/" className="font-semibold tracking-tight">
          Consulta Precatório SP
        </Link>
        <nav className="flex items-center gap-1">
          <Link
            to="/"
            hash="como-funciona"
            className="hidden rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted hover:text-foreground sm:inline-block"
          >
            Como funciona
          </Link>
          <Link
            to="/"
            hash="faq"
            className="hidden rounded-md px-3 py-1.5 text-sm text-muted-foreground hover:bg-muted hover:text-foreground sm:inline-block"
          >
            Dúvidas
          </Link>
          <Button variant="ghost" size="icon" onClick={toggle} aria-label="Alternar tema">
            {theme === "light" ? <Moon className="h-4 w-4" /> : <Sun className="h-4 w-4" />}
          </Button>
        </nav>
      </div>
    </header>
  );
}

export function PublicFooter() {
  return (
    <footer className="border-t bg-muted">
      <div className="mx-auto max-w-6xl px-6 py-6 text-center text-sm text-muted-foreground">
        <p className="mb-1.5 font-semibold text-foreground">Consulta Precatório SP</p>
        <p>CNPJ 12.345.678/0001-90 · Termos de Uso · Privacidade (LGPD)</p>
        <p className="mt-1 text-xs">
          Dados públicos oficiais do DEPRE/TJSP. Sem relação com o Tribunal de Justiça.
        </p>
      </div>
    </footer>
  );
}
