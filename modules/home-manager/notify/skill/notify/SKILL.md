---
name: notify
description: Send Erik a push notification on his phone (a native notification in his T3 Code app; tapping it opens your thread), or a one-time code (MFA, verification, pairing) he must type in. Load when you need his attention urgently, are blocked on his decision or login, finished something long he asked to hear about, or have a code he must type in. Any agent on Erik's machines can do this, the personal agent included.
---

# Notify Erik on his phone

**Never contact other people.** Never send, post, reply, react, comment, invite, share or connect with anyone else on Erik's behalf (Discord, LinkedIn, X, email, Teams, SMS, GitHub comments, connect invites, shared docs), unless Erik approved that exact message in this conversation. Drafts for Erik to send himself are fine. Notifications to Erik himself are fine.

A notification is a **native notification in Erik's T3 Code app** (the
fork's preview build). The T3 server on his PC sends it through Firebase Cloud
Messaging. It arrives with the app closed and off the tailnet, and tapping it
opens the thread you link, straight into the app. Codes get a **Copy code**
button. Erik set nothing up.

**Fallback: Discord.** Every send is also posted to #notifications of his
private Discord server "Agents". The copy is silent when the native push went
out, and pings him as before when it did not (the PC or T3 is down, or no
device is registered). Every send is also mirrored to the self-hosted ntfy
(homelab repo `docs/notifications.md`). Discord holds back phone pushes
while Erik's account is active in a desktop or web client, so **never leave
Discord open in the agent browser**.

One gap: if Erik **force-stops** the T3 app in Android settings, Android
holds its pushes until he opens it again. Google still accepts them, so the
Discord copy is silent too. Swiping the app away from recents is fine.

## How to send

**From any agent with Executor (preferred):**

```js
// threadId: from t3_thread_list (currentThreadId); environmentId only off the PC
await tools.notify.send({
  title: "Nightly update blocked",            // short; shows in bold
  message: "nix flake update broke hyprland; needs your call on pinning.",
  priority: "high",                           // urgent | high | normal | low
  threadId: "<your thread id>",
  source: "nix-nightly",                      // short name of what you are
});

await tools.notify.sendCode({ code: "482913", service: "GitHub", threadId: "<your thread id>" });
await tools.notify.status({});                // budget and recent sends
```

**From a shell, script, scheduled task or systemd unit (PC and framework):**

```sh
notify-erik -p high -t "Nightly update blocked" --thread "$THREAD_ID" "nix flake update broke hyprland"
notify-erik --code 482913 -t "GitHub code: 482913"
notify-erik status
```

`notify-erik --help` lists every option (`--link URL`, `--tags`, `--markdown`,
`--test`, `--dry-run`). It fills in this machine's T3 environment itself.

**From a pod in the homelab:** send through Executor's `notify` app.
(ntfy, `docs/notifications.md` in the homelab repo, does not reach the phone
on its own.)

## When to send (and when not)

| priority | in the T3 app (Android channel)            | use for |
| -------- | ------------------------------------------ | ------- |
| urgent   | heads-up with sound ("Urgent")             | something important broke and you cannot fix it; security; data at risk |
| high     | heads-up with sound ("Needs you")          | you are blocked on Erik (decision, login, approval) and the work stalls |
| normal   | sound, no heads-up ("Updates")             | a long task he asked to hear about finished; a reminder; a result he is waiting for |
| low      | silent, in the shade only ("FYI")          | FYI that can wait until he looks |
| code     | heads-up, Copy code button, expires 10 min | one-time codes he must type somewhere, right now |

Erik can tune each channel in Android's notification settings for the app.

- **Never** for progress updates, routine success, or anything that is
  already in your final report. One notification per event; batch related
  news into one message.
- Lead with what he must do, then why. He reads it on a lock screen.
- **Always link your thread** (`threadId` / `--thread`) so a tap opens it.
- **Codes:** only short-lived codes. Never passwords, tokens or recovery
  codes. When a login sends a code to Erik's email and you need him to type
  it on his phone or another device, send it with `sendCode`. To read
  that code from his personal Gmail, use the Executor `gmail` tools
  (`searchThreads`, `getThread`) before any browser or Thunderbird. When you need
  a code *from* him, ask in your thread and send a `high` notification that
  links it.
- Tests: `test: true` / `--test` prefixes the title with `[TEST]`.

## Limits

Agents share these budgets (Executor app and CLI each enforce them; the CLI
per machine):

- urgent: 4 per hour
- everything except codes: 12 per hour, 40 per day
- codes: 6 per 10 minutes, 30 per day (separate budget; he is waiting for them)
- the same title and message again within 15 minutes is dropped

A refusal (`sent: false`, or CLI exit code 3) means **do not retry**: put
the message in your final report instead.

## Where things are

- Native push: fork `ErikFrankling/t3code`. The server side is
  `apps/server/src/erikPush.ts` (`POST /api/push/devices` where the app
  registers its FCM token, `POST /api/push/send` for senders, devices in
  `~/.t3/userdata/push-devices.json`). The app side is
  `apps/mobile/src/features/agent-awareness/erikPushRegistration.ts` and
  `ErikNotifications.kt`. Firebase project `t3code-erik-push` on
  ef.pro454@gmail.com. Service-account key: sops `secrets/notify.yaml`
  `t3code-fcm-service-account`, on the PC at
  `/run/secrets/t3code-fcm-service-account` (t3code service env
  `T3CODE_FCM_SERVICE_ACCOUNT_FILE`). google-services.json: the same sops
  file and the fork's GitHub secret `T3CODE_ANDROID_GOOGLE_SERVICES_JSON`.
  Check: `jq length ~/.t3/userdata/push-devices.json` on the PC (1 means the phone is registered).

- Executor app `notify`: source in
  `~/.dotfiles/modules/home-manager/notify/executor-app`, deploy with
  `../deploy.sh`. Accounts: Discord webhook, ntfy token `executor`. It
  reaches the T3 server at `http://192.168.50.232:3773`.
- CLI: `~/.dotfiles/modules/nixos/notify/` (Discord webhook, Erik's Discord
  user id and the ntfy token in `secrets/notify.yaml`, sops).
- Discord: server "Agents" (id 1562316035896512532), channel #notifications,
  webhook "Agents" (Alertmanager posts to the same webhook). The agent
  browser is **not** logged in to Discord, and no agent needs to be: to check
  a post, read it back through the webhook with the id `notify-erik` prints
  (Executor: `messageId`):
  `curl "$(cat /run/secrets/discord-webhook-url)/messages/<id>"`. Never copy
  Erik's Discord token from another browser: Discord revoked the copied
  session on 2026-10-21.
- ntfy server: homelab repo `kubernetes/homelab/apps/ntfy.yaml`, Gatus check
  `phone/ntfy`.
