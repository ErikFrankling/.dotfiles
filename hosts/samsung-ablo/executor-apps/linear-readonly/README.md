# Linear

Adapted from https://catalog.executor.sh/apps/linear.json.
Upgraded on 2026-11-10 at Erik's request for full service access.
Uses Linear's official https://mcp.linear.app/mcp endpoint with OAuth scopes
`read` and `write`, as advertised by its authorization server. Reference:
https://linear.app/docs/mcp. The historical source-directory name is retained.

Existing app ID: `app_d5bfa251-b235-4ec7-aa47-725ebb49b4bb`.
Setup: http://127.0.0.1:4788/apps/app_d5bfa251-b235-4ec7-aa47-725ebb49b4bb/setup

Reconnect the Ablo account after upgrading scopes. OAuth client registration
is automatic; no client ID/secret needs to be created. Select the Ablo
workspace during consent. Both Claude and Codex use the resulting connection.
MCP tools without a read-only annotation retain upstream approval protection.
Account permissions still apply; installing this adapter does not grant
permissions the signed-in user lacks. Human-channel communication still needs
Erik's approval of the exact message.
