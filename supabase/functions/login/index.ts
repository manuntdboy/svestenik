// Вход с потребителско име и парола.
// Намира имейла по потребителското име на сървъра (така имейлите не се
// показват на никого), влиза и връща сесията на приложението.
import { createClient } from "npm:@supabase/supabase-js@2";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const WRONG = { error: "wrong_credentials" };

Deno.serve(async (req) => {
  if (req.method !== "POST") return json(405, { error: "method_not_allowed" });

  let username = "";
  let password = "";
  try {
    const body = await req.json();
    username = String(body.username ?? "").trim().toLowerCase();
    password = String(body.password ?? "");
  } catch {
    return json(400, { error: "bad_request" });
  }
  if (!username || !password) return json(400, { error: "bad_request" });

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

  const admin = createClient(url, secret, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  const { data: profile } = await admin
    .from("profiles")
    .select("id")
    .eq("username", username)
    .maybeSingle();
  if (!profile) return json(401, WRONG);

  const { data: userData, error: userErr } = await admin.auth.admin.getUserById(profile.id);
  const email = userData?.user?.email;
  if (userErr || !email) return json(401, WRONG);

  const { data, error } = await admin.auth.signInWithPassword({ email, password });
  if (error || !data.session) {
    if (error?.message?.toLowerCase().includes("not confirmed")) {
      return json(401, { error: "email_not_confirmed" });
    }
    return json(401, WRONG);
  }

  return json(200, {
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
  });
});
