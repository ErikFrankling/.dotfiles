---
name: computer-use
description: Operate browser windows and native applications on Erik's local agent desktop using the shared computer-use tools. Use for requests to click, type, inspect an app, or complete a workflow through its GUI on this PC.
---

# Computer use on this PC

For Firefox account work, reuse **one agent-owned Firefox window in Erik's existing
profile** on `AGENT-1`, filling the agent monitor. Open additional pages as
**tabs in that same window**, not additional tiled windows. Create the window
only if no suitable agent-owned window exists. It shares his website logins and LastPass
installation. Follow [Firefox with existing logins](firefox.md) for the tested
launch and window-scoped accessibility UI workflow. Check whether the site is
already signed in before opening LastPass. Never close Erik's Firefox or move
his existing windows to reuse the profile. No profile copying, browser restart,
new automation server, or compositor change is needed for this workflow.

For applications launched on the independent agent seat, use the `agent-desktop`
MCP server for GUI actions. Its launch command is
`agent-computer-use mcp`. Read the tools' current schemas before calling them;
tool availability in a previous session does not establish that this session
is connected.

The agent's display is the headless Hyprland output `AGENT-1`, with workspace
`name:agent`. Erik's physical displays are for his own work. Dedicated agent
processes use an independent input seat; shared Firefox instead uses the
window's accessibility UI actions described in the linked reference.
The plugin filters seat visibility: normal clients see the native seat, and
clients launched with `HYPRLAND_AGENT_SEAT=1` see the agent seat. The Firefox
service sets this marker before process startup. Never export it into the
user's session or human application launchers; changing it after a client
connects does not change that client's seat classification.

## Start a task

Run `agent-desktop status` to check the current runtime. If the independent
input backend or agent output is unavailable, report the failure and diagnose
that path. Do not switch to global `ydotool`, `hyprctl dispatch` focus changes,
or the older built-in computer-use backend to get past the failure: those can
move Erik's pointer or send keystrokes to his windows.

Use `agent-desktop --help` for the installed helper's command syntax. It provides
`start-browser`, `screenshot FILE`, and `view` as well as `status`.
**The existing `start-browser` command starts the separate test profile. Do not
use it for Erik's logged-in account workflows.** Use the normal-window procedure
in `firefox.md` instead. Keep the separate service for independent-seat tests
or tasks that explicitly need a different profile.

Inspect the target window and a fresh agent-display screenshot before acting.
Check window/output identity, rather than assuming that every window returned
by a desktop-wide tool belongs to the agent. Keep actions on `AGENT-1`; leave
human windows where they are. Launch native applications using the installed
agent-desktop helper's supported commands, if available, and verify placement
before input. If a requested app cannot be opened there reliably, report that
specific limitation.

## Work and verify

Use `computer_status` to inspect connection grants and pause state, then
`list_windows` for stable window IDs. This backend provides compositor window
and surface metadata, not a semantic accessibility tree. Use `view_window` for
pixels and `window_state` for popup/subsurface geometry.

Request `control` permission with `scope: {kind: "window", id: window_id}` for
input, or `observe` for viewing only. Control also covers observation. The local
supervisor automatically approves these requests for 300 seconds only while
the mapped window belongs to an opted-in agent process on output `AGENT-1`
and workspace `agent`. Human windows can land there when displays disconnect;
placement alone never makes them agent windows. For an
`approval_required` response, use `wait_for_permission` and retry after a grant.
These grants apply to the independent-seat MCP route. A normal shared Firefox
window does not acquire that seat by being moved to `AGENT-1`; use its
accessibility UI, not an MCP permission request that will remain pending.
The supervisor does not auto-approve workspace, recording, or launch access.
Transient toplevel dialogs need their own window grant. If paused, respect the
owner's pause; do not issue UI resume/mode commands to bypass it.

`input_window` takes **window-local logical coordinates** and the current
geometry `revision`. For a resized/cropped `view_window` image, convert using
its `image_to_window`: `x = pixel_x * scale_x + offset_x`, and likewise for y.
Do not add the output's desktop position. Surface-targeted input instead uses
`surface_id`, `surface_revision`, and surface-local coordinates from
`window_state`. Refresh observations after layout changes; frame IDs are not
input freshness tokens.

Use `then: "screenshot"` when an action and its follow-up capture should share
one call. Input can complete before rendering does, so verify the resulting
state. On partial failures inspect acknowledged actions/characters and observe
again before retrying; do not replay completed typing because capture failed.

Client support depends on binding both pointer and keyboard resources for the
independent seat. Unsupported clients, explicit focus actions, and active popup
grabs are refused. Report that limitation for the actual app; a running Firefox
service is not proof that every Firefox dialog accepts independent input.

Do not have multiple sessions operate this one desktop concurrently. Respect
runtime ownership/busy errors; coordinate a handoff rather than launching a
second input backend. Keep the scope of external actions within the user's task.

`agent-desktop view` opens the agent display for Erik. The VNC endpoint is
loopback port `5903` and is view-only; opening the viewer does not enable human
clicks. If a step needs Erik's interaction, explain the exact blocked step and
the available handoff mechanism rather than promising that the viewer accepts
input. Do not change VNC input mode or take over a physical display implicitly.

## Connection and maintenance

The shared skill and tools are local machine capabilities. A cloud harness
does not gain access merely by loading these instructions. If this session has
no `agent-desktop` tools, report that registration/connection gap; do not claim
the runtime is working based on this skill's presence.

The source is in `~/.dotfiles/modules/home-manager/computer-use/`. Changes to
packages, services, wrappers, and skill distribution belong in the Nix config.
Consult that repository's `AGENTS.md` before modifying it.

`agent-input-plugin.service` refuses to replace a different plugin in a live
session. A plugin update requires a planned Hyprland logout/login because the
old plugin owns client-bound Wayland resources; never work around this by
hot-unloading it or stopping the user's input method.

For implementation verification, `agent-desktop-self-test [OUTPUT_DIRECTORY]`
drives a disposable local page through MCP and checks actual browser events.
Run it only when testing the setup; it operates the agent Firefox. Its report explicitly
separates tested paths from concurrent-modifier and authenticated-flow coverage.
