# Firefox with Erik's existing logins

Erik wants an ordinary additional Firefox window, using his running profile,
on the agent monitor. His original windows and tabs stay on the physical
monitors. This is the default for account tasks, including GitHub and LastPass.

## Open the window normally

1. Read `hyprctl -j clients`, `hyprctl -j monitors`, and the active window.
   Record existing Firefox window addresses, stable IDs, PIDs, and workspaces.
   Reuse a known agent-created window if its UI supports the requested action.
2. Open an ordinary new window with the task URL:

   ```sh
   hyprctl dispatch exec '[workspace name:agent silent] /run/current-system/sw/bin/firefox --new-window https://github.com/settings/profile'
   ```

   Substitute the actual URL using proper shell quoting. Do not add
   `--no-remote`, `--profile`, or `HYPRLAND_AGENT_SEAT`. These change the behavior
   we need. Do not terminate or restart the existing browser.
3. Poll clients with a bounded timeout. Identify exactly one new Firefox window
   by comparing addresses with the before snapshot. If ambiguous, inspect the
   new windows; never choose or move an existing human window.
4. Check placement. If necessary, move **only that new window**:

   ```sh
   hyprctl dispatch movetoworkspacesilent 'name:agent,address:EXACT_NEW_ADDRESS'
   ```

5. Verify its PID matches the running normal Firefox, its monitor is `AGENT-1`,
   and existing human window placement and active-window identity are unchanged.
   Observe `agent-desktop screenshot FILE` to verify the actual loaded page.

A successful launch is not proof of account access. For GitHub, its authenticated
settings page shows the account identity. If already signed in, continue with
the task; do not log out merely to test logging in again. LastPass is the same
extension in the same running profile, but check its UI if the task requires
using the vault rather than assuming it is unlocked.

## Use the existing accessibility UI

`busctl` is installed. Firefox exposes browser and web-page controls through
AT-SPI. These are application UI actions; they do not inject keys into the
human keyboard or require the private agent seat. No new server is needed.

Discover addresses each session; never reuse example bus names or object IDs:

```sh
busctl --user call org.a11y.Bus /org/a11y/bus org.a11y.Bus GetAddress
busctl --address="$a11y_address" list
```

Match the AT-SPI application bus connection to the Firefox PID obtained above.
Query its root children, then match the **agent window's exact current title**.
If multiple roots have the same title, do not guess. Scope traversal to that
root rather than dumping all human windows or tabs.

```sh
busctl --address="$a11y_address" --json=short call "$firefox_bus" \
  /org/a11y/atspi/accessible/root org.a11y.atspi.Accessible GetChildren
busctl --address="$a11y_address" --json=short call "$firefox_bus" "$node" \
  org.freedesktop.DBus.Properties GetAll s org.a11y.atspi.Accessible
busctl --address="$a11y_address" --json=short call "$firefox_bus" "$node" \
  org.a11y.atspi.Accessible GetRoleName
busctl --address="$a11y_address" --json=short call "$firefox_bus" "$node" \
  org.a11y.atspi.Accessible GetChildren
```

Traverse descendants with a node limit and per-call timeout. Properties include
`Name`, `Parent`, and `Attributes` (HTML tag/id/class), which distinguish a page
button from browser chrome. Verify the node still descends from the agent root
before acting. Re-query after navigation because object paths can become stale.

Inspect action names, then invoke the desired UI action:

```sh
busctl --address="$a11y_address" --json=short call "$firefox_bus" "$node" \
  org.a11y.atspi.Action GetName i 0
busctl --address="$a11y_address" --json=short call "$firefox_bus" "$node" \
  org.a11y.atspi.Action DoAction i 0
```

For editable controls, inspect `Accessible.GetInterfaces` first. The standard
method is `org.a11y.atspi.EditableText.SetTextContents s TEXT`; verify its visible
result before submitting. Do not put credentials in reusable skill files or
print password-field contents. Firefox's `GetActions` result was malformed on
this installation; `GetName` returned useful names such as `press` and `click`.

**An action returning `true` only acknowledges the request.** Observe the page
and check the active human window after interaction. During validation, the
GitHub page's menu and Appearance link worked; background address-bar editing
and the LastPass toolbar action did not produce a verified result. Do not claim
those worked or repeatedly send input because of the acknowledgement. Opening
a normal new window at the desired URL is the tested navigation path.

The compositor MCP's `input_window` still cannot control a normal shared Firefox
process. Do not try to solve that by marking the entire browser as agent-owned,
changing seat filters, disabling IBus, or moving the human window. Accessibility
is useful for exposed controls, not a claim that arbitrary canvas interactions,
all extension popups, or independent simultaneous typing have been validated.

## Verified on 2026-09-22

- Opened a new window in the existing Firefox PID on `AGENT-1`.
- GitHub's authenticated profile settings showed `ErikFrankling` without a login.
- Activated GitHub's settings menu and followed Appearance through its UI;
  the resulting window title was `Appearance`.
- Existing human windows retained their workspace/monitor placement; the active
  human window was unchanged after launch and the tested UI actions.
- No account settings were saved, no human browser was closed, and no profile
  was copied. This verifies reuse of an existing login, not a fresh LastPass or
  GitHub authentication flow.
