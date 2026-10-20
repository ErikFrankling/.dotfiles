# Activating the T3 Codex Executor fix

Executor disappearing from a Codex tool catalog does not necessarily mean
Executor is down. On 2026-10-20, the installed T3 build contained the fix from
`71a3d7de`, but the running server still used the older bundle.

`hosts/pc/home.nix` deliberately sets `X-SwitchMethod=keep-old`: a rebuild
installs updates without interrupting active agent turns. Compare the running
process with the installed service before changing credentials or adding
another MCP server:

```sh
systemctl --user show t3code -p MainPID -p ExecStart
ps -p "$(systemctl --user show t3code -p MainPID --value)" -o args=
```

The running command identifies the actual `t3code-unwrapped` store path.
Inspect its `libexec/t3code/apps/server/dist/binCli-*.mjs` bundle. The fixed
adapter uses `"mcp_servers.t3-code"`; the old adapter sets the entire
`mcp_servers` object. The latter drops MCP overrides supplied by the Codex
launcher, including Executor. An app-server-wide MCP status check can still
look healthy; query `mcpServerStatus/list` with a `threadId`.

After a successful `rebuild`, a deliberate restart is needed to load the
installed adapter. This interrupts active T3 turns. Mark the outage first:

```sh
health-watch maintenance 5 "activate T3 Codex MCP preservation fix" t3code
systemctl --user restart t3code
```

Run the restart from outside the T3 service's cgroup, since stopping that
service also stops its agent processes. Afterward, check the running bundle
again and start or resume a Codex session. Its callable catalog should include
Executor's six MCP tools: `skills`, `search`, `describe`, `call`, `execute`,
and `resume`. The brain operations are discovered through Executor `search`
with namespace `brain`, then invoked through `call` or `execute`; they are not
separate top-level MCP tools.

For diagnostics when the session lacks Executor, its existing HTTP MCP endpoint
can be called directly. Read `/run/secrets/executor-api-key` without logging
it; send `initialize`, retain the response's `Mcp-Session-Id`, and include it
in subsequent `tools/list` and `tools/call` requests. Send both
`Content-Type: application/json` and `Accept: application/json, text/event-stream`.
Pass `agent: "Codex"` on brain calls. Never store the token in the repository.
