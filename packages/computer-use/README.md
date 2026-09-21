# Hyprland computer-use backend

Pinned upstream: [SamSaffron/hyprland-computer-use, afcd3dc](https://github.com/SamSaffron/hyprland-computer-use/tree/afcd3dc39d859f18c0ac13c90625becb4a45ef66).
This package does not activate a service or load a plugin.

```nix
backend = pkgs.callPackage ../../packages/computer-use {
  hyprland = config.programs.hyprland.package;
};
```

- Broker/stdio bridge: `${backend}/bin/hyprland-computer-use`.
- Plugin: `${backend.plugin}/lib/guard-seat.so`.
- Header commit check: `${backend.plugin}/bin/computer-use-header-version`.
- `serve` runs the broker; `mcp` connects a harness over stdio; `console` opens
  the permission UI. Both broker and console belong in the graphical session.
- Native socket: `$XDG_RUNTIME_DIR/computer-use/guard.sock`; broker sockets:
  `mcp.sock` and `ui.sock` in the same directory.
- `setup` is deliberately disabled: Nix builds the native artifact, and the
  desktop module owns activation. Replacing an active seat-owning plugin requires
  a full compositor restart; do not hot-unload it.

## Local behavior

The compositor refuses input unless the target client bound both agent-seat
keyboard and pointer resources. The guard advertises `automatic_fallback=false`,
and the broker refuses any guard advertising fallback or lacking an independent
seat. Explicit desktop `focus` actions are refused. There is no shared-input
fallback.

Input is confined to monitor `AGENT-1`, workspace `agent`. This is checked in the
compositor for every transaction and in continuing seat authorization, including
popup callbacks. Moving a target onto a physical output invalidates its input
route even before the external supervisor revokes its grant. Monitor/workspace
names are intentionally fixed in `seat_only_policy.hpp`; keep them consistent
with the desktop module.

This is input confinement, not an OS security boundary. Same-user agents with a
shell can access the trusted UI socket. Applications can still request desktop
activation themselves. Capture permissions are enforced by the upstream broker;
this patch does not implement compositor-side capture confinement.

## Validation and limits

The plugin uses the supplied Hyprland package's own stdenv and build inputs,
including matching private headers. It also retains upstream's runtime commit
check. Both source and Go dependencies have fixed hashes.

Package builds run all Go tests, upstream native unit/protocol tests, and local
seat/confinement refusal-policy tests. Nix-specific fixture fixes replace two
hard-coded `/bin` utilities and disable Go path trimming only during tests.
These checks do not establish live application compatibility.

Native Wayland only. GTK popup seat serials, same-process browser menus, Unicode,
and Firefox/LastPass need live validation. XWayland, clipboard, IME, and DnD do
not have independently implemented input here. An extra seat does not make a
single-seat application compatible; unsupported targets must remain refused.
The toolkit supplies window discovery, toplevel capture, surface metadata,
batched input and optional post-action observation, not an AT-SPI tree engine.
## Native keyboard regression and live validation

On 2026-09-21, loading the independent seat disrupted human Firefox text input
before any agent GUI actions were sent. IBus 1.5.34 binds every advertised seat
and replaces its active seat even when Hyprland rejects the additional input
method. Its unavailable callback does not restore the original seat, and key
forwarding then uses an uninitialized/rejected seat. The local IBus patch in
`../ibus-native-seat.patch` preserves the first/native seat. The frontend is
managed by `modules/home-manager/ibus-native-seat.nix`.

The follow-up live MCP test also found that the upstream independent-seat
implementation refuses every input action while the human IBus grab is active
(`agent_seat_constraint_capture_drag_or_ime_unsupported`). Stopping the human
input method is not a solution. Agent and native input paths must be independent.

`modules/home-manager/computer-use/tests/live_e2e.py` is an opt-in test against
the running agent Firefox. It drives a disposable loopback page through the
actual MCP stdio bridge and checks trusted browser events, Unicode, chords,
clicks, an HTML popover, dragging, scrolling, captures, permission boundaries,
and native keyboard/focus state, including native Firefox popup open/dismiss.
It does not claim held-human-modifier coverage. Run
`agent-desktop-self-test [OUTPUT_DIRECTORY]` and retain
the JSON report; package tests alone do not establish desktop coexistence.

The opt-in filter uses `HYPRLAND_AGENT_SEAT=1` from each client's initial process
environment. Native clients see the compositor seat; agent clients see only the
private seat. Unsupported native-seat protocols are hidden from agent clients.
GTK's mandatory data-device manager is replaced with an empty private manager;
clipboard transfer and native drag-and-drop are unavailable, and cannot mutate
the human selection through that manager.

The compositor's original global filter is retained, preserving its security
context checks. Its local symbol offset is resolved during the Nix build from
the exact Hyprland binary; runtime requires that same immutable executable path.
This also restores a compositor-owned callback if plugin initialization fails.

## Live verification on 2026-09-21

After restarting Hyprland, the read-only probe confirmed one native seat for an
ordinary client and one private seat for a marked client. The Firefox MCP suite
passed, with native focus and the main keyboard unchanged. A separate native
Firefox context-menu test confirmed popup creation and Escape dismissal.
Ordinary input calls took roughly 8–10 ms and full window captures 60–80 ms on
this machine. These are tool response times, not model latency or guaranteed
application paint completion; the combined capture with a 200 ms delay could
still precede the browser's visible text update. Re-observe after input when the
image does not yet show the expected state.

The approval supervisor also requires the process opt-in marker, so human
windows moved onto the headless workspace after display disconnection do not
receive automatic grants. Authenticated LastPass flows, physical held-modifier
coexistence, and native applications beyond Firefox have not been exercised.
Clipboard transfer/native DnD remain intentionally unsupported; the VNC viewer
is view-only.
