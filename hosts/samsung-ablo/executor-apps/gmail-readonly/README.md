# Gmail (read-only)

Adapted from https://catalog.executor.sh/apps/gmail.json on 2026-11-10. Exposes
only search, readThread, readMessage, labels and attachment queries; send,
draft and modify tools are removed. Scope is `gmail.readonly` only.

Deployed app: `app_3f14b67d-055b-42b0-b48f-8db13e02a205`.
Setup: http://127.0.0.1:4788/apps/app_3f14b67d-055b-42b0-b48f-8db13e02a205/setup

Use the same Ablo-owned Google Cloud Web application OAuth client as Drive.
Enable **Gmail API** in addition to Drive API. Authorized redirect URI:
`http://127.0.0.1:4788/api/oauth/callback`. Connect the Gmail account separately
and consent to `https://www.googleapis.com/auth/gmail.readonly`. Client details
belong in Executor's secure form, never source or chat. Authentication remains
pending user consent; deployment alone does not give mailbox access.
