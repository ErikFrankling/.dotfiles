---
name: browser-use
description: Browser use on Erik's PC. Load whenever a task involves a website or web app: "browser use", "computer use" on a site, logging in to anything (GitHub, Gmail/Google, Microsoft/Teams/Outlook, Basecamp, cloud consoles, the apps Erik is building), testing/QA of a web UI, filling forms, downloading from a site. You drive the agent's own Chromium (LastPass installed and logged in) with the `browser` Playwright MCP.
---

# Browser use on Erik's PC

You have your own browser: **the agent Chromium**, a permanent Chromium running
on your monitor AGENT-1 (workspace `agent`), separate from Erik's Firefox. It has
**LastPass installed and logged in to Erik's vault**, and its profile keeps every
site you log in to logged in. **You are allowed to use Erik's accounts.** Log in
wherever a task needs it, using LastPass. Don't ask permission and don't stop
at a login page: logging in is part of the job.

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

- The agent Chromium runs in the background with no window until you open a
  page. Your first page becomes one full-screen window on AGENT-1; open more
  pages as **tabs** (`browser_tabs` `{action:"new", url}`), switch with
  `{action:"select", index}`, close finished ones with `{action:"close"}`.
- Every `agent-chromium` window is forced onto AGENT-1 by a Hyprland rule, so
  nothing can open on Erik's monitors. Still, don't open extra windows.
- Tabs **persist after your session** (it's a real browser profile). When the
  task is done, close every tab you opened (`browser_tabs` `{action:"close"}`
  per tab) so the next agent starts clean. Logins stay; they live in cookies.
- Never start another browser (no `chromium`, `google-chrome`, `firefox`,
  `npx playwright`, headless browsers): they have none of the logins and may
  open on Erik's screens. Erik's own Firefox is off limits.
- If `browser` can't connect: `systemctl --user status agent-chromium`,
  `systemctl --user restart agent-chromium` is fine (it's your browser).

## Logging in with LastPass

Most sites are already logged in from earlier sessions: check the page first.
When a login form appears (tested on GitHub):

1. `browser_click` the username/email field. LastPass autofills it and opens
   its account picker ("Multiple accounts? Type to filter") right under the
   field. The picker is an iframe, so it is **not** in `browser_snapshot`.
2. `browser_take_screenshot`, find the right account in the picker, and click
   it with `browser_mouse_click_xy` (screenshot pixels = page coordinates).
   Username and password are then filled.
3. Submit (`browser_click` the sign-in button) and verify you're in.
4. "Sign in with Google/Microsoft" flows work the same way on their pages.

You never need to read or type a password yourself. To look something up in
the vault (a note, a username), open it through the DevTools endpoint
(Playwright refuses extension URLs), then find it with `browser_tabs`:

```sh
curl -s -X PUT "http://127.0.0.1:9222/json/new?chrome-extension://hdokiejnpimakedhajhdlcegeplioahd/vault.html"
```

**When you need Erik** (only these cases):

- LastPass itself is logged out (the picker doesn't appear and the vault asks
  for the master password), or
- the site wants a second factor you can't provide: security key/passkey
  (GitHub's `two-factor/webauthn` page), a phone prompt, an SMS code.

Then stop and tell him exactly: *"Please run `agent-browser-login` (also in
the app launcher) and log in to SITE; close the window when done."* It opens
this same browser profile as a normal window on his screen with his keyboard;
when he closes it the browser returns to AGENT-1 with the session saved, and you
continue. His master password never passes through you. For a one-off code
(SMS/authenticator), you can instead ask him for the code in chat.

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
