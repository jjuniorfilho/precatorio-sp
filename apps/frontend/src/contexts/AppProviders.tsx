import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import {
  mockLeads,
  type CrmStatus,
  type Lead,
  type Precatorio,
} from "@/data/mockData";

// ---------------- Search ----------------
interface SearchState {
  query: string;
  result: Precatorio | null | "not_found" | "loading" | null;
  setQuery: (q: string) => void;
  setResult: (r: SearchState["result"]) => void;
}

const SearchCtx = createContext<SearchState | null>(null);

// ---------------- Lead ----------------
interface LeadData {
  processo: string | null;
  saldo: number | null;
  devedora: string | null;
  nome: string;
  email: string;
  telefone: string;
  relacao: string;
}
interface LeadCtxValue extends LeadData {
  setLeadData: (d: Partial<LeadData>) => void;
  reset: () => void;
}
const LeadCtx = createContext<LeadCtxValue | null>(null);

// ---------------- Auth ----------------
interface AuthCtxValue {
  isAuthenticated: boolean;
  email: string | null;
  login: (email: string, password: string) => Promise<boolean>;
  logout: () => void;
}
const AuthCtx = createContext<AuthCtxValue | null>(null);
const AUTH_KEY = "consulta_precatorio_admin_auth";

// ---------------- Admin ----------------
interface AdminCtxValue {
  leads: Lead[];
  newLeadsCount: number;
  updateLeadStatus: (id: string, status: CrmStatus) => void;
  updateLeadNotes: (id: string, notes: string) => void;
  clearNewLeadsCount: () => void;
}
const AdminCtx = createContext<AdminCtxValue | null>(null);

// ---------------- Theme ----------------
interface ThemeCtxValue {
  theme: "light" | "dark";
  toggle: () => void;
}
const ThemeCtx = createContext<ThemeCtxValue | null>(null);

export function AppProviders({ children }: { children: ReactNode }) {
  // search
  const [query, setQuery] = useState("");
  const [result, setResult] = useState<SearchState["result"]>(null);

  // lead
  const [lead, setLead] = useState<LeadData>({
    processo: null,
    saldo: null,
    devedora: null,
    nome: "",
    email: "",
    telefone: "",
    relacao: "",
  });
  const setLeadData = useCallback((d: Partial<LeadData>) => setLead((p) => ({ ...p, ...d })), []);
  const resetLead = useCallback(
    () =>
      setLead({
        processo: null,
        saldo: null,
        devedora: null,
        nome: "",
        email: "",
        telefone: "",
        relacao: "",
      }),
    [],
  );

  // auth
  const [auth, setAuth] = useState<{ isAuthenticated: boolean; email: string | null }>({
    isAuthenticated: false,
    email: null,
  });
  useEffect(() => {
    if (typeof window === "undefined") return;
    try {
      const raw = localStorage.getItem(AUTH_KEY);
      if (raw) setAuth(JSON.parse(raw));
    } catch {}
  }, []);
  const login = useCallback(async (email: string, password: string) => {
    await new Promise((r) => setTimeout(r, 500));
    if (email === "admin@empresa.com" && password === "admin123") {
      const next = { isAuthenticated: true, email };
      setAuth(next);
      localStorage.setItem(AUTH_KEY, JSON.stringify(next));
      return true;
    }
    return false;
  }, []);
  const logout = useCallback(() => {
    setAuth({ isAuthenticated: false, email: null });
    localStorage.removeItem(AUTH_KEY);
  }, []);

  // admin
  const [leads, setLeads] = useState<Lead[]>(mockLeads);
  const [newLeadsCount, setNewLeadsCount] = useState(12);
  useEffect(() => {
    const id = setInterval(() => setNewLeadsCount((n) => n + 1), 45000);
    return () => clearInterval(id);
  }, []);
  const updateLeadStatus = useCallback(
    (id: string, status: CrmStatus) =>
      setLeads((ls) => ls.map((l) => (l.id === id ? { ...l, status_crm: status } : l))),
    [],
  );
  const updateLeadNotes = useCallback(
    (id: string, notes: string) =>
      setLeads((ls) => ls.map((l) => (l.id === id ? { ...l, notas: notes } : l))),
    [],
  );
  const clearNewLeadsCount = useCallback(() => setNewLeadsCount(0), []);

  // theme
  const [theme, setTheme] = useState<"light" | "dark">("light");
  useEffect(() => {
    if (typeof window === "undefined") return;
    const saved = (localStorage.getItem("theme") as "light" | "dark" | null) ?? "light";
    setTheme(saved);
    document.documentElement.classList.toggle("dark", saved === "dark");
  }, []);
  const toggleTheme = useCallback(() => {
    setTheme((t) => {
      const next = t === "light" ? "dark" : "light";
      document.documentElement.classList.toggle("dark", next === "dark");
      localStorage.setItem("theme", next);
      return next;
    });
  }, []);

  const searchValue = useMemo(() => ({ query, result, setQuery, setResult }), [query, result]);
  const leadValue = useMemo(
    () => ({ ...lead, setLeadData, reset: resetLead }),
    [lead, setLeadData, resetLead],
  );
  const authValue = useMemo(
    () => ({ ...auth, login, logout }),
    [auth, login, logout],
  );
  const adminValue = useMemo(
    () => ({ leads, newLeadsCount, updateLeadStatus, updateLeadNotes, clearNewLeadsCount }),
    [leads, newLeadsCount, updateLeadStatus, updateLeadNotes, clearNewLeadsCount],
  );
  const themeValue = useMemo(() => ({ theme, toggle: toggleTheme }), [theme, toggleTheme]);

  return (
    <ThemeCtx.Provider value={themeValue}>
      <AuthCtx.Provider value={authValue}>
        <AdminCtx.Provider value={adminValue}>
          <SearchCtx.Provider value={searchValue}>
            <LeadCtx.Provider value={leadValue}>{children}</LeadCtx.Provider>
          </SearchCtx.Provider>
        </AdminCtx.Provider>
      </AuthCtx.Provider>
    </ThemeCtx.Provider>
  );
}

export const useSearch = () => {
  const v = useContext(SearchCtx);
  if (!v) throw new Error("SearchCtx missing");
  return v;
};
export const useLead = () => {
  const v = useContext(LeadCtx);
  if (!v) throw new Error("LeadCtx missing");
  return v;
};
export const useAuth = () => {
  const v = useContext(AuthCtx);
  if (!v) throw new Error("AuthCtx missing");
  return v;
};
export const useAdmin = () => {
  const v = useContext(AdminCtx);
  if (!v) throw new Error("AdminCtx missing");
  return v;
};
export const useTheme = () => {
  const v = useContext(ThemeCtx);
  if (!v) throw new Error("ThemeCtx missing");
  return v;
};
