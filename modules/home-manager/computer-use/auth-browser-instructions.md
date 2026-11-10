# Authentication: real agent browser only

Erik's explicit rule (2026-11-10): **Never use T3 Code's built-in preview browser for anything authentication-related.**

For sign-in, OAuth/SSO, account linking, consent, MFA/passkeys, password managers,
or any site that needs an existing login, load `browser-use` and `computer-use`.
Use the real agent Chromium through the `browser` MCP; use the configured
computer-use tools for native dialogs. This applies on the laptops and PC, in
Claude and Codex, including delegated agents.

**Do not open or probe `preview_*` first for these tasks.** Its isolated profile
does not have Erik's Firefox sessions. A login page there is not evidence that
Erik is logged out or must authenticate again. Do not ask him to sign into the
built-in preview as a workaround.

Run `agent-cookie-sync` and retry in the real agent browser before requesting a
login. If sync finds no profile, repair profile discovery (current Firefox uses
`~/.config/mozilla/firefox`; legacy profiles use `~/.mozilla/firefox`). Preserve
the existing rules about Erik's own windows, external communication and phone
approval prompts. A real identity-provider reauthentication/MFA challenge is
different from an empty preview profile; report the actual challenge precisely.

Built-in preview remains suitable for public/unauthenticated pages and app UI
previews that do not depend on existing accounts.
