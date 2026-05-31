import { Link, useRouterState } from "@tanstack/react-router";
import { Bell, LayoutDashboard, LogOut, Menu, Moon, Sun, Users, AlertTriangle, BarChart3 } from "lucide-react";
import { useState, type ReactNode } from "react";
import { useAdmin, useAuth, useTheme } from "@/contexts/AppProviders";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";

const nav = [
  { to: "/admin/funil", label: "Visão geral", icon: LayoutDashboard },
  { to: "/admin/leads", label: "Leads completos", icon: Users, hasBadge: true },
  { to: "/admin/incompletos", label: "Incompletos", icon: AlertTriangle },
  { to: "/admin/funil", label: "Funil", icon: BarChart3 },
];

export function AdminShell({
  title,
  subtitle,
  actions,
  children,
}: {
  title: string;
  subtitle?: string;
  actions?: ReactNode;
  children: ReactNode;
}) {
  const { newLeadsCount, clearNewLeadsCount } = useAdmin();
  const { theme, toggle } = useTheme();
  const { email, logout } = useAuth();
  const path = useRouterState({ select: (s) => s.location.pathname });
  const [mobileOpen, setMobileOpen] = useState(false);

  return (
    <div className="flex min-h-screen bg-background">
      {/* Sidebar desktop */}
      <aside className={cn("hidden w-64 shrink-0 flex-col border-r bg-sidebar sm:flex sticky top-0 h-screen")}>
        <SidebarContent path={path} newLeadsCount={newLeadsCount} clearNewLeadsCount={clearNewLeadsCount} email={email} onLogout={logout} />
      </aside>

      {/* Mobile drawer */}
      {mobileOpen && (
        <div className="fixed inset-0 z-50 sm:hidden">
          <div className="absolute inset-0 bg-foreground/40" onClick={() => setMobileOpen(false)} />
          <aside className="absolute left-0 top-0 flex h-full w-64 flex-col border-r bg-sidebar">
            <SidebarContent path={path} newLeadsCount={newLeadsCount} clearNewLeadsCount={clearNewLeadsCount} email={email} onLogout={logout} onNav={() => setMobileOpen(false)} />
          </aside>
        </div>
      )}

      <div className="flex min-w-0 flex-1 flex-col">
        <header className="sticky top-0 z-30 flex h-14 items-center justify-between gap-3 border-b bg-background px-4 sm:px-6">
          <div className="flex min-w-0 items-center gap-2">
            <Button variant="ghost" size="icon" className="sm:hidden" onClick={() => setMobileOpen(true)}>
              <Menu className="h-5 w-5" />
            </Button>
            <div className="min-w-0">
              <h1 className="truncate text-sm font-semibold sm:text-base">{title}</h1>
              {subtitle && <p className="truncate text-xs text-muted-foreground">{subtitle}</p>}
            </div>
          </div>
          <div className="flex items-center gap-2">
            {actions}
            <Button variant="ghost" size="icon" onClick={toggle} aria-label="Alternar tema">
              {theme === "light" ? <Moon className="h-4 w-4" /> : <Sun className="h-4 w-4" />}
            </Button>
            <Link to="/admin/leads" className="relative" onClick={clearNewLeadsCount}>
              <Button variant="ghost" size="icon" aria-label="Notificações">
                <Bell className="h-4 w-4" />
              </Button>
              {newLeadsCount > 0 && (
                <span className="absolute right-1 top-1 inline-flex h-4 min-w-4 items-center justify-center rounded-full bg-error px-1 text-[10px] font-bold text-white">
                  {newLeadsCount}
                </span>
              )}
            </Link>
          </div>
        </header>
        <main className="flex-1 p-4 sm:p-6">{children}</main>
      </div>
    </div>
  );
}

function SidebarContent({
  path,
  newLeadsCount,
  clearNewLeadsCount,
  email,
  onLogout,
  onNav,
}: {
  path: string;
  newLeadsCount: number;
  clearNewLeadsCount: () => void;
  email: string | null;
  onLogout: () => void;
  onNav?: () => void;
}) {
  return (
    <>
      <div className="border-b px-5 py-4">
        <p className="text-sm font-semibold">Consulta Precatório SP</p>
        <p className="text-xs text-muted-foreground">Painel Admin</p>
      </div>
      <nav className="flex-1 space-y-0.5 p-3">
        {nav.map((item, i) => {
          const active = path === item.to;
          return (
            <Link
              key={i}
              to={item.to}
              onClick={() => {
                if (item.to === "/admin/leads") clearNewLeadsCount();
                onNav?.();
              }}
              className={cn(
                "flex items-center gap-2 rounded-md px-3 py-2 text-sm transition-colors",
                active ? "bg-primary-50 font-medium text-primary" : "text-foreground hover:bg-sidebar-accent",
              )}
            >
              <item.icon className="h-4 w-4" />
              <span className="flex-1">{item.label}</span>
              {item.hasBadge && newLeadsCount > 0 && (
                <span className="inline-flex h-5 min-w-5 items-center justify-center rounded-full bg-primary px-1.5 text-[10px] font-bold text-primary-foreground">
                  {newLeadsCount}
                </span>
              )}
            </Link>
          );
        })}
      </nav>
      <div className="border-t p-3">
        <div className="flex items-center gap-2 rounded-md px-2 py-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary text-xs font-bold text-primary-foreground">
            A
          </div>
          <div className="min-w-0 flex-1">
            <p className="text-sm font-medium">Admin</p>
            <p className="truncate text-xs text-muted-foreground">{email}</p>
          </div>
          <Button variant="ghost" size="icon" onClick={onLogout} aria-label="Sair">
            <LogOut className="h-4 w-4" />
          </Button>
        </div>
      </div>
    </>
  );
}
