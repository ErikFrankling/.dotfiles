---
name: notify
description: Send Erik a push notification on his phone (it arrives through the Discord app he already has), or a one-time code (MFA, verification, pairing) he must type in. Load when you need his attention urgently, are blocked on his decision or login, finished something long he asked to hear about, or have a code he must type in. Any agent on Erik's machines can do this, the personal agent included.
---

# Notify Erik on his phone

A notification is a message from "Agents" in #notifications of Erik's private
Discord server "Agents". The Discord app on his phone pushes it like any
message, with every app closed and off the tailnet; Erik set nothing up.
"Open thread" in the message opens the T3 thread you link (in T3 web for now).
Every send is mirrored to the self-hosted ntfy (homelab repo
`docs/notifications.md`), the backbone for a native T3 app channel.

Discord holds back phone pushes while Erik's account is active in a desktop
or web client. **Never leave Discord open in the agent browser**: close the
tab when done, or his phone stops buzzing.

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

**From a pod in the homelab:** plain HTTP to ntfy with the service's own token;
see `docs/notifications.md` in the homelab repo. (ntfy alone does not reach
the phone yet; send through Executor's `notify` app if Erik must see it.)

## When to send (and when not)

| priority | on the phone                       | use for |
| -------- | ---------------------------------- | ------- |
| urgent   | push, @mention, 🚨                 | something important broke and you cannot fix it; security; data at risk |
| high     | push, @mention, ❗                 | you are blocked on Erik (decision, login, approval) and the work stalls |
| normal   | push                               | a long task he asked to hear about finished; a reminder; a result he is waiting for |
| low      | silent message, no push            | FYI that can wait until he looks |
| code     | push, @mention, code in the text   | one-time codes he must type somewhere, right now |

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

- Executor app `notify`: source in
  `~/.dotfiles/modules/home-manager/notify/executor-app`, deploy with
  `../deploy.sh`. Accounts: Discord webhook, ntfy token `executor`.
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
