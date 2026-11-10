# Gmail

Official Executor catalog app from https://catalog.executor.sh/apps/gmail.json,
refreshed 2026-11-10. The historical directory name is retained; this is now the
full Gmail app following Erik's request for full work-service access.

Upstream curated queries and mutations are restored, and the complete Gmail
OpenAPI router is mounted under `api`. OAuth requests `https://mail.google.com/`
and `https://www.googleapis.com/auth/gmail.settings.basic`, with offline access.
Local tool approval prompts are disabled at Erik’s explicit request. Having access does not
authorize sending email or other communications without Erik approving the
specific message.

Framework `apps` is pinned to the installed host's 0.0.1-beta.95. Source passes a
strict TypeScript check. Connected 2026-11-10: Gmail profile and mail-search
calls through Executor succeeded after enabling the API and completing consent.
Credentials are stored by Executor, not in these files.

App ID remains `app_3f14b67d-055b-42b0-b48f-8db13e02a205`.
Setup: http://127.0.0.1:4788/apps/app_3f14b67d-055b-42b0-b48f-8db13e02a205/setup

Enable Gmail API in the Ablo Google Cloud project. Use the same Web application
OAuth client as Drive and the exact redirect URI
`http://127.0.0.1:4788/api/oauth/callback`. Connect the Gmail requirement separately
using Executor's secure form. Never put client secrets or tokens in source.
