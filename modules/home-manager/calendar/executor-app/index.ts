import {
  array,
  boolean,
  decodeJson,
  defineApp,
  defineProvider,
  json,
  number,
  oauth2,
  object,
  query,
  record,
  router,
  string,
  type QueryContext,
} from "apps";

// Erik's Google Calendar, read-only (scope calendar.readonly: Google gives
// this scope no way to create, change, accept or decline anything).
const provider = defineProvider({
  name: "Google Calendar",
  hosts: ["www.googleapis.com"],
  auth: {
    oauth: oauth2({
      discover: "https://accounts.google.com",
      scopes: ["https://www.googleapis.com/auth/calendar.readonly"],
      authorizationParams: { access_type: "offline", prompt: "consent" },
    }),
  },
  async health({ account, fetch, signal }) {
    const response = await fetch(
      "https://www.googleapis.com/calendar/v3/users/me/calendarList/primary",
      {
        signal,
        headers: { Authorization: "Bearer " + account.fields.access_token },
      },
    );
    const me = await decodeJson(response, object({ id: string() }));
    return { accountInfo: { externalId: me.id, email: me.id } };
  },
});

const requirements = { user: { accounts: { calendar: provider } } };
type QCtx = QueryContext<typeof requirements>;

const API = "https://www.googleapis.com/calendar/v3";
const TZ = "Europe/Stockholm";
const NL = String.fromCharCode(10);
const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

async function gcal(
  ctx: any,
  path: string,
  params: [string, string][] = [],
): Promise<any> {
  const qs = params.length
    ? "?" +
      params
        .map(([k, v]) => encodeURIComponent(k) + "=" + encodeURIComponent(v))
        .join("&")
    : "";
  const response = await ctx.fetch(API + path + qs, {
    headers: {
      Authorization: "Bearer " + ctx.user.accounts.calendar.fields.access_token,
      "user-agent": "executor-calendar",
    },
    signal: ctx.signal,
  });
  return await decodeJson(response, record(json()));
}

// Europe/Stockholm offset (minutes) at a UTC instant: EU rule, DST from the
// last Sunday of March 01:00 UTC to the last Sunday of October 01:00 UTC.
function lastSundayUtc(year: number, month: number): number {
  const d = new Date(Date.UTC(year, month + 1, 0, 1, 0, 0));
  d.setUTCDate(d.getUTCDate() - d.getUTCDay());
  return d.getTime();
}
function stockholmOffsetMinutes(utcMs: number): number {
  const y = new Date(utcMs).getUTCFullYear();
  return utcMs >= lastSundayUtc(y, 2) && utcMs < lastSundayUtc(y, 9) ? 120 : 60;
}
function pad(n: number): string {
  return (n < 10 ? "0" : "") + n;
}
function stockholmParts(utcMs: number) {
  const d = new Date(utcMs + stockholmOffsetMinutes(utcMs) * 60000);
  return {
    date: d.getUTCFullYear() + "-" + pad(d.getUTCMonth() + 1) + "-" + pad(d.getUTCDate()),
    time: pad(d.getUTCHours()) + ":" + pad(d.getUTCMinutes()),
    weekday: DAYS[d.getUTCDay()],
  };
}
// Local midnight (Stockholm) of YYYY-MM-DD as a UTC instant.
function localMidnightUtc(date: string): number {
  const [y, m, d] = date.split("-").map(Number);
  const guess = Date.UTC(y, m - 1, d, 0, 0, 0);
  const off = stockholmOffsetMinutes(guess - 2 * 3600000);
  const first = guess - off * 60000;
  return first - (stockholmOffsetMinutes(first) - off) * 60000;
}

type Ev = {
  calendar: string;
  title: string;
  start: string;
  end: string;
  allDay: boolean;
  where: string | null;
  meetLink: string | null;
  link: string | null;
  organizer: string | null;
  attendees: { name: string | null; email: string; response: string | null }[];
  myResponse: string | null;
  description: string | null;
  status: string;
};

function toEvent(item: any, calendarName: string): Ev {
  const allDay = item.start?.date !== undefined;
  const attendees = (item.attendees ?? [])
    .filter((a: any) => !a.resource)
    .map((a: any) => ({
      name: a.displayName ?? null,
      email: String(a.email),
      response: a.responseStatus ?? null,
    }));
  const me = (item.attendees ?? []).find((a: any) => a.self);
  const desc = typeof item.description === "string" ? item.description : null;
  return {
    calendar: calendarName,
    title: String(item.summary ?? "(no title)"),
    start: String(item.start?.dateTime ?? item.start?.date),
    end: String(item.end?.dateTime ?? item.end?.date),
    allDay,
    where: item.location ?? null,
    meetLink:
      item.hangoutLink ??
      (item.conferenceData?.entryPoints ?? []).find((e: any) => e.uri)?.uri ??
      null,
    link: item.htmlLink ?? null,
    organizer: item.organizer?.email ?? null,
    attendees,
    myResponse: me?.responseStatus ?? null,
    description: desc ? desc.slice(0, 600) : null,
    status: String(item.status ?? "confirmed"),
  };
}

async function fetchRange(ctx: any, timeMin: number, timeMax: number): Promise<Ev[]> {
  const list = await gcal(ctx, "/users/me/calendarList", [["minAccessRole", "reader"]]);
  const cals = ((list.items as any[]) ?? []).filter(
    (c) => c.selected !== false && !c.hidden && c.accessRole !== "freeBusyReader",
  );
  const all = await Promise.all(
    cals.map(async (c) => {
      const r = await gcal(ctx, "/calendars/" + encodeURIComponent(c.id) + "/events", [
        ["timeMin", new Date(timeMin).toISOString()],
        ["timeMax", new Date(timeMax).toISOString()],
        ["singleEvents", "true"],
        ["orderBy", "startTime"],
        ["timeZone", TZ],
        ["maxResults", "100"],
      ]);
      const name = String(c.summaryOverride ?? c.summary ?? c.id);
      return ((r.items as any[]) ?? [])
        .filter((i) => i.status !== "cancelled")
        .map((i) => toEvent(i, name));
    }),
  );
  return all
    .flat()
    .sort((a, b) => a.start.localeCompare(b.start) || a.title.localeCompare(b.title));
}

function label(ev: Ev): string {
  if (ev.allDay) return "all day";
  return ev.start.substring(11, 16) + "-" + ev.end.substring(11, 16);
}

function block(events: Ev[]): string {
  if (events.length === 0) return "No events.";
  const lines: string[] = [];
  let day = "";
  for (const ev of events) {
    const d = ev.start.substring(0, 10);
    if (d !== day) {
      day = d;
      const wd = DAYS[new Date(d + "T12:00:00Z").getUTCDay()];
      lines.push(wd + " " + d);
    }
    const bits = [ev.title];
    if (ev.where) bits.push(ev.where);
    if (ev.meetLink) bits.push(ev.meetLink);
    const guests = ev.attendees.filter((a) => a.response !== "declined");
    if (guests.length > 1)
      bits.push("with " + guests.map((a) => a.name ?? a.email).slice(0, 6).join(", "));
    lines.push("  " + label(ev) + "  " + bits.join(" | "));
  }
  return lines.join(NL);
}

const EventOut = object({
  calendar: string(),
  title: string(),
  start: string(),
  end: string(),
  allDay: boolean(),
  where: json(),
  meetLink: json(),
  link: json(),
  organizer: json(),
  attendees: array(
    object({ name: json(), email: string(), response: json() }),
  ),
  myResponse: json(),
  description: json(),
  status: string(),
});

const Out = object({
  from: string(),
  to: string(),
  count: number(),
  text: string(),
  events: array(EventOut),
});

const upcoming = query(
  {
    description:
      "Erik's Google Calendar events from now until now+days (default 7, max 60), all his selected calendars, times in Europe/Stockholm. Read-only. `text` is a compact ready-to-read block; `events` has attendees, Meet link and calendar link.",
    input: object({ days: number().optional() }),
    output: Out,
  },
  async (ctx: QCtx, input) => {
    const days = Math.min(Math.max(input.days ?? 7, 0.1), 60);
    const now = Date.now();
    const events = await fetchRange(ctx, now, now + days * 86400000);
    const keep = events.filter((e) => e.allDay || new Date(e.end).getTime() > now);
    return {
      from: stockholmParts(now).date + " " + stockholmParts(now).time,
      to: stockholmParts(now + days * 86400000).date,
      count: keep.length,
      text: block(keep),
      events: keep,
    };
  },
);

const day = query(
  {
    description:
      "Erik's Google Calendar events on one local day (YYYY-MM-DD, Europe/Stockholm; default today). Read-only. `text` is a compact block; `events` has attendees, Meet link and calendar link.",
    input: object({ date: string().optional() }),
    output: Out,
  },
  async (ctx: QCtx, input) => {
    const date = input.date ?? stockholmParts(Date.now()).date;
    if (!/^[0-9]{4}-[0-9]{2}-[0-9]{2}$/.test(date))
      throw new Error("date must be YYYY-MM-DD.");
    const start = localMidnightUtc(date);
    const end = localMidnightUtc(
      stockholmParts(start + 36 * 3600000).date,
    );
    const events = await fetchRange(ctx, start, end);
    return { from: date, to: date, count: events.length, text: block(events), events };
  },
);

const calendars = query(
  {
    description: "List the calendars Erik's Google account shows (name, id, access role, selected).",
    input: object({}),
  },
  async (ctx: QCtx) => {
    const list = await gcal(ctx, "/users/me/calendarList");
    return {
      calendars: ((list.items as any[]) ?? []).map((c) => ({
        id: String(c.id),
        name: String(c.summaryOverride ?? c.summary ?? c.id),
        role: String(c.accessRole),
        selected: c.selected !== false,
        primary: c.primary === true,
      })),
    };
  },
);

const instructions = [
  "Erik's Google Calendar (ef.pro454@gmail.com), read-only: the app has the calendar.readonly scope and no tools that create, change, accept, decline or delete events. Never contact attendees.",
  "upcoming({days}) = from now; day({date}) = one local day. Times are Europe/Stockholm. `text` is the compact block to show; `events` carries attendees, the Meet link (meetLink) and the calendar link (link).",
  "On the PC, `calendar-next` prints the same plus the KTH/Canvas schedule.",
].join(NL);

export default defineApp(requirements, {
  tools: router(
    { upcoming, day, calendars },
    {
      title: "Google Calendar",
      description: "Read Erik's Google Calendar: upcoming events and a single day.",
      instructions,
    },
  ),
});
