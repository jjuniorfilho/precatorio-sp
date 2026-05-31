import { cn } from "@/lib/utils";
import type { CrmStatus } from "@/data/mockData";
import { crmStatusLabel } from "@/data/mockData";

const map: Record<CrmStatus, string> = {
  novo: "bg-blue-50 text-blue-700 ring-blue-200 dark:bg-blue-950/40 dark:text-blue-300 dark:ring-blue-900",
  contatado: "bg-cyan-50 text-cyan-700 ring-cyan-200 dark:bg-cyan-950/40 dark:text-cyan-300 dark:ring-cyan-900",
  qualificado: "bg-yellow-50 text-yellow-700 ring-yellow-200 dark:bg-yellow-950/40 dark:text-yellow-300 dark:ring-yellow-900",
  interessado: "bg-orange-50 text-orange-700 ring-orange-200 dark:bg-orange-950/40 dark:text-orange-300 dark:ring-orange-900",
  proposta: "bg-purple-50 text-purple-700 ring-purple-200 dark:bg-purple-950/40 dark:text-purple-300 dark:ring-purple-900",
  negociacao: "bg-pink-50 text-pink-700 ring-pink-200 dark:bg-pink-950/40 dark:text-pink-300 dark:ring-pink-900",
  fechado: "bg-green-50 text-green-700 ring-green-200 dark:bg-green-950/40 dark:text-green-300 dark:ring-green-900",
  descartado: "bg-muted text-muted-foreground ring-border",
};

export function CrmBadge({
  status,
  className,
  muted,
}: {
  status: CrmStatus;
  className?: string;
  muted?: boolean;
}) {
  return (
    <span
      className={cn(
        "inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium ring-1 ring-inset",
        muted ? "bg-muted text-muted-foreground ring-border opacity-70" : map[status],
        className,
      )}
    >
      {crmStatusLabel[status]}
    </span>
  );
}
