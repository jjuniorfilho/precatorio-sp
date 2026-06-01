import { cn } from "@/lib/utils";

type Variant = "default" | "white" | "navbar";
type Size    = "sm" | "md" | "lg" | "xl";

interface ForjurisLogoProps {
  variant?: Variant;
  size?: Size;
  className?: string;
}

const sizes: Record<Size, string> = {
  sm: "text-lg",      // 18px — mobile header
  md: "text-xl",      // 20px — navbar padrão
  lg: "text-2xl",     // 24px — landing / cards
  xl: "text-3xl",     // 30px — hero / splash
};

const colors: Record<Variant, { for: string; juris: string }> = {
  default: { for: "text-primary",       juris: "text-[#0C1B3D]" },
  white:   { for: "text-white/70",      juris: "text-white" },
  navbar:  { for: "text-white/60",      juris: "text-white" },
};

export function ForjurisLogo({
  variant = "default",
  size = "md",
  className,
}: ForjurisLogoProps) {
  const c = colors[variant];
  return (
    <span
      className={cn(
        "font-heading font-bold tracking-tight select-none",
        sizes[size],
        className
      )}
      aria-label="Forjuris"
    >
      <span className={c.for}>For</span>
      <span className={c.juris}>juris</span>
    </span>
  );
}

/** Ícone quadrado "FJ" — usar em favicon, app icon, avatar */
export function ForjurisIcon({ size = 32, className }: { size?: number; className?: string }) {
  return (
    <svg
      width={size}
      height={size}
      viewBox="0 0 32 32"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      className={className}
      aria-label="Forjuris"
    >
      <rect width="32" height="32" rx="7" fill="#2B4FA8" />
      <text
        fontFamily="Sora, sans-serif"
        fontWeight="800"
        fontSize="13"
        fill="white"
        x="4"
        y="22"
        letterSpacing="0.5"
      >
        FJ
      </text>
    </svg>
  );
}
