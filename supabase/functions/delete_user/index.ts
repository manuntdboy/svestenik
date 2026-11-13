// Създателят изтрива профил при поискване (GDPR). Събитията, записани от
// него за колеги, минават към председателя; записите в касата остават с
// „изтрит потребител“. Председател на храм с други свещеници не се трие,
// докато не се определи нов председател.
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });
  const url = Deno.env.get("SUPABASE_URL")!;
  let secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  if (!secret) {
    try {
      secret = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}").default ?? "";
    } catch {
      secret = "";
    }
  }
  if (!secret) return json(500, { error: "server_config" });
  const admin = createClient(url, secret, { auth: { persistSession: false, autoRefreshToken: false } });

  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who } = await admin.auth.getUser(jwt);
  const caller = who?.user;
  if (!caller) return json(401, { error: "not_authenticated" });
  const { data: creator } = await admin.from("app_creators").select("user_id").eq("user_id", caller.id).maybeSingle();
  if (!creator) return json(403, { error: "forbidden" });

  let userId = "";
  try {
    userId = String((await req.json()).user_id ?? "");
  } catch {
    return json(400, { error: "bad_request" });
  }
  if (!userId || userId === caller.id) return json(400, { error: "bad_request" });

  const { error: prepErr } = await admin.rpc("creator_prepare_delete", { p_user: userId });
  if (prepErr) {
    return json(409, { error: String(prepErr.message ?? "").includes("is_chair") ? "is_chair" : "prepare_failed" });
  }
  const { error } = await admin.auth.admin.deleteUser(userId);
  if (error) return json(500, { error: "delete_failed" });
  return json(200, { ok: true });
});
