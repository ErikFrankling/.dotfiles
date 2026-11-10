# PostHog

Adapted from https://catalog.executor.sh/apps/posthog.json.
Upgraded on 2026-11-10 at Erik's request for full service access. `scopes.json`
contains the current scopes advertised by
https://mcp.posthog.com/.well-known/oauth-protected-resource, excluding the
server's `introspection` scope: 82 read, 71 write and three identity scopes.
The historical source-directory name is retained.

OAuth is DCR/PKCE at https://mcp.posthog.com/mcp (US/EU accounts route
automatically). No client secret or personal key is required.

Existing app ID: `app_9c3b3a30-101a-49b5-922a-4c8017b8a482`.
Setup: http://127.0.0.1:4788/apps/app_9c3b3a30-101a-49b5-922a-4c8017b8a482/setup

Reconnect the Ablo account after upgrading scopes, selecting the intended
project during consent. MCP tools without a read-only annotation retain
upstream approval protection. Account permissions still apply; the adapter
does not grant permissions the signed-in user lacks. Human-channel
communication still needs Erik's approval of the exact message.
