import type { Precatorio } from "@/data/mockData";

export type InputType = "processo" | "cpf" | "cnpj" | "desconhecido";

export function detectInputType(input: string): InputType {
  const digits = input.replace(/\D/g, "");
  if (input.includes(".8.26.") || /\d{7}-\d{2}\.\d{4}/.test(input)) return "processo";
  if (digits.length === 11) return "cpf";
  if (digits.length === 14) return "cnpj";
  return "desconhecido";
}

export function normalizeInput(input: string): string {
  return input.replace(/[\s.\-/]/g, "").toLowerCase();
}

export function findByCpf(cpf: string, precatorios: Precatorio[]): Precatorio[] {
  const n = normalizeInput(cpf);
  return precatorios.filter((p) => p.cpf_titular && normalizeInput(p.cpf_titular) === n);
}

export function findByCnpj(cnpj: string, precatorios: Precatorio[]): Precatorio[] {
  const n = normalizeInput(cnpj);
  return precatorios.filter((p) => p.cnpj_titular && normalizeInput(p.cnpj_titular) === n);
}

export function maskCpfPartial(cpf: string): string {
  const m = cpf.match(/^(\d{3})\.?\d{3}\.?\d{3}-?(\d{2})$/);
  if (!m) return cpf;
  return `${m[1]}.***.***-${m[2]}`;
}

export function maskCnpjPartial(cnpj: string): string {
  const m = cnpj.match(/^(\d{2})\.?\d{3}\.?\d{3}\/?(\d{4})-?(\d{2})$/);
  if (!m) return cnpj;
  return `${m[1]}.***.***/${m[2]}-${m[3]}`;
}
