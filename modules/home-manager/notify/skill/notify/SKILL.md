---
name: notify
description: Send Erik a push notification on his phone, or a one-time code (MFA, verification, pairing) that pops up with a Copy button. Load when you need his attention urgently, are blocked on his decision or login, finished something long he asked to hear about, or have a code he must type in. Any agent on Erik's machines can do this, the personal agent included.
---

# Notify Erik on his phone

Erik's phone runs the ntfy app, subscribed to his self-hosted ntfy server
(homelab repo `docs/notifications.md`). Messages arrive within a second, also
when every app is closed, as long as the phone is on Tailscale (it always is).
Tapping a notification opens the T3 thread you link.

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

**From a shell, script or systemd unit (PC and framework):**

```sh
notify-erik -p high -t "Nightly update blocked" --thread "$THREAD_ID" "nix flake update broke hyprland"
notify-erik --code 482913 -t "GitHub code: 482913"
notify-erik status
```

`notify-erik --help` lists every option (`--link URL`, `--tags`, `--markdown`,
`--test`, `--dry-run`). It fills in this machine's T3 environment itself.

**From a pod in the homelab:** plain HTTP to ntfy with the service's own token;
see `docs/notifications.md` in the homelab repo.

## When to send (and when not)

| priority | on the phone                        | use for |
| -------- | ----------------------------------- | ------- |
| urgent   | pops up, long vibration             | something important broke and you cannot fix it; security; data at risk |
| high     | pops up, sound                      | you are blocked on Erik (decision, login, approval) and the work stalls |
| normal   | sound, in the shade                 | a long task he asked to hear about finished; a result he is waiting for |
| low      | silent                              | FYI that can wait until he looks |
| code     | pops up with **Copy code** button   | one-time codes he must type somewhere, right now |

- **Never** for progress updates, routine success, or anything that is
  already in your final report. One notification per event; batch related
  news into one message.
- Lead with what he must do, then why. He reads it on a lock screen.
- **Always link your thread** (`threadId` / `--thread`) so a tap opens it.
- **Codes:** only short-lived codes. Never passwords, tokens or recovery
  codes. When a login sends a code to Erik's email and you need him to type
  it on his phone or another device, send it with `sendCode`. When you need
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
  `./deploy.sh` there. Account: ntfy token `executor`.
- CLI: `~/.dotfiles/modules/nixos/notify/` (token in `secrets/notify.yaml`,
  sops).
- Server: homelab repo `kubernetes/homelab/apps/ntfy.yaml`, Gatus check
  `phone/ntfy`.
