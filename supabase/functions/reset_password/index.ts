// Председателят дава временна парола на свещеник от своя храм.
// Свещеникът влиза с нея и приложението го кара веднага да си смени паролата.
// Всяко нулиране се записва в password_resets (кой, на кого, кога).
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Лесна за диктуване парола: 4 букви (без объркващи) + 4 цифри.
function tempPassword(): string {
  const letters = "abcdefghjkmnpqrstuvwxyz";
  const digits = "23456789";
  const rnd = new Uint32Array(8);
  crypto.getRandomValues(rnd);
  let s = "";
  for (let i = 0; i < 4; i++) s += letters[rnd[i] % letters.length];
  for (let i = 4; i < 8; i++) s += digits[rnd[i] % digits.length];
  return s;
}

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

  let churchId = "";
  let userId = "";
  try {
    const body = await req.json();
    churchId = String(body.church_id ?? "");
    userId = String(body.user_id ?? "");
  } catch {
    return json(400, { error: "bad_request" });
  }
  if (!userId) return json(400, { error: "bad_request" });
  if (userId === caller.id) return json(400, { error: "own_password" });

  // Създателят може за всеки; председателят – само в своя храм.
  const { data: creator } = await admin.from("app_creators").select("user_id").eq("user_id", caller.id).maybeSingle();
  if (!creator) {
    if (!churchId) return json(400, { error: "bad_request" });
    const { data: me } = await admin.from("church_members").select("role,status")
      .eq("church_id", churchId).eq("user_id", caller.id).maybeSingle();
    if (!me || me.role !== "manager" || me.status !== "active") return json(403, { error: "not_manager" });
    const { data: target } = await admin.from("church_members").select("status")
      .eq("church_id", churchId).eq("user_id", userId).maybeSingle();
    if (!target) return json(404, { error: "not_member" });
  }

  const password = tempPassword();
  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) return json(500, { error: "update_failed" });
  await admin.from("password_resets").insert({ church_id: churchId || null, user_id: userId, by_user: caller.id });
  return json(200, { password });
});
