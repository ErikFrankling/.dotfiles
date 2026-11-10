# PostHog (read scopes)

Adapted from https://catalog.executor.sh/apps/posthog.json on 2026-11-10.
The committed scopes are exactly the `:read` scopes advertised by
https://mcp.posthog.com/.well-known/oauth-protected-resource on that date.
OAuth is DCR/PKCE at https://mcp.posthog.com/mcp (US/EU accounts route
automatically). No client secret or personal key is required.

App: `app_9c3b3a30-101a-49b5-922a-4c8017b8a482`.
Setup: http://127.0.0.1:4788/apps/app_9c3b3a30-101a-49b5-922a-4c8017b8a482/setup

Connect the Ablo account and choose the intended project during consent.
Read-only OAuth scopes restrict provider access; the MCP server may still list
write tools. Upstream approval protection for all tools without readOnlyHint
is retained. A listed tool is not evidence that its operation is authorized.
The server must enforce the granted OAuth scopes; verify useful read tools
after sign-in. No account is connected by deployment alone.
