import { supabase, ensureAuth } from "./supabase.js";
import { assertConfig } from "./config.js";

async function main() {
  assertConfig();
  await ensureAuth();
  const { count } = await supabase.from("precatorios").select("*", { count: "exact", head: true });
  console.log("total precatorios:", count);
  const { count: countEstado } = await supabase.from("precatorios").select("*", { count: "exact", head: true }).eq("fonte_relatorio", "estado");
  console.log("total fonte=estado:", countEstado);
}
main().then(() => process.exit(0)).catch((e) => { console.error(e); process.exit(1); });
