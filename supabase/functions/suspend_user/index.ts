// Създателят временно спира профил (без да го трие) и после го пуска отново.
import { createClient } from "npm:@supabase/supabase-js@2";

// Уеб версията (браузър) праща заявки от друг адрес – разрешаваме ги (CORS).
const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
function serveCors(h: (req: Request) => Promise<Response> | Response) {
  Deno.serve(async (req) => {
    if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
    const r = await h(req);
    const hd = new Headers(r.headers);
    for (const [k, v] of Object.entries(CORS)) hd.set(k, v);
    return new Response(r.body, { status: r.status, headers: hd });
  });
}


const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });

serveCors(async (req) => {
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
  let on = true;
  try {
    const b = await req.json();
    userId = String(b.user_id ?? "");
    on = b.suspend !== false;
  } catch {
    return json(400, { error: "bad_request" });
  }
  if (!userId || userId === caller.id) return json(400, { error: "bad_request" });

  // Банът спира входа и подновяването на сесията; полето в профила кара
  // приложението веднага да покаже „Профилът е временно спрян“.
  const { error } = await admin.auth.admin.updateUserById(userId, { ban_duration: on ? "876000h" : "none" });
  if (error) return json(500, { error: "ban_failed" });
  const { error: pErr } = await admin.from("profiles")
    .update({ suspended_at: on ? new Date().toISOString() : null }).eq("id", userId);
  if (pErr) return json(500, { error: "profile_failed" });
  if (on) await admin.from("device_tokens").delete().eq("user_id", userId);
  await admin.from("activity_log").insert({
    actor_id: caller.id, target_id: userId, action: on ? "Спря профила" : "Пусна профила отново",
  });
  return json(200, { ok: true });
});
