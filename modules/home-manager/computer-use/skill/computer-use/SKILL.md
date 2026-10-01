---
name: computer-use
description: Computer use on Erik's PC. Load whenever Erik says "computer use", "use the computer", "click through", "QA this", "test the UI", "open the app", "take a screenshot", or asks for anything done through a GUI: desktop apps, windows, keyboard/mouse input, screenshots, or screen recordings. For websites also load browser-use; for videos/demos also load screen-recording.
---

# Computer use on Erik's PC

You have your own monitor, your own keyboard and mouse, and your own browser on
this machine. **Erik wants you to use them freely and to solve problems on your
own.** Don't ask for permission to click, type, open apps, log in to sites, or
use his accounts: he has given you that access deliberately. Figure out the UI,
recover from mistakes, and verify the result. Only stop to ask when something is
truly impossible from here (a code sent to his phone, a physical key) and say
exactly what you need. Use normal judgement for irreversible actions outside the
task (mailing other people, deleting data, payments).

Related skills: **browser-use** (websites, logins, LastPass) and
**screen-recording** (videos, demos with captions). Load them when relevant.

## The setup in one picture

Erik runs **Hyprland** (a tiling Wayland compositor) with three outputs:

| Output | What | Workspaces | Yours? |
|---|---|---|---|
| `DP-3` | Erik's physical 4K monitor | 1-10 | **never touch** |
| `HDMI-A-1` | Erik's physical 4K monitor | 1-10 | **never touch** |
| `AGENT-1` | invisible headless monitor, 1920x1080 | `agent`, `agent-park` | **yours** |

- **Seats.** A Wayland *seat* is a keyboard+pointer pair. Erik uses the normal
  seat. You have a separate **agent seat**: your clicks and keystrokes go only to
  apps that were started on the agent seat, and never to Erik's windows. You can
  work while he keeps typing. Nothing you do can move his mouse or steal focus,
  as long as you use the tools below.
- **Workspace `agent`** is what AGENT-1 shows and the only place your input is
  accepted. **Workspace `agent-park`** is a hidden shelf on AGENT-1 for windows
  you want off screen (e.g. while recording). Both exist permanently.
- Everything you open must end up on AGENT-1. Never open windows on Erik's
  monitors, never switch his workspaces, never run `hyprctl dispatch
  workspace|focuswindow|movefocus|movetoworkspace` without `silent` and an
  explicit `address:` of *your* window, and never use `ydotool`, `wtype`,
  `xdotool` or anything that injects global input.
- Erik can watch AGENT-1 with `agent-desktop view` (view-only VNC).

## Your tools (MCP servers)

| Server | Use it for |
|---|---|
| `browser` (Playwright) | Everything in the agent Chromium: websites, web apps, logins. See **browser-use**. |
| `cua` (Cua Driver) | Finding windows and **reading/operating desktop apps via accessibility**: `list_windows`, `get_window_state` (element tree + screenshot), `click`/`set_value`/`double_click`/`right_click` by `element_index`, `zoom` into a region. |
| `agent-seat` | **Real keyboard and mouse** on agent-seat windows (`input_window`), window screenshots (`view_window`), window-only video (`record_window`). |

Tool names appear as e.g. `mcp__cua__get_window_state`,
`mcp__agent-seat__input_window`, `mcp__browser__browser_navigate`.

Shell helpers: `agent-desktop status` (health), `agent-desktop screenshot
FILE.png` (the whole AGENT-1 screen), `hyprctl -i 0 clients -j` (window list;
`-i 0` picks the running Hyprland even if your shell lacks
`HYPRLAND_INSTANCE_SIGNATURE`).

## Opening apps

Start GUI apps on your workspace **and** your seat:

```sh
hyprctl -i 0 dispatch exec '[workspace name:agent silent] env HYPRLAND_AGENT_SEAT=1 gnome-calculator'
# Chromium/Electron apps overwrite their environment, so also pass the switch:
hyprctl -i 0 dispatch exec '[workspace name:agent silent] env HYPRLAND_AGENT_SEAT=1 some-electron-app --hyprland-agent-seat'
```

Then find it with `mcp__cua__list_windows` or `hyprctl -i 0 clients -j` (match
`class`, workspace `agent`). Rules:

- It must be a **new process**. Apps that are already running for Erik
  (Firefox, Spotify, Discord, Obsidian, kitty...) hand the request to his
  process: the window opens on his screen and is his, not yours. Don't launch
  those. If you did by accident, close only that new window.
- Native Wayland apps work best. XWayland apps and kitty cannot use the agent
  seat; use GNOME Terminal if you need a GUI terminal (you normally have a shell).
- A watcher moves any window of an agent-seat app (dialogs, extra windows)
  or of a program you started straight from your shell onto workspace `agent`
  the instant it opens. That is a safety net, not the plan: a window launched
  without the `[workspace name:agent silent]` rule still flashes on Erik's
  screen for a moment and, without the seat marker, can't take your input.
  Always launch with the full command above.
- Close what you open when you are done:
  `hyprctl -i 0 dispatch closewindow address:0x...` (your window's address only).

## Window handling on AGENT-1

Hyprland **tiles**: every window on workspace `agent` shares the 1920x1080
screen, so two windows get half the screen each, four get a quarter. Keep it
tidy:

- One app on screen at a time is best: it fills AGENT-1, screenshots are
  sharp, and recordings look good.
- Park windows you need later instead of stacking them:
  `hyprctl -i 0 dispatch movetoworkspacesilent name:agent-park,address:0xADDR`
  and bring one back with
  `hyprctl -i 0 dispatch movetoworkspacesilent name:agent,address:0xADDR`.
  Always `movetoworkspacesilent` (never plain `movetoworkspace`), always with
  your window's address. Parked windows can't receive input until they're back
  on `agent`.
- The agent Chromium is a permanent service (its window appears when a page is open); park its window instead of closing it mid-task.
- Window addresses come from `hyprctl -i 0 clients -j` (`address`), the
  agent-seat tools use `id` from their own `list_windows`, and Cua uses
  `window_id` + `pid` from its `list_windows`.

## Seeing the screen

- One app, with its UI elements: `mcp__cua__get_window_state` with `pid` and
  `window_id` returns the accessibility tree (numbered elements with
  labels/values) **and** a screenshot. Prefer the tree for reading text and
  finding controls; use the screenshot for layout and visual checks.
  Use `query` to filter big trees and `include_screenshot:false` when you only
  need the tree.
- One window as pixels: `mcp__agent-seat__view_window` (`window_id`, optional
  `region` to zoom, `max_width`). The result includes `image_to_window` for
  converting image pixels to window coordinates.
- Whole agent screen: `agent-desktop screenshot /path/shot.png`, then view the file.
- Browser pages: see **browser-use** (`browser_snapshot` / `browser_take_screenshot`).

## Mouse and keyboard input

Two routes. Pick the first that works:

1. **By element (accessibility, fastest):** from `get_window_state`,
   `mcp__cua__click` / `double_click` / `right_click` with the `element_token`
   (or `snapshot_id` + `element_index`), and `mcp__cua__set_value` for text
   fields. **Only for elements whose `actions` list is non-empty** (`click`,
   `press`, `activate`, `toggle`...). Elements with `actions=[]` (e.g. GTK tabs,
   many list rows) can't be activated this way: Cua then falls back to X11
   input, which fails on this Wayland desktop ("X11 connection failed"). Use
   route 2 for those, clicking the centre of the element's `frame`.
   Results with `"effect":"unverifiable"` mean "sent", not "worked": re-read
   the tree or screenshot to confirm.
2. **Real keyboard/mouse on the agent seat:** `mcp__agent-seat__input_window`
   with `window_id`, the window's current `revision` (from `list_windows` /
   `view_window`) and a list of `actions`:
   - `{"type":"click","x":X,"y":Y}` (window-local coordinates; `button`,
     `click_count`, `modifiers` optional)
   - `{"type":"text","text":"hello"}`: types text into the focused control
   - `{"type":"key","key":"CTRL+S"}`: keys and chords (`ENTER`, `TAB`,
     `ESCAPE`, `CTRL+A`, `SHIFT+TAB`, `ALT+F4`...)
   - `{"type":"scroll","x":X,"y":Y,"delta":3}` (positive = down), `{"type":"drag","x":X1,"y":Y1,"to_x":X2,"to_y":Y2}`
   Add `"then":"screenshot"` (and `"observation":{"delay_ms":500}`) to get a
   screenshot after the actions in the same call. Batch several actions in one
   call when you know the sequence (click field, type, Enter).

   Before the first input on a window, call `mcp__agent-seat__request_permission`
   with `capability:"control"` and `scope:{kind:"window",id:ID}`. A local
   supervisor approves agent-seat windows on workspace `agent` automatically; if
   it says `approval_required`, call `wait_for_permission` with the `request_id`.
   If computer use is **paused**, Erik paused it: stop and tell him.

   Coordinates are **window-local logical pixels**. If you clicked from a
   downscaled screenshot, convert with its `image_to_window` transform:
   `x = px * scale_x + offset_x`. From a Cua element `frame` (screen
   coordinates): `x = frame.x + frame.w/2 - window_bounds.x`, same for y.

**Testing keyboard input** (for QA): focus the field by clicking it, send
`text` then check the value in `get_window_state` (the element's `value`) or a
fresh screenshot. Test shortcuts with `key` chords and verify the visible
effect. `input_window` reports how many actions/characters were acknowledged;
after an error, observe first, and never blindly replay text that was already typed.

## Verify, always

Input can land before the app repaints. After every meaningful action check the
result (tree value, screenshot, page title) before moving on, and at the end
confirm the task's outcome, not just that the clicks were sent.

## When things fail

- `independent_seat_unsupported_by_client`: the app wasn't started on the agent
  seat (missing env/switch, or it joined an existing process). Relaunch it properly.
- `approval_required` that never resolves: the window isn't an agent-seat window
  on workspace `agent` (maybe it's parked, or it is Erik's).
- `agent-desktop status` shows service health. Implementation:
  `~/.dotfiles/modules/home-manager/computer-use/` (Nix-managed; follow
  `~/.dotfiles/AGENTS.md` to change it).
