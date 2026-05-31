import type { Precatorio } from "@/data/mockData";

export function formatCurrency(centavos: number): string {
  return new Intl.NumberFormat("pt-BR", {
    style: "currency",
    currency: "BRL",
  }).format(centavos / 100);
}

export function formatDate(iso: string): string {
  return new Intl.DateTimeFormat("pt-BR", {
    dateStyle: "short",
    timeStyle: "short",
  }).format(new Date(iso));
}

export function formatRelativeDate(iso: string): string {
  const d = new Date(iso);
  const now = new Date();
  const isToday = d.toDateString() === now.toDateString();
  const yesterday = new Date(now);
  yesterday.setDate(now.getDate() - 1);
  const isYesterday = d.toDateString() === yesterday.toDateString();
  const time = d.toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" });
  if (isToday) return `Hoje ${time}`;
  if (isYesterday) return `Ontem ${time}`;
  return `${d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" })} ${time}`;
}

export function normalizeProcesso(input: string): string {
  return input.replace(/[\s.\-]/g, "").toLowerCase();
}

export function maskProcesso(processo: string): string {
  // 0122089-09.2025.8.26.0500 -> ●●●●●●●-●●.2025.8.26.0500
  const match = processo.match(/^[\d]+-[\d]+(\.\d{4}\..+)$/);
  if (!match) return processo;
  return `●●●●●●●-●●${match[1]}`;
}

export function firstName(fullName: string): string {
  return fullName.trim().split(/\s+/)[0] ?? "";
}

export function maskCpf(cpf: string): string {
  // 123.456.789-09 -> 1●●.●●●.●●●-●9
  const digits = cpf.replace(/\D/g, "");
  if (digits.length !== 11) return cpf;
  return `${digits[0]}●●.●●●.●●●-●${digits[10]}`;
}

export function findPrecatorio(
  input: string,
  precatorios: Precatorio[],
): Precatorio | null {
  const normalized = normalizeProcesso(input);
  if (!normalized) return null;
  return (
    precatorios.find(
      (p) =>
        normalizeProcesso(p.processo_depre) === normalized ||
        normalizeProcesso(p.autos) === normalized,
    ) ?? null
  );
}

export function maskPhone(value: string): string {
  const digits = value.replace(/\D/g, "").slice(0, 11);
  if (digits.length <= 2) return digits;
  if (digits.length <= 7) return `(${digits.slice(0, 2)}) ${digits.slice(2)}`;
  if (digits.length <= 10)
    return `(${digits.slice(0, 2)}) ${digits.slice(2, 6)}-${digits.slice(6)}`;
  return `(${digits.slice(0, 2)}) ${digits.slice(2, 7)}-${digits.slice(7)}`;
}
