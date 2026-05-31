import { useEffect, useRef, type KeyboardEvent, type ClipboardEvent } from "react";
import { cn } from "@/lib/utils";

interface OtpInputProps {
  value: string;
  onChange: (v: string) => void;
  length?: number;
  disabled?: boolean;
}

export function OtpInput({ value, onChange, length = 6, disabled }: OtpInputProps) {
  const refs = useRef<(HTMLInputElement | null)[]>([]);

  useEffect(() => {
    const firstEmpty = value.length;
    refs.current[Math.min(firstEmpty, length - 1)]?.focus();
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  const digits = Array.from({ length }, (_, i) => value[i] ?? "");

  const setAt = (i: number, c: string) => {
    const arr = digits.slice();
    arr[i] = c;
    onChange(arr.join("").slice(0, length));
  };

  return (
    <div className="flex justify-center gap-2">
      {digits.map((d, i) => (
        <input
          key={i}
          ref={(el) => {
            refs.current[i] = el;
          }}
          inputMode="numeric"
          maxLength={1}
          disabled={disabled}
          value={d}
          onPaste={(e: ClipboardEvent<HTMLInputElement>) => {
            e.preventDefault();
            const text = e.clipboardData.getData("text").replace(/\D/g, "").slice(0, length);
            if (text) {
              onChange(text);
              refs.current[Math.min(text.length, length - 1)]?.focus();
            }
          }}
          onChange={(e) => {
            const c = e.target.value.replace(/\D/g, "").slice(-1);
            setAt(i, c);
            if (c && i < length - 1) refs.current[i + 1]?.focus();
          }}
          onKeyDown={(e: KeyboardEvent<HTMLInputElement>) => {
            if (e.key === "Backspace" && !digits[i] && i > 0) {
              refs.current[i - 1]?.focus();
            }
          }}
          className={cn(
            "h-14 w-12 rounded-lg border-2 bg-background text-center text-[22px] font-bold transition-colors focus:outline-none",
            d ? "border-primary" : "border-input",
            "focus:border-primary",
          )}
        />
      ))}
    </div>
  );
}
