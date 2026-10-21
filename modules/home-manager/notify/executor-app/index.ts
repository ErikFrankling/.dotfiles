// Executor app `notify`: push notifications to Erik's phone. Delivered as a
// Discord message in his private server "Agents" (the Discord app is already
// on his phone) and mirrored to the self-hosted ntfy (homelab repo,
// docs/notifications.md), the backbone for a native T3 app channel. Source of truth:
// ~/.dotfiles/modules/home-manager/notify/executor-app; deploy with ../deploy.sh.
// Same limits as the `notify-erik` CLI on the PCs.
import {
  array,
  bearer,
  boolean,
  decodeJson,
  defineApp,
  defineProvider,
  mutation,
  type MutationContext,
  object,
  plain,
  query,
  type QueryContext,
  router,
  secrets,
  string,
} from "apps";

const SERVER = "https://ntfy.erikfrankling.duckdns.org";
const TOPIC = "erik";
// Erik's PC; agents on another machine pass their own environmentId.
const PC_ENVIRONMENT = "638dd505-c97b-41e7-b7a7-7d91b3b9fd67";
// Erik's phone runs the fork's "preview" build (com.t3tools.t3code.preview),
// which registers only this scheme.
const APP_SCHEME = "t3code-preview";
// Discord only links http(s): a tap opens the thread in T3 web.
const T3_WEB = "https://t3code.erikfrankling.duckdns.org";

const ntfy = defineProvider({
  name: "ntfy",
  hosts: ["ntfy.erikfrankling.duckdns.org"],
  auth: {
    token: secrets({
      label: "ntfy access token (write-only on topic erik)",
      fields: object({ token: string({ minLength: 1 }) }),
      request: ({ token }) => bearer(token),
    }),
  },
  async health({ account, fetch, signal }) {
    const response = await fetch(`${SERVER}/v1/account`, {
      signal,
      headers: account.headers(),
    });
    const me = await decodeJson(response, object({ username: string() }));
    if (me.username === "*") throw new Error("ntfy did not accept this token.");
    return { accountInfo: { username: me.username } };
  },
});

// What reaches Erik's phone today: a webhook into #notifications of his
// private Discord server "Agents". The Discord app on his phone pushes it.
const discord = defineProvider({
  name: "Discord webhook",
  hosts: ["discord.com"],
  auth: {
    webhook: secrets({
      label: "Discord webhook (Agents server, #notifications)",
      fields: object({
        webhookId: plain(string({ minLength: 1 })),
        webhookToken: string({ minLength: 1 }),
        mentionUserId: plain(string({ minLength: 1 })),
      }),
    }),
  },
  async health({ account, fetch, signal }) {
    const response = await fetch(
      `https://discord.com/api/webhooks/${account.fields.webhookId}/${account.fields.webhookToken}`,
      { signal, headers: { "user-agent": "executor-notify (homelab, 1.0)" } },
    );
    const hook = await decodeJson(response, object({ id: string(), name: string() }));
    return { accountInfo: { externalId: hook.id, displayName: hook.name } };
  },
});

const requirements = { app: { accounts: { ntfy, discord } } };
type MContext = MutationContext<typeof requirements>;
type QContext = QueryContext<typeof requirements>;

type Class = "urgent" | "high" | "normal" | "low" | "code";
const PRIORITY: Record<Class, number> = { urgent: 5, high: 4, normal: 3, low: 2, code: 4 };

const HOUR = 3_600_000;
const DAY = 24 * HOUR;
const REPEAT_WINDOW = 15 * 60_000;

// [window, max, which sends count, what to say]
const LIMITS: Array<[Class | "code" | "any", number, number, string]> = [
  ["urgent", HOUR, 4, "4 urgent notifications in the last hour"],
  ["code", 10 * 60_000, 6, "6 codes in the last 10 minutes"],
  ["code", DAY, 30, "30 codes in the last 24 hours"],
  ["any", HOUR, 12, "12 notifications in the last hour"],
  ["any", DAY, 40, "40 notifications in the last 24 hours"],
];

async function sha(text: string): Promise<string> {
  const bytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(bytes)]
    .slice(0, 8)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

type Links = { app?: string; web?: string };

function threadLinks(threadId?: string, environmentId?: string, link?: string): Links {
  if (!threadId) return { app: link, web: link };
  const path = `${encodeURIComponent(environmentId ?? PC_ENVIRONMENT)}/${encodeURIComponent(threadId)}`;
  return { app: `${APP_SCHEME}://threads/${path}`, web: `${T3_WEB}/${path}` };
}

type Outcome =
  | { sent: true; id: string; messageId: string | null }
  | { sent: false; reason: string; advice: string };

async function deliver(
  ctx: MContext,
  input: {
    class: Class;
    title: string;
    message: string;
    source: string;
    links: Links;
    tags: string[];
    markdown: boolean;
    code?: string;
  },
): Promise<Outcome> {
  const now = Date.now();
  const digest = await sha(`${input.title}\n${input.message}`);
  const id = crypto.randomUUID();

  // Check the limits and reserve a row in one transaction, so two agents
  // sending at once cannot both slip under a limit.
  const refusal = ctx.sql.transaction(() => {
    const repeat = ctx.sql
      .exec<{ n: number }>(
        "SELECT COUNT(*) AS n FROM sends WHERE digest = ? AND created_at >= ? AND status != 'failed'",
        digest,
        now - REPEAT_WINDOW,
      )
      .one().n;
    if (repeat > 0) return "the same notification was sent in the last 15 minutes";
    for (const [cls, window, max, why] of LIMITS) {
      if (cls === "any" ? input.class === "code" : cls !== input.class) continue;
      const n = ctx.sql
        .exec<{ n: number }>(
          cls === "any"
            ? "SELECT COUNT(*) AS n FROM sends WHERE created_at >= ? AND status != 'failed' AND class != 'code'"
            : "SELECT COUNT(*) AS n FROM sends WHERE created_at >= ? AND status != 'failed' AND class = ?",
          ...(cls === "any" ? [now - window] : [now - window, cls]),
        )
        .one().n;
      if (n >= max) return why;
    }
    ctx.sql.exec(
      "INSERT INTO sends (id, created_at, class, digest, title, source, status) VALUES (?, ?, ?, ?, ?, ?, 'sending')",
      id,
      now,
      input.class,
      digest,
      input.title,
      input.source,
    );
    ctx.sql.exec("DELETE FROM sends WHERE created_at < ?", now - 30 * DAY);
    return null;
  });
  if (refusal) {
    return {
      sent: false,
      reason: refusal,
      advice: "Not sent. Do not retry; put it in your final report instead.",
    };
  }

  const body = {
    topic: TOPIC,
    title: input.title,
    message: input.message,
    priority: PRIORITY[input.class],
    tags: [...input.tags, ...(input.source ? [input.source] : [])].slice(0, 6),
    markdown: input.markdown,
    ...(input.links.app ? { click: input.links.app } : {}),
    ...(input.code
      ? { actions: [{ action: "copy", label: "Copy code", value: input.code, clear: false }] }
      : {}),
  };
  // Discord: urgent, high and codes also @mention Erik; low is sent silently.
  const hook = ctx.app.accounts.discord.fields;
  const ping = ["urgent", "high", "code"].includes(input.class);
  const icon = { urgent: "🚨 ", high: "❗ ", normal: "", low: "", code: "🔑 " }[input.class];
  const content =
    `${ping ? `<@${hook.mentionUserId}> ` : ""}${icon}**${input.title}**\n${input.message}` +
    (input.code ? `\n\`\`\`\n${input.code}\n\`\`\`` : "") +
    (input.links.web ? `\n[Open thread](${input.links.web})` : "") +
    (input.source ? `\n-# from ${input.source}` : "");
  let messageId: string;
  try {
    const response = await ctx.fetch(
      `https://discord.com/api/webhooks/${hook.webhookId}/${hook.webhookToken}?wait=true`,
      {
        method: "POST",
        signal: ctx.signal,
        headers: { "content-type": "application/json", "user-agent": "executor-notify (homelab, 1.0)" },
        body: JSON.stringify({
          username: "Agents",
          content,
          allowed_mentions: { users: ping ? [hook.mentionUserId] : [] },
          // 4: no link previews; 4096: silent (low priority)
          flags: 4 + (input.class === "low" ? 4096 : 0),
        }),
      },
    );
    messageId = (await decodeJson(response, object({ id: string() }))).id;
    ctx.sql.exec("UPDATE sends SET status = 'sent', message_id = ? WHERE id = ?", messageId, id);
  } catch (error) {
    ctx.sql.exec("UPDATE sends SET status = 'failed' WHERE id = ?", id);
    throw error;
  }

  // ntfy: best effort, it does not change the outcome.
  await ctx
    .fetch(`${SERVER}/`, {
      method: "POST",
      signal: ctx.signal,
      headers: { ...ctx.app.accounts.ntfy.headers(), "content-type": "application/json" },
      body: JSON.stringify(body),
    })
    .catch(() => undefined);
  return { sent: true, id, messageId };
}

const PRIORITIES = ["urgent", "high", "normal", "low"] as const;
type PriorityName = (typeof PRIORITIES)[number];

function checkLength(field: string, value: string | undefined, max: number): void {
  if (value !== undefined && value.length > max) {
    throw new Error(`${field} is longer than ${max} characters; shorten it.`);
  }
}

const send = mutation(
  {
    description:
      "Send a push notification to Erik's phone. Only for things he needs to know or act on now: " +
      "something broke that you cannot fix, you are blocked on his decision, a long task he is " +
      "waiting for finished. Rate limited; a refusal means do not retry.",
    input: object({
      message: string({ minLength: 1 }),
      title: string().optional(),
      priority: string().default("normal"),
      threadId: string().optional(),
      environmentId: string().optional(),
      link: string().optional(),
      tags: array(string()).default([]),
      markdown: boolean().default(false),
      source: string().default(""),
      test: boolean().default(false),
    }),
  },
  async (ctx: MContext, input) => {
    if (!(PRIORITIES as readonly string[]).includes(input.priority)) {
      throw new Error("priority must be urgent, high, normal or low.");
    }
    checkLength("title", input.title, 120);
    checkLength("message", input.message, 3000);
    checkLength("source", input.source, 40);
    const title = input.title ?? "Agent";
    return deliver(ctx, {
      class: input.priority as PriorityName,
      title: input.test ? `[TEST] ${title}` : title,
      message: input.message,
      source: input.source,
      links: threadLinks(input.threadId, input.environmentId, input.link),
      tags: [...input.tags],
      markdown: input.markdown,
    });
  },
);

const sendCode = mutation(
  {
    description:
      "Send a one-time code (MFA, verification, pairing) to Erik's phone so it pops up at the top " +
      "of his screen with a Copy button while he is on the entry screen. Own budget, separate from " +
      "send. Never send passwords or long-lived secrets this way.",
    input: object({
      code: string({ minLength: 1 }),
      service: string().optional(),
      message: string().optional(),
      threadId: string().optional(),
      environmentId: string().optional(),
      source: string().default(""),
      test: boolean().default(false),
    }),
  },
  async (ctx: MContext, input) => {
    checkLength("code", input.code, 64);
    checkLength("service", input.service, 60);
    checkLength("message", input.message, 500);
    checkLength("source", input.source, 40);
    const title = input.service ? `${input.service} code: ${input.code}` : `Code: ${input.code}`;
    return deliver(ctx, {
      class: "code",
      title: input.test ? `[TEST] ${title}` : title,
      message: input.message ?? `One-time code ${input.code} (tap Copy code)`,
      source: input.source,
      links: threadLinks(input.threadId, input.environmentId),
      tags: ["key"],
      markdown: false,
      code: input.code,
    });
  },
);

const status = query(
  {
    description: "How many notifications were sent recently and the remaining budget.",
    input: object({}),
  },
  async (ctx: QContext) => {
    const now = Date.now();
    const count = (sinceMs: number, codes: boolean) =>
      ctx.sql
        .exec<{ n: number }>(
          `SELECT COUNT(*) AS n FROM sends WHERE created_at >= ? AND status != 'failed' AND class ${codes ? "=" : "!="} 'code'`,
          now - sinceMs,
        )
        .one().n;
    const recent = ctx.sql
      .exec<{ created_at: number; class: string; title: string; source: string; status: string }>(
        "SELECT created_at, class, title, source, status FROM sends ORDER BY created_at DESC LIMIT 10",
      )
      .toArray()
      .map((r) => ({ ...r, at: new Date(r.created_at).toISOString() }));
    return {
      lastHour: `${count(HOUR, false)}/12`,
      last24h: `${count(DAY, false)}/40`,
      codesLast10min: `${count(10 * 60_000, true)}/6`,
      recent,
    };
  },
);

const instructions = `Push notifications to Erik's phone: a message in his private Discord server "Agents"
(the Discord app pushes it; "Open thread" opens your T3 thread).

Use send only when Erik must know or act soon:
- urgent: something important is broken and you cannot fix it, security issue, data at risk.
- high: you are blocked on his decision or login and the task stalls without him.
- normal: a long task he asked to hear about finished, or a result he is waiting for.
- low: FYI that can wait until he next looks.
Never for progress updates, routine success, or anything already in your final report.
One notification per event; batch related news into one.

Use sendCode for one-time codes (MFA, verification, device pairing) he must type somewhere;
it pops up with a Copy button. Never send passwords or long-lived secrets.

Always pass threadId (t3_thread_list returns currentThreadId) so tapping opens your thread,
and environmentId when you are not on the PC (t3_environment_read). Set source to a short
name of what you are (e.g. "systems-check"). Use test: true for tests.
A result with sent: false hit a limit: do not retry; mention it in your report.
Shell scripts and agents without Executor: the notify-erik CLI (same limits).`;

export default defineApp(requirements, {
  tools: router(
    { send, sendCode, status },
    {
      title: "Notify Erik",
      description: "Push notifications and one-time codes to Erik's phone.",
      instructions,
    },
  ),
});
