import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";

export const Route = createFileRoute("/admin/")({
  component: () => {
    const navigate = useNavigate();
    useEffect(() => {
      navigate({ to: "/admin/leads", replace: true });
    }, [navigate]);
    return null;
  },
});
