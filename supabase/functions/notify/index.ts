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

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json(400, { error: "bad_request" });
  }
  const type = String(body.type ?? "event");

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "");
  } catch {
    return json(500, { error: "fcm_not_configured" });
  }

  const { data: callerProfile } = await admin.from("profiles").select("full_name").eq("id", caller.id).maybeSingle();
  const callerName = callerProfile?.full_name ?? "";

  // Кому и какво пращаме.
  let recipients: string[] = [];
  let title = "";
  let text = "";
  let data: Record<string, string> = {};

  if (type === "join_request") {
    // Нов свещеник чака одобрение → до председателите на храма.
    const churchId = String(body.church_id ?? "");
    const { data: me } = await admin.from("church_members").select("status")
      .eq("church_id", churchId).eq("user_id", caller.id).maybeSingle();
    if (!me || me.status !== "pending") return json(403, { error: "forbidden" });
    const { data: church } = await admin.from("churches").select("name").eq("id", churchId).maybeSingle();
    const { data: managers } = await admin.from("church_members").select("user_id")
      .eq("church_id", churchId).eq("role", "manager").eq("status", "active");
    recipients = (managers ?? []).map((m) => m.user_id);
    title = "Нов свещеник чака одобрение";
    text = `${callerName} иска да се присъедини към ${church?.name ?? "храма"}`;
    data = { type, church_id: churchId };
  } else if (type === "member_approved") {
    // Председателят одобри → до одобрения свещеник.
    const churchId = String(body.church_id ?? "");
    const userId = String(body.user_id ?? "");
    const { data: me } = await admin.from("church_members").select("role,status")
      .eq("church_id", churchId).eq("user_id", caller.id).maybeSingle();
    if (!me || me.role !== "manager" || me.status !== "active") return json(403, { error: "forbidden" });
    const { data: target } = await admin.from("church_members").select("status")
      .eq("church_id", churchId).eq("user_id", userId).maybeSingle();
    if (!target || target.status !== "active") return json(409, { error: "not_approved" });
    const { data: church } = await admin.from("churches").select("name").eq("id", churchId).maybeSingle();
    recipients = [userId];
    title = "Одобрен сте";
    text = `${callerName} ви одобри в ${church?.name ?? "храма"}. Отворете Кайрос.`;
    data = { type, church_id: churchId };
  } else {
    // Събитие, записано от колега.
    const eventId = String(body.event_id ?? "");
    const change = body.change === "updated" ? "updated" : "created";
    const { data: ev } = await admin.from("events").select("*").eq("id", eventId).maybeSingle();
    if (!ev) return json(404, { error: "not_found" });
    // Само записалият може да уведоми; на себе си не пращаме.
    if (ev.owner_id !== caller.id) return json(403, { error: "forbidden" });
    if (ev.assignee_id === caller.id) return json(200, { sent: 0, reason: "self" });
    const when = new Date(ev.starts_at).toLocaleString("bg-BG", {
      timeZone: "Europe/Sofia",
      weekday: "long",
      day: "numeric",
      month: "long",
      hour: "2-digit",
      minute: "2-digit",
    });
    const kind = KIND[ev.kind] ?? "Събитие";
    title = change === "updated" ? `Промяна: ${kind}` : `Ново събитие за вас: ${kind}`;
    const parts = [when];
    if (ev.for_whom) parts.push(ev.for_whom);
    if (callerName) parts.push(`записа ${callerName}`);
    text = parts.join(" · ");
    recipients = [ev.assignee_id];
    data = { type: "event", event_id: ev.id, church_id: ev.church_id };
  }

  recipients = recipients.filter((r) => r && r !== caller.id);
  if (recipients.length === 0) return json(200, { sent: 0, reason: "no_recipients" });
  const { data: tokens } = await admin.from("device_tokens").select("token").in("user_id", recipients);
  if (!tokens || tokens.length === 0) return json(200, { sent: 0, reason: "no_devices" });

  const access = await fcmAccessToken(sa);
  let sent = 0;
  for (const { token } of tokens) {
    const res = await fetch(`https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`, {
      method: "POST",
      headers: { Authorization: `Bearer ${access}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body: text },
          data,
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
