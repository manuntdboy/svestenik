// Push известие до свещеника, за когото колега е записал (или променил) събитие.
// Извиква се от приложението след запис. Проверява, че извикващият е записал
// събитието, и праща известие през Firebase Cloud Messaging (HTTP v1).
//
// Нужна тайна в Supabase (Edge Functions → Secrets): FCM_SERVICE_ACCOUNT –
// целият JSON ключ на service account с роля „Firebase Cloud Messaging API Admin“.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const KIND: Record<string, string> = {
  krashtene: "Кръщене",
  venchavka: "Венчавка",
  pogrebenie: "Погребение",
  panihida: "Панихида",
  vodosvet: "Водосвет",
  sluzhba: "Служба",
  izpoved: "Изповед",
  maslosvet: "Маслосвет",
  kurban: "Курбан",
  drugo: "Друго",
};

type ServiceAccount = { client_email: string; private_key: string; project_id: string; token_uri?: string };

let cachedToken: { value: string; expires: number } | null = null;

async function fcmAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires > now + 60) return cachedToken.value;
  const tokenUri = sa.token_uri ?? "https://oauth2.googleapis.com/token";
  const key = await importPKCS8(sa.private_key, "RS256");
  const assertion = await new SignJWT({ scope: "https://www.googleapis.com/auth/firebase.messaging" })
    .setProtectedHeader({ alg: "RS256", typ: "JWT" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience(tokenUri)
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);
  const res = await fetch(tokenUri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  if (!res.ok) throw new Error(`token ${res.status}: ${await res.text()}`);
  const data = await res.json();
  cachedToken = { value: data.access_token, expires: now + (data.expires_in ?? 3600) };
  return cachedToken.value;
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

  // Кой извиква?
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: who } = await admin.auth.getUser(jwt);
  const caller = who?.user;
  if (!caller) return json(401, { error: "not_authenticated" });

  let eventId = "";
  let change = "created";
  try {
    const body = await req.json();
    eventId = String(body.event_id ?? "");
    change = body.change === "updated" ? "updated" : "created";
  } catch {
    return json(400, { error: "bad_request" });
  }

  const { data: ev } = await admin.from("events").select("*").eq("id", eventId).maybeSingle();
  if (!ev) return json(404, { error: "not_found" });
  // Само записалият може да уведоми; на себе си не пращаме.
  if (ev.owner_id !== caller.id) return json(403, { error: "forbidden" });
  if (ev.assignee_id === caller.id) return json(200, { sent: 0, reason: "self" });

  const { data: tokens } = await admin.from("device_tokens").select("token").eq("user_id", ev.assignee_id);
  if (!tokens || tokens.length === 0) return json(200, { sent: 0, reason: "no_devices" });

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "");
  } catch {
    return json(500, { error: "fcm_not_configured" });
  }

  const { data: author } = await admin.from("profiles").select("full_name").eq("id", caller.id).maybeSingle();
  const when = new Date(ev.starts_at).toLocaleString("bg-BG", {
    timeZone: "Europe/Sofia",
    weekday: "long",
    day: "numeric",
    month: "long",
    hour: "2-digit",
    minute: "2-digit",
  });
  const kind = KIND[ev.kind] ?? "Събитие";
  const title = change === "updated" ? `Промяна: ${kind}` : `Ново събитие за вас: ${kind}`;
  const parts = [when];
  if (ev.for_whom) parts.push(ev.for_whom);
  if (author?.full_name) parts.push(`записа ${author.full_name}`);
  const body = parts.join(" · ");

  const access = await fcmAccessToken(sa);
  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data: { event_id: ev.id, church_id: ev.church_id },
          android: { priority: "high", notification: { channel_id: "events", sound: "default" } },
        },
      }),
    });
    if (res.ok) {
      sent++;
    } else {
      const text = await res.text();
      // Изтрит или сменен токен – махаме го.
      if (res.status === 404 || text.includes("UNREGISTERED") || text.includes("INVALID_ARGUMENT")) {
        await admin.from("device_tokens").delete().eq("token", token);
      } else {
        console.error("FCM", res.status, text);
      }
    }
  }
  return json(200, { sent });
});
