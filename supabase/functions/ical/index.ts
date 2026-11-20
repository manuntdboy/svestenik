// Календарът на Кайрос като iCal абонамент (Google Calendar, iPhone, Outlook).
// GET /functions/v1/ical?t=<личната тайна връзка>  – само четене.
import { createClient } from "npm:@supabase/supabase-js@2";

const KIND: Record<string, string> = {
  krashtene: "Кръщене", venchavka: "Венчавка", pogrebenie: "Погребение", panihida: "Панихида",
  vodosvet: "Водосвет", sluzhba: "Служба", arhiereyska: "Архиерейска Литургия", izpoved: "Изповед",
  maslosvet: "Маслосвет", kurban: "Курбан", drugo: "Събитие",
};
const RANK: Record<string, string> = {
  deacon: "Дякон", hierodeacon: "Йеродякон", protodeacon: "Протодякон", archdeacon: "Архидякон",
  priest: "Иерей", hieromonk: "Йеромонах", archpriest: "Протойерей", stavrophor: "Свещеноиконом",
  archimandrite: "Архимандрит", bishop: "Епископ", metropolitan: "Митрополит",
};

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;

const esc = (s: string) => s.replace(/\\/g, "\\\\").replace(/;/g, "\;").replace(/,/g, "\\,").replace(/\r?\n/g, "\\n");
const utc = (d: Date) => d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
const day = (s: string, plus = 0) => {
  const d = new Date(s + "T00:00:00Z");
  d.setUTCDate(d.getUTCDate() + plus);
  return d.toISOString().slice(0, 10).replace(/-/g, "");
};
const priest = (r: Row) => [r.rank && RANK[r.rank] ? RANK[r.rank] : "", r.priest ?? ""].join(" ").trim();

// Редове до 75 байта (изискване на формата).
function fold(line: string): string {
  const enc = new TextEncoder();
  if (enc.encode(line).length <= 75) return line;
  const out: string[] = [];
  let cur = "";
  for (const ch of line) {
    if (enc.encode(cur + ch).length > (out.length ? 74 : 75)) {
      out.push(cur);
      cur = "";
    }
    cur += ch;
  }
  out.push(cur);
  return out.join("\r\n ");
}

Deno.serve(async (req) => {
  const t = new URL(req.url).searchParams.get("t") ?? "";
  if (!/^[0-9a-f]{48}$/.test(t)) return new Response("Not found", { status: 404 });
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data, error } = await admin.rpc("calendar_feed_data", { p_token: t });
  if (error) return new Response("Error", { status: 500 });
  if (!data) return new Response("Not found", { status: 404 });

  const names = data.with_names === true;
  const stamp = utc(new Date());
  const L: string[] = [
    "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Kairos//BG", "CALSCALE:GREGORIAN", "METHOD:PUBLISH",
    "X-WR-CALNAME:Кайрос", "X-WR-TIMEZONE:Europe/Sofia",
    "REFRESH-INTERVAL;VALUE=DURATION:PT1H", "X-PUBLISHED-TTL:PT1H",
  ];
  for (const e of (data.events ?? []) as Row[]) {
    const start = new Date(e.starts_at);
    const end = new Date(start.getTime() + (e.minutes ?? 30) * 60000);
    let title = KIND[e.kind] ?? "Събитие";
    if (names && e.for_whom) title += " – " + e.for_whom;
    if (!e.mine && e.priest) title += " · " + priest(e);
    if (e.status === "done") title = "✓ " + title;
    const where = e.outside ? (e.address ?? "") : [e.church, e.church_address, e.settlement].filter(Boolean).join(", ");
    L.push("BEGIN:VEVENT", `UID:${e.id}@kairos`, `DTSTAMP:${stamp}`, `DTSTART:${utc(start)}`, `DTEND:${utc(end)}`,
      `SUMMARY:${esc(title)}`);
    if (where) L.push(`LOCATION:${esc(where)}`);
    L.push(`DESCRIPTION:${esc(e.church ? "Кайрос · " + e.church : "Кайрос")}`, "END:VEVENT");
  }
  for (const d of (data.duties ?? []) as Row[]) {
    const title = d.mine ? "Дежурен" : "Дежурен: " + priest(d);
    L.push("BEGIN:VEVENT", `UID:duty-${d.id}@kairos`, `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${day(d.start)}`, `DTEND;VALUE=DATE:${day(d.end, 1)}`,
      `SUMMARY:${esc(title)}`, `DESCRIPTION:${esc("Кайрос · " + (d.church ?? ""))}`, "TRANSP:TRANSPARENT", "END:VEVENT");
  }
  for (const l of (data.leaves ?? []) as Row[]) {
    L.push("BEGIN:VEVENT", `UID:leave-${l.id}@kairos`, `DTSTAMP:${stamp}`,
      `DTSTART;VALUE=DATE:${day(l.start)}`, `DTEND;VALUE=DATE:${day(l.end, 1)}`,
      "SUMMARY:Почивка", `DESCRIPTION:${esc("Кайрос · " + (l.church ?? ""))}`, "TRANSP:TRANSPARENT", "END:VEVENT");
  }
  L.push("END:VCALENDAR");
  return new Response(L.map(fold).join("\r\n") + "\r\n", {
    headers: {
      "Content-Type": "text/calendar; charset=utf-8",
      "Content-Disposition": 'inline; filename="kairos.ics"',
      "Cache-Control": "no-store",
    },
  });
});
