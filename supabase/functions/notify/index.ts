// Push известие до свещеника, за когото колега е записал (или променил) събитие.
// Извиква се от приложението след запис. Проверява, че извикващият е записал
// събитието, и праща известие през Firebase Cloud Messaging (HTTP v1).
//
// Нужна тайна в Supabase (Edge Functions → Secrets): FCM_SERVICE_ACCOUNT –
// целият JSON ключ на service account с роля „Firebase Cloud Messaging API Admin“.
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5";

// Сан пред името – същото правило като в приложението (models.dart withRank).
const RANKS: Record<string, string> = {
  deacon: "Дякон", hierodeacon: "Йеродякон", protodeacon: "Протодякон", archdeacon: "Архидякон",
  priest: "Иерей", hieromonk: "Йеромонах", archpriest: "Протойерей", stavrophor: "Свещеноиконом",
  archimandrite: "Архимандрит", bishop: "Епископ",
};
const TITLE_WORDS = new Set(["о.", "о", "отец", "свещеник", "иерей", "йерей", "протойерей", "протоиерей",
  "дякон", "протодякон", "свещеноиконом", "ставрофор", "йеродякон", "иеродякон",
  "архидякон", "йеромонах", "иеромонах", "архимандрит", "епископ", "владика"]);
function withRank(rank: string | null | undefined, name: string): string {
  const label = rank ? RANKS[rank] : undefined;
  if (!label) return name;
  let words = name.trim().split(/\s+/).filter((w) => w);
  while (words.length) {
    const w = words[0].toLowerCase();
    if (TITLE_WORDS.has(w)) words = words.slice(1);
    else if (w.startsWith("о.") && w.length > 2) words = [words[0].slice(2), ...words.slice(1)];
    else break;
  }
  return words.length ? `${label} ${words.join(" ")}` : label;
}


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
  arhiereyska: "Архиерейска Литургия",
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

async function handle(req: Request): Promise<Response> {
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
    // Тайната е записана и като CM_SERVICE_ACCOUNT (без F) – приемаме и двете.
    sa = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? Deno.env.get("CM_SERVICE_ACCOUNT") ?? "");
  } catch {
    return json(500, { error: "fcm_not_configured" });
  }

  const { data: callerProfile } = await admin.from("profiles").select("full_name, rank").eq("id", caller.id).maybeSingle();
  const callerName = withRank(callerProfile?.rank, callerProfile?.full_name ?? "");

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
  } else if (type === "chair_proposed" || type === "chair_responded") {
    const churchId = String(body.church_id ?? "");
    const { data: church } = await admin.from("churches").select("name,pending_chair,chair_proposed_by")
      .eq("id", churchId).maybeSingle();
    if (!church) return json(404, { error: "not_found" });
    if (type === "chair_proposed") {
      const { data: me } = await admin.from("church_members").select("role,status")
        .eq("church_id", churchId).eq("user_id", caller.id).maybeSingle();
      if (!me || me.role !== "manager" || me.status !== "active" || !church.pending_chair) {
        return json(403, { error: "forbidden" });
      }
      recipients = [church.pending_chair];
      title = "Предложение да станете председател";
      text = `${callerName} ви предлага за председател на ${church.name}. Отворете Кайрос, за да отговорите.`;
    } else {
      const proposer = String(body.proposer_id ?? "");
      const accepted = body.accepted === true;
      const { data: me } = await admin.from("church_members").select("role")
        .eq("church_id", churchId).eq("user_id", caller.id).maybeSingle();
      // при приемане извикващият вече е председател; при отказ – не
      if (!me || (accepted && me.role !== "manager")) return json(403, { error: "forbidden" });
      const { data: prop } = await admin.from("church_members").select("user_id")
        .eq("church_id", churchId).eq("user_id", proposer).maybeSingle();
      if (!prop) return json(403, { error: "forbidden" });
      recipients = [proposer];
      title = accepted ? `${callerName} е новият председател` : `${callerName} отказа председателството`;
      text = accepted
        ? `Вие вече сте редови свещеник в ${church.name}.`
        : `Остава председател на ${church.name} както досега.`;
    }
    data = { type, church_id: churchId };
  } else if (type === "leave_request" || type === "leave_decided") {
    const requestId = String(body.request_id ?? "");
    const { data: lv } = await admin.from("leave_requests").select("*").eq("id", requestId).maybeSingle();
    if (!lv) return json(404, { error: "not_found" });
    const fmt = (d: string) =>
      new Date(d + "T12:00:00Z").toLocaleDateString("bg-BG", { day: "numeric", month: "long" });
    const period = lv.start_date === lv.end_date ? fmt(lv.start_date) : `${fmt(lv.start_date)} – ${fmt(lv.end_date)}`;
    if (type === "leave_request") {
      if (lv.user_id !== caller.id || lv.status !== "pending") return json(403, { error: "forbidden" });
      const { data: managers } = await admin.from("church_members").select("user_id")
        .eq("church_id", lv.church_id).eq("role", "manager").eq("status", "active");
      recipients = (managers ?? []).map((m) => m.user_id);
      title = "Заявка за почивка";
      text = `${callerName} · ${period}${lv.note ? " · " + lv.note : ""}`;
    } else {
      const { data: me } = await admin.from("church_members").select("role,status")
        .eq("church_id", lv.church_id).eq("user_id", caller.id).maybeSingle();
      if (!me || me.role !== "manager" || me.status !== "active") return json(403, { error: "forbidden" });
      recipients = [lv.user_id];
      title = lv.status === "approved" ? "Почивката е одобрена" : "Почивката не е одобрена";
      text = `${period} · ${callerName}`;
    }
    data = { type, church_id: lv.church_id, request_id: lv.id };
  } else if (type === "stock_loaded" || type === "stock_pending" || type === "stock_decided") {
    // Склад: зареждане (за знание) и ръчно изписване (за одобрение) → другият; решение → въвелият.
    const moveId = String(body.move_id ?? "");
    const { data: mv } = await admin.from("stock_moves").select("*").eq("id", moveId).maybeSingle();
    if (!mv) return json(404, { error: "not_found" });
    const ITEMS: Record<string, [string, string]> = {
      candle_040: ["свещи 0,40 €", "кг"], candle_1: ["свещи 1 €", "кг"], candle_4: ["свещи 4 €", "кг"],
      cert_baptism: ["кръщелни свидетелства", "бр."], cert_wedding: ["венчални свидетелства", "бр."],
      diploma: ["грамоти", "бр."],
    };
    const [name, unit] = ITEMS[mv.item] ?? [mv.item, ""];
    const q = `${Math.abs(mv.qty)} ${unit} ${name}`;
    const { data: members } = await admin.from("church_members").select("user_id, role, permissions")
      .eq("church_id", mv.church_id).eq("status", "active");
    const holders = (members ?? []).filter((m) => m.role === "manager" || (m.permissions ?? []).includes("cash"))
      .map((m) => m.user_id);
    if (type === "stock_loaded") {
      if (mv.created_by !== caller.id || mv.kind !== "load") return json(403, { error: "forbidden" });
      recipients = holders;
      title = "Склад: заредено";
      text = `${callerName} зареди ${q}`;
    } else if (type === "stock_pending") {
      if (mv.created_by !== caller.id || mv.status !== "pending") return json(403, { error: "forbidden" });
      recipients = holders;
      title = "Склад: изписване чака одобрение";
      text = `${q} · ${mv.note ?? ""} · ${callerName}`;
    } else {
      if (mv.decided_by !== caller.id) return json(403, { error: "forbidden" });
      recipients = [mv.created_by];
      title = mv.status === "approved" ? "Склад: изписването е одобрено" : "Склад: изписването е върнато";
      text = `${q}${mv.return_reason ? " · " + mv.return_reason : ""} · ${callerName}`;
    }
    data = { type: "stock", church_id: mv.church_id };
  } else if (type === "cash_close_pending" || type === "cash_close_decided") {
    // Приключване на месец: касиерът иска → председателят; решение → касиерът.
    const churchId = String(body.church_id ?? "");
    const month = String(body.month ?? "");
    const { data: members } = await admin.from("church_members").select("user_id, role, permissions")
      .eq("church_id", churchId).eq("status", "active");
    const me = (members ?? []).find((m) => m.user_id === caller.id);
    const label = new Date(month + "T12:00:00Z").toLocaleDateString("bg-BG", { month: "long", year: "numeric" });
    if (type === "cash_close_pending") {
      const { data: per } = await admin.from("cash_periods").select("*")
        .eq("church_id", churchId).eq("month", month).maybeSingle();
      if (!per || per.requested_by !== caller.id || per.status !== "pending") return json(403, { error: "forbidden" });
      recipients = (members ?? []).filter((m) => m.role === "manager").map((m) => m.user_id);
      title = "Каса: приключване на месеца";
      text = `${callerName} иска да приключи ${label} – моля, одобрете`;
    } else {
      if (!me || me.role !== "manager") return json(403, { error: "forbidden" });
      const cashier = (members ?? []).find((m) => m.role !== "manager" && (m.permissions ?? []).includes("cash"));
      recipients = cashier ? [cashier.user_id] : [];
      title = body.approved ? `Каса: ${label} е приключен` : `Каса: приключването на ${label} е върнато`;
      text = callerName;
    }
    data = { type: "cash", church_id: churchId };
  } else if (type === "cash_pending" || type === "cash_decided") {
    // Каса: чакащ запис → до този, който трябва да го реши; решение → до въвелия.
    const entryId = String(body.entry_id ?? "");
    const { data: ce } = await admin.from("cash_entries").select("*").eq("id", entryId).maybeSingle();
    if (!ce) return json(404, { error: "not_found" });
    const eur = new Intl.NumberFormat("bg-BG", { style: "currency", currency: "EUR" }).format(Math.abs(Number(ce.amount)));
 const what = ce.reverses ? "Сторно" : ce.book === "opening" ? "Начално салдо" : ce.book === "income" ? "Приход" : ce.book === "expense" ? "Разход"
      : ce.direction === "to_bank" ? "Внасяне в банката" : "Теглене от банката";
    const cat = ce.category === "Друго" && ce.category_other ? ce.category_other : ce.category;
    const { data: members } = await admin.from("church_members").select("user_id, role, permissions")
      .eq("church_id", ce.church_id).eq("status", "active");
    const holders = (members ?? []).filter((m) => m.role === "manager" || (m.permissions ?? []).includes("cash"));
    const cashier = (members ?? []).find((m) => m.role !== "manager" && (m.permissions ?? []).includes("cash"));
    if (type === "cash_pending") {
      if (ce.created_by !== caller.id || ce.status !== "pending") return json(403, { error: "forbidden" });
      const creatorHolder = holders.some((m) => m.user_id === caller.id);
      if (ce.book === "income" && !ce.reverses && !creatorHolder) {
        recipients = cashier ? [cashier.user_id] : holders.map((m) => m.user_id);
      } else {
        recipients = holders.map((m) => m.user_id);
      }
      title = `Каса: ${what.toLowerCase()} чака одобрение`;
      text = `${eur} · ${cat} · ${callerName}`;
    } else {
      if (ce.decided_by !== caller.id) return json(403, { error: "forbidden" });
      recipients = [ce.created_by];
      const ok = ce.status === "approved";
      title = ok ? `Каса: ${what.toLowerCase()} е ${ce.book === "income" && !ce.reverses ? "приет" : "одобрен"}`
        : `Каса: ${what.toLowerCase()} е върнат`;
      text = `${eur} · ${cat}${ok ? "" : ce.return_reason ? " · " + ce.return_reason : ""} · ${callerName}`;
    }
    data = { type: "cash", church_id: ce.church_id, entry_id: ce.id };
  } else if (type === "church_event" || type === "event_confirmed") {
    // Архиерейска Литургия: при записване – до всички свещеници в храма;
    // при потвърждение – до записалия.
    const eventId = String(body.event_id ?? "");
    const { data: ev } = await admin.from("events").select("*").eq("id", eventId).maybeSingle();
    if (!ev || ev.kind !== "arhiereyska") return json(404, { error: "not_found" });
    const when = new Date(ev.starts_at).toLocaleString("bg-BG", {
      timeZone: "Europe/Sofia", weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit",
    });
    if (type === "church_event") {
      if (ev.owner_id !== caller.id) return json(403, { error: "forbidden" });
      const { data: members } = await admin.from("church_members").select("user_id")
        .eq("church_id", ev.church_id).eq("status", "active");
      recipients = (members ?? []).map((m) => m.user_id);
      title = "Архиерейска Литургия – моля, потвърдете";
      text = `${when}${callerName ? " · записа " + callerName : ""}`;
    } else {
      const { data: conf } = await admin.from("event_confirmations").select("user_id")
        .eq("event_id", ev.id).eq("user_id", caller.id).maybeSingle();
      if (!conf) return json(403, { error: "forbidden" });
      recipients = [ev.owner_id];
      title = "Потвърдено участие";
      text = `${callerName} · Архиерейска Литургия · ${when}`;
    }
    data = { type: "event", event_id: ev.id, church_id: ev.church_id };
  } else if (type === "assignment_accepted" || type === "assignment_declined" || type === "assignment_kept") {
    const eventId = String(body.event_id ?? "");
    const { data: ev } = await admin.from("events").select("*").eq("id", eventId).maybeSingle();
    if (!ev) return json(404, { error: "not_found" });
    const kind = KIND[ev.kind] ?? "Събитие";
    const when = new Date(ev.starts_at).toLocaleString("bg-BG", {
      timeZone: "Europe/Sofia", weekday: "long", day: "numeric", month: "long", hour: "2-digit", minute: "2-digit",
    });
    if (type === "assignment_accepted") {
      if (ev.assignee_id !== caller.id || ev.assignment_status !== "accepted") return json(403, { error: "forbidden" });
      recipients = [ev.owner_id];
      title = `${callerName} прие: ${kind}`;
      text = [when, ev.for_whom].filter(Boolean).join(" · ");
    } else if (type === "assignment_declined") {
      if (ev.declined_by !== caller.id || ev.assignment_status !== "declined") return json(403, { error: "forbidden" });
      const { data: managers } = await admin.from("church_members").select("user_id")
        .eq("church_id", ev.church_id).eq("role", "manager").eq("status", "active");
      recipients = [...(managers ?? []).map((m) => m.user_id), ev.owner_id];
      let sub = "";
      if (ev.proposed_substitute) {
        const { data: sp } = await admin.from("profiles").select("full_name, rank").eq("id", ev.proposed_substitute).maybeSingle();
        if (sp?.full_name) sub = ` · предлага ${withRank(sp.rank, sp.full_name)}`;
      }
      title = `${callerName} отказа: ${kind}`;
      text = [when, ev.decline_reason].filter(Boolean).join(" · ") + sub;
    } else {
      // председателят остави събитието на отказалия
      const { data: me } = await admin.from("church_members").select("role,status")
        .eq("church_id", ev.church_id).eq("user_id", caller.id).maybeSingle();
      if (!me || me.role !== "manager" || me.status !== "active") return json(403, { error: "forbidden" });
      recipients = [ev.assignee_id];
      title = `Председателят ви остави: ${kind}`;
      text = [when, ev.for_whom].filter(Boolean).join(" · ");
    }
    data = { type, event_id: ev.id, church_id: ev.church_id };
  } else {
    // Събитие, записано от колега.
    const eventId = String(body.event_id ?? "");
    const change = body.change === "updated" ? "updated" : "created";
    const { data: ev } = await admin.from("events").select("*").eq("id", eventId).maybeSingle();
    if (!ev) return json(404, { error: "not_found" });
    // Уведомява записалият, или председателят след прехвърляне; на себе си не пращаме.
    let allowed = ev.owner_id === caller.id;
    if (!allowed) {
      const { data: me } = await admin.from("church_members").select("role,status")
        .eq("church_id", ev.church_id).eq("user_id", caller.id).maybeSingle();
      allowed = !!me && me.role === "manager" && me.status === "active";
    }
    if (!allowed) return json(403, { error: "forbidden" });
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
    title = ev.assignment_status === "pending"
      ? `Моля, потвърдете: ${kind}`
      : change === "updated" ? `Промяна: ${kind}` : `Ново събитие за вас: ${kind}`;
    const parts = [when];
    if (ev.for_whom) parts.push(ev.for_whom);
    if (callerName) parts.push(`записа ${callerName}`);
    text = parts.join(" · ");
    recipients = [ev.assignee_id];
    data = { type: "event", event_id: ev.id, church_id: ev.church_id };
  }

  // Дневник без лични данни: вид, колко получатели, устройства и изпратени.
  const log = (o: Record<string, unknown>) => console.log("notify " + JSON.stringify({ type, ...o }));
  const before = recipients.length;
  recipients = recipients.filter((r) => r && r !== caller.id);
  if (recipients.length === 0) {
    log({ recipients: 0, self: before > 0 });
    return json(200, { sent: 0, reason: before > 0 ? "only_self" : "no_recipients" });
  }
  const { data: tokens } = await admin.from("device_tokens").select("token").in("user_id", recipients);
  if (!tokens || tokens.length === 0) {
    log({ recipients: recipients.length, devices: 0 });
    return json(200, { sent: 0, reason: "no_devices", recipients: recipients.length });
  }

  const access = await fcmAccessToken(sa);
  let sent = 0;
  let stale = 0; // стари/изтрити телефони – чистят се сами, не са грешка
  const fcmErrors: number[] = [];
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
        stale++;
      } else {
        fcmErrors.push(res.status);
        console.error("FCM", res.status, text.slice(0, 300));
      }
    }
  }
  log({ recipients: recipients.length, devices: tokens.length, sent, stale });
  return json(200, { sent, stale, recipients: recipients.length, devices: tokens.length, fcm_errors: fcmErrors });
}

// Всяко извикване оставя ред в notify_log: вид, код и кратък резултат
// (брой получатели/устройства/изпратени или грешка) – без лични данни.
// Чете се само от сървъра (Actions → „Дневник на известията“).
Deno.serve(async (req) => {
  let type = "?";
  try {
    type = String((await req.clone().json()).type ?? "event");
  } catch {
    // няма тяло
  }
  const res = await handle(req);
  try {
    const info = await res.clone().json();
    let secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    if (!secret) secret = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}").default ?? "";
    const admin = createClient(Deno.env.get("SUPABASE_URL")!, secret, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    await admin.from("notify_log").insert({ type, status: res.status, info });
  } catch (e) {
    console.error("notify_log", String(e).slice(0, 200));
  }
  return res;
});
