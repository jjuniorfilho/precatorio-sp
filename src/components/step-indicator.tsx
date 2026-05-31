import { Check } from "lucide-react";
import { cn } from "@/lib/utils";

interface StepIndicatorProps {
  current: 1 | 2 | 3 | 4;
  // step 3 has sub-stages a/b — render same as current=3
}

const STEPS = [
  { n: 1, label: "" },
  { n: 2, label: "Seus dados" },
  { n: 3, label: "Verificar" },
  { n: 4, label: "Pronto" },
];

export function StepIndicator({ current }: StepIndicatorProps) {
  return (
    <div className="mb-6 flex items-center justify-between gap-1">
      {STEPS.map((s, i) => {
        const completed = s.n < current;
        const active = s.n === current;
        return (
          <div key={s.n} className="flex flex-1 items-center gap-1">
            <div className="flex flex-col items-center gap-1">
              <div
                className={cn(
                  "flex h-7 w-7 items-center justify-center rounded-full text-xs font-semibold transition-colors",
                  completed && "bg-success text-white",
                  active && "bg-primary text-primary-foreground",
                  !completed && !active && "bg-muted text-muted-foreground",
                )}
              >
                {completed ? <Check className="h-4 w-4" /> : s.n}
              </div>
              {s.label && (
                <span
                  className={cn(
                    "text-[10px] font-medium uppercase tracking-wide whitespace-nowrap",
                    active ? "text-foreground" : "text-muted-foreground",
                  )}
                >
                  {s.label}
                </span>
              )}
            </div>
            {i < STEPS.length - 1 && (
              <div
                className={cn(
                  "mb-4 h-px flex-1",
                  s.n < current ? "bg-success" : "bg-border",
                )}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
