import { Link } from "@tanstack/react-router";
import { Moon, Sun } from "lucide-react";
import { useTheme } from "@/contexts/AppProviders";
import { Button } from "@/components/ui/button";
import { ForjurisLogo } from "@/components/forjuris-logo";

export function PublicNavbar() {
  const { theme, toggle } = useTheme();
  return (
    <header className="sticky top-0 z-40 h-14 bg-primary shadow-sm">
      <div className="mx-auto flex h-full max-w-6xl items-center justify-between px-4 sm:px-6">
        <Link to="/" aria-label="Forjuris — página inicial">
          <ForjurisLogo variant="navbar" size="md" />
        </Link>
        <nav className="flex items-center gap-1">
          <Link
            to="/"
            hash="como-funciona"
            className="hidden rounded-md px-3 py-1.5 text-sm text-white/80 hover:bg-white/10 hover:text-white sm:inline-block"
          >
            Como funciona
          </Link>
          <Link
            to="/"
            hash="faq"
            className="hidden rounded-md px-3 py-1.5 text-sm text-white/80 hover:bg-white/10 hover:text-white sm:inline-block"
          >
            Dúvidas
          </Link>
          <Button
            variant="ghost"
            size="icon"
            onClick={toggle}
            aria-label="Alternar tema"
            className="text-white/80 hover:bg-white/10 hover:text-white"
          >
            {theme === "light" ? <Moon className="h-4 w-4" /> : <Sun className="h-4 w-4" />}
          </Button>
        </nav>
      </div>
    </header>
  );
}

export function PublicFooter() {
  return (
    <footer className="bg-[#0C1B3D]">
      <div className="mx-auto max-w-6xl px-6 py-8 text-center text-sm">
        <ForjurisLogo variant="white" size="md" className="mb-3 inline-block" />
        <p className="text-white/50">
          CNPJ XX.XXX.XXX/XXXX-XX · <a href="#" className="text-white/60 hover:text-white">Termos de Uso</a> · <a href="#" className="text-white/60 hover:text-white">Privacidade (LGPD)</a>
        </p>
        <p className="mt-1.5 text-xs text-white/30">
          Dados públicos oficiais do DEPRE/TJSP. Sem relação com o Tribunal de Justiça.
        </p>
      </div>
    </footer>
  );
}
