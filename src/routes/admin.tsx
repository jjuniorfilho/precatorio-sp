import { createFileRoute, Outlet, useNavigate, useRouterState } from "@tanstack/react-router";
import { useEffect } from "react";
import { useAuth } from "@/contexts/AppProviders";

export const Route = createFileRoute("/admin")({
  component: AdminLayout,
});

function AdminLayout() {
  const { isAuthenticated } = useAuth();
  const navigate = useNavigate();
  const path = useRouterState({ select: (s) => s.location.pathname });
  const isLoginRoute = path === "/admin/login";

  useEffect(() => {
    if (isLoginRoute) return;
    if (!isAuthenticated) {
      navigate({ to: "/admin/login", replace: true });
    } else if (path === "/admin") {
      navigate({ to: "/admin/leads", replace: true });
    }
  }, [isAuthenticated, isLoginRoute, path, navigate]);

  if (!isLoginRoute && !isAuthenticated) return null;
  return <Outlet />;
}
