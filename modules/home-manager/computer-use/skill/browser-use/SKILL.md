---
name: browser-use
description: Browser use on Erik's PC. Load whenever a task involves a website or web app: "browser use", "computer use" on a site, logging in to anything (GitHub, Gmail/Google, Microsoft/Teams/Outlook, Basecamp, cloud consoles, the apps Erik is building), testing/QA of a web UI, filling forms, downloading from a site. You drive the agent's own Chromium (logged in wherever Erik is in Firefox, plus LastPass) with the `browser` Playwright MCP.
---

# Browser use on Erik's PC

You have your own browser: **the agent Chromium**, a permanent Chromium running
on your monitor AGENT-1 (workspace `agent`), separate from Erik's Firefox.
**It is logged in wherever Erik is logged in in Firefox**: `agent-cookie-sync`
copies his Firefox cookies into it every 5 minutes. It also has **LastPass
installed and logged in to Erik's vault**. **You are allowed to use Erik's
accounts.** Don't ask permission to use them. But read "Logins" below before you
submit any login form: **a login must never set off a prompt on Erik's phone
unless you warned him first.**

Also read **computer-use** for the overall machine setup.

## Driving it: the `browser` MCP (Playwright)

The `browser` server is Microsoft's Playwright MCP, connected to the agent
Chromium over its DevTools port (127.0.0.1:9222). It works through the page's
DOM and accessibility tree: fast, exact, and it never touches Erik's input.

Core loop:

1. `browser_navigate` `{url}`: the response includes the page title/URL and a
   snapshot link.
2. `browser_snapshot`: the page as an accessibility tree where every element
   has a **ref** (e.g. `e42`). This is your main way to read the page.
   `browser_find` `{text}` searches it without dumping everything.
3. Act by ref: `browser_click` `{element:"Sign in button", target:"e42"}`,
   `browser_type` `{element, target, text, submit:true}`,
   `browser_fill_form` `{fields:[...]}`, `browser_select_option`,
   `browser_press_key` `{key:"Enter"}`, `browser_hover`, `browser_drag`.
   `element` is a short human description; `target` is the ref.
4. Check the result from the response/snapshot; wait for async UI with
   `browser_wait_for` `{text}` or `{textGone}` or `{time}`.

Also available: `browser_take_screenshot` (visual check; `fullPage:true` for the
whole page), `browser_tabs` (`list`/`new`/`select`/`close`),
`browser_navigate_back`, `browser_evaluate` (run JS), `browser_handle_dialog`,
`browser_file_upload`, `browser_console_messages`,
`browser_network_requests`/`browser_network_request` (debug web apps),
`browser_resize`. The vision tools (`browser_mouse_click_xy`,
`browser_mouse_move_xy`, `browser_mouse_drag_xy`) click viewport coordinates
from a screenshot: use them for canvas UIs and iframes the snapshot can't reach.

Refs go stale when the page changes: take a new snapshot after navigation or big
UI updates. Prefer refs over coordinates; screenshots are for checking visuals,
not for choosing what to click.

## Tabs and windows

- **Other agents use this browser at the same time.** Always open your own
  tab first (`browser_tabs` `{action:"new", url}`) and work only in tabs you
  opened; never navigate or close someone else's tab. Re-check the current
  tab with `browser_tabs` `{action:"list"}` if a result looks wrong: another
  agent may have switched it.
- The agent Chromium runs in the background with no window until you open a
  page. Your first page becomes one full-screen window on AGENT-1; open more
  pages as **tabs** (`browser_tabs` `{action:"new", url}`), switch with
  `{action:"select", index}`, close finished ones with `{action:"close"}`.
- Every `agent-chromium` window is forced onto AGENT-1 by a Hyprland rule, so
  nothing can open on Erik's monitors. Still, don't open extra windows.
- Erik's own browsers (Firefox, Helium, Chrome) and windows are off limits:
  never click, type in, move or capture them.
- Tabs **persist after your session** (it's a real browser profile). When the
  task is done, close every tab you opened (`browser_tabs` `{action:"close"}`
  per tab) so the next agent starts clean. Logins stay; they live in cookies.
- Never start another browser (no `chromium`, `google-chrome`, `firefox`,
  `npx playwright`, headless browsers): they have none of the logins and may
  open on Erik's screens.
- If `browser` can't connect: `systemctl --user status agent-chromium`,
  `systemctl --user restart agent-chromium` is fine (it's your browser), but
  other agents lose their tabs and session-only logins, so only when needed.

## Logins

### 1. You are normally already logged in (Firefox cookie sync)

Erik uses Firefox every day. The user timer `agent-cookie-sync.timer` copies his
Firefox cookies (persistent ones and the session ones from Firefox's session
store) into the agent Chromium every 5 minutes and right after the browser
starts. So Canvas, Microsoft 365/Outlook, Gmail, GitHub, X and so on open
already logged in, as Erik, with no sign-in and no phone prompt. Verified
2026-10-21: Canvas, `outlook.office.com`, Gmail.

- Firefox is the source of truth. A site is re-copied when its Firefox cookies
  change or when your browser lacks one of them. Only sites Erik used in
  Firefox in the last 30 days are copied (Chromium holds ~3300 cookies in
  total; `agent-cookie-sync --days N` widens it for a one-off run). The sync
  never deletes your cookies, so logins on sites Firefox has no cookies for
  stay.
- **Excluded sites** (`syncExcluded` in
  `modules/home-manager/computer-use/logins.nix`): `lastpass.com` (your
  LastPass has its own session) and **`linkedin.com`**: LinkedIn revokes a
  session the moment it is used from a second browser, which logged Erik out
  of LinkedIn in Firefox on 2026-10-21. The agent browser keeps its own
  LinkedIn login; logging in again needs approval in Erik's LinkedIn app, so
  the phone rule applies. If any other site logs out (in either browser)
  right after a sync, add it to `syncExcluded`, rebuild and tell Erik.
- **KTH webmail** (`webmail.kth.se`, Outlook Web App forms login) needs no
  phone: LastPass fills `erikfran` and the password, click Sign in. Its
  session is a session cookie, so it is gone after the agent browser restarts.
- Don't restart `agent-chromium` without reason: session-cookie logins the
  agent made itself are lost (the Firefox ones come back with the sync).
- If you hit a login page, first run `agent-cookie-sync -v` and reload. Erik
  may have logged in in Firefox after the last run.
- A login you make yourself in the agent browser stays there, but if Firefox
  has the same site under another account, the next change in Firefox
  overwrites it. Use Firefox's account, or ask Erik.

### 2. KTH Canvas: use the API token first (read-only)

**Canvas is read-only for agents (Erik, 2026-10-21).** Never push anything to
Canvas, through the API or in the browser where you are logged in as Erik: no
assignment submissions, discussion posts or replies, comments, file uploads,
inbox messages, peer reviews, quiz answers, calendar events, profile or
setting changes. Only GET requests with the token. If a task needs something
submitted, prepare it and hand it to Erik.

KTH's ADFS (`login.ug.kth.se`) single sign-on lasts only ~8 hours and every new
KTH login asks for Microsoft Authenticator. For anything the Canvas API can do
(courses, files, announcements, assignments, submissions, modules, pages), use
the API with the agents' own token. It does not depend on any browser session:

```sh
curl -sH "Authorization: Bearer $(agent-canvas-token)" https://canvas.kth.se/api/v1/users/self
```

The token is the sops secret `canvas-token` (PC). KTH caps tokens at 90 days;
`agent-canvas-token-renew.timer` checks daily and extends it by 89 days when
under 30 are left (about every 60 days). That renewal is the only write. If it ever returns 401
(`Invalid access token`), create a new one in a logged-in Canvas tab
(`POST /api/v1/users/self/tokens`, `expires_at` at most 89 days ahead), put it
into `hosts/pc/secrets/secrets.yaml` with `sops set --value-stdin`, update
`canvasTokenId` in `modules/home-manager/computer-use/logins.nix` and rebuild.
For the Canvas web UI, the synced Firefox session works while Erik's does.

### Microsoft Teams (Neptune Software): strictly read-only

Erik's work Teams (Neptune Software) is open in his Helium browser. You use the
**agent Chromium's own Neptune Microsoft session**, not his Helium window:
`https://teams.microsoft.com/v2/` in your own tab opens logged in ("stay signed
in" session, verified 2026-10-21) with no prompt. Never touch his Helium window.

**"We have to be very careful with this" (Erik).** Teams is read-only for you:
read chats and channels when a task needs it, and report what you found.
Never type in a compose box, send, reply, react, edit, delete, start a call,
change your status, join or leave anything, or open a meeting, without Erik's
explicit go-ahead for that exact message. Don't click into a chat's compose
area at all; read with `browser_evaluate` (`innerText`) or snapshots.

Before opening Teams (or any Microsoft app) after a long gap, check that no
prompt can fire: this sign-in request uses `prompt=none`, so Microsoft either
signs in silently or returns an error. It never asks for anything:

`https://login.microsoftonline.com/organizations/oauth2/v2.0/authorize?client_id=5e3ce6c0-2b1f-4285-8d4b-75ee78787346&response_type=id_token&scope=openid&nonce=x1&response_mode=fragment&prompt=none&redirect_uri=https%3A%2F%2Fteams.microsoft.com%2Fv2`

If it lands on `teams.microsoft.com/v2/#id_token=...`, go ahead. If it lands
on an `error=` (`login_required`, `interaction_required`), the session has
expired: the phone rule applies, so ask Erik before logging in.

### 3. Logging in yourself with LastPass

Only when 1 and 2 don't cover it. When a login form appears (tested on GitHub):

1. `browser_click` the username/email field. LastPass autofills it and opens
   its account picker ("Multiple accounts? Type to filter") right under the
   field. The picker is an iframe, so it is **not** in `browser_snapshot`.
2. `browser_take_screenshot`, find the right account in the picker, and click
   it with `browser_mouse_click_xy` (screenshot pixels = page coordinates).
   Username and password are then filled.
3. **Before you submit, apply the phone rule below.** Then submit and verify
   you're in.
4. "Sign in with Google/Microsoft" flows work the same way on their pages.

You never need to read or type a password yourself. To look something up in
the vault (a note, a username), open it through the DevTools endpoint
(Playwright refuses extension URLs), then find it with `browser_tabs`:

```sh
curl -s -X PUT "http://127.0.0.1:9222/json/new?chrome-extension://hdokiejnpimakedhajhdlcegeplioahd/vault.html"
```

### The phone rule (Erik, 2026-10-21)

**Never set off a phone sign-in prompt without warning Erik first.** These
prompts cover his whole phone screen; one destroyed a dictation. That covers
Microsoft Authenticator (any Microsoft/KTH/`login.ug.kth.se`/Entra login),
Google "Is it you?" prompts, LinkedIn app approvals, SMS/WhatsApp codes and
passkey prompts. If a login could end in one of those (submitting a password on
those sites almost always does):

1. Stop before submitting. Run `agent-cookie-sync -v` and reload: often you are
   then logged in and no prompt is needed.
2. Otherwise tell Erik in chat which site, why you need it, and that a prompt
   will appear on his phone (or ask him to log in in Firefox, which the sync
   then copies within 5 minutes). Wait for his OK. Don't submit the form
   until he says go.
3. Number-match prompts: tell him the number shown on the page.

Never retry a login that is waiting on his phone, and never loop on a login
page. Every attempt is another prompt.

**When you need Erik** (only these cases):

- LastPass itself is logged out (the picker doesn't appear and the vault asks
  for the master password), or
- the site wants a second factor you can't provide (see the phone rule),
  including security keys/passkeys (GitHub's `two-factor/webauthn` page).

Best is to ask him to log in to the site **in Firefox**: the sync copies it to
you and it stays useful for every later agent. Alternatively: *"Please run
`agent-browser-login` (also in the app launcher) and log in to SITE; close the
window when done."* It opens this same browser profile as a normal window on
his screen with his keyboard; when he closes it the browser returns to AGENT-1
with the session saved. His master password never passes through you. For a
one-off code (SMS/authenticator), you can instead ask him for the code in chat.
## Email codes and confirmation links (Thunderbird)

**Executor mail tools first.** Erik's personal Gmail (`ef.pro454@gmail.com`) is an
Executor app: `tools.gmail.searchThreads`, `getThread`, `getMessage`,
`listLabels`, `modifyLabels`, `archive`, `unsubscribeInfo` (read, label, archive
only; the app has no send or delete tools, never add them without Erik's OK). KTH mail is the `kth-mail` app (searchMessages, getMessage, markRead, archive; needs its own sign-in first).
Search with `search({query: "gmail"})` through the executor MCP. If the app
has no linked account yet, or the call fails, fall back to the methods below
and check the brain entry "Gmail and KTH mail through Executor". Neptune
mail and Teams stay out of Executor.

Logins often send a code or "confirm it's you" link by email. You can read
Erik's mail yourself; don't ask him to copy codes. His accounts:
`erik.frankling@frankling.se` (Office 365), `erik.frankling@gmail.com`,
`ef.pro454@gmail.com`, KTH (`erikfran`), `erik.frankling@outlook.com`.

Thunderbird syncs all of them as the user unit `thunderbird.service`, **out of
sight**: its window (class `agent-thunderbird`) always opens on the hidden
`agent-park` workspace on AGENT-1, never on Erik's monitors (2026-10-21; it
used to pop up on his screen). If `systemctl --user is-active thunderbird` is
not `active`, run `systemctl --user restart thunderbird` and wait ~60 s. Never
start `thunderbird` any other way, and never move its window to Erik's
monitors. Only he does that, with `open-mail`. In order:

1. **Webmail in your browser** (no GUI needed, freshest). Logged in already:
   `https://mail.google.com` (check which account), `https://outlook.office.com`
   (Neptune account; check the identity), `https://webmail.kth.se/owa/`
   (KTH, password login, no phone). Open it in your own tab and read.
2. **Read the mail store on disk** (code or link inside the message).
   Thunderbird keeps mbox files; newest messages are at the end:

   ```sh
   for f in ~/.thunderbird/default/ImapMail/*/INBOX*; do
     case "$f" in *.msf) continue;; esac
     echo "== $f ($(date -r "$f" '+%F %H:%M'))"
     tail -c 400000 "$f" | grep -a -E '^(From|Date|Subject): ' | tail -6
   done
   # then print the newest matching message body:
   tail -c 400000 "FILE" | grep -a -i -A60 '^Subject: .*KEYWORD' | tail -80
   ```

   Check the file timestamp: bodies land when Thunderbird syncs (every few
   minutes) or a message is opened.
3. **Look at the Thunderbird window** only if 1 and 2 fail. Windows on
   `agent-park` are not rendered, so a capture is blank. Move it to your
   visible workspace on AGENT-1, capture with `mcp__cua__get_window_state`
   (`include_accessibility_tree:false`) and `mcp__cua__zoom`, then park it
   again:

   ```sh
   hyprctl dispatch movetoworkspacesilent 'name:agent,class:^(agent-thunderbird)$'
   # ... capture ...
   hyprctl dispatch movetoworkspacesilent 'name:agent-park,class:^(agent-thunderbird)$'
   ```

   Read only: don't send, delete, move or mark mail.

### Codes that end up on the wrong side

- **A code reaches you** (mail, SMS mirrored to mail) **while Erik is the one
  on the code screen**: send it to his phone right away with
  `notify-erik --code CODE "SITE login code"` (or the Executor app `notify`),
  so he never waits on an entry screen without it. Don't make him ask.
- **A code reaches Erik** (SMS, authenticator) while you need it: ask for it
  in chat, say which site it is for, and keep the page open.
- Never trigger a code or prompt you will not use, and never re-send codes
  in a loop: every send is another interruption.

## QA / testing web apps

- Reproduce as a user would: navigate, click, type; after each step check
  the snapshot or screenshot, `browser_console_messages` for errors, and
  `browser_network_requests` for failing calls.
- Test keyboard behaviour with `browser_press_key` (Tab order, Enter to submit,
  Escape to close) and `browser_type` with `slowly:true` when the app reacts to
  individual keystrokes (autocomplete, search-as-you-type).
- Local dev servers (`http://localhost:PORT`) work the same way.
- Report concrete findings: what you did, what happened, what you expected,
  with screenshots. For a video walkthrough, see **screen-recording**.

## Downloads and files

Downloads go to `~/Downloads`. Uploads: `browser_file_upload` `{paths:[...]}`
with absolute paths.
