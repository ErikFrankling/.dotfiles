# Google Drive (read-only)

Minimal adaptation of the official Executor Google Drive app fetched from
https://catalog.executor.sh/apps/google-drive.json on 2026-11-10.

Top-level `search` and `read` are unchanged upstream tools. The vendored OpenAPI
schema exposes 26 GET operations only; mutation methods and the ID/token
creation endpoints are absent. OAuth requests only
`https://www.googleapis.com/auth/drive.readonly`, with offline access for refresh
tokens. This permits reading files the signed-in account can access, including
exports, metadata, comments and revisions; it does not permit editing or sharing.

Create a Google Cloud OAuth client of type **Web application**, enable Google
Drive API, and add the exact redirect URI shown by this local Executor's
connection page. Enter client credentials in that page, never in source or chat.
For the organization's own users, use an Internal consent audience if available.
External applications in Testing can have refresh-token lifetime restrictions.

The upstream dependency is `apps` 0.0.1-beta.95. Deployment compatibility must be
validated on the installed Executor. After any upstream refresh, retain the
read-only OAuth scope and GET-only schema before deploying.

Reading a Sheet through the curated tool exports only its first sheet; binary
files return metadata/link instead of extracted text. No account is connected
by these source files alone.

## This laptop

Deployed and built successfully on native Executor 2.0.0-beta.24, framework
0.0.1-beta.95. App ID: `app_660e5f3c-0fc4-4f0e-9f95-b0006664fa7a`.
Dashboard: http://127.0.0.1:4788/apps/app_660e5f3c-0fc4-4f0e-9f95-b0006664fa7a/setup

Google OAuth setup for this origin:

1. In an Ablo-owned Google Cloud project, enable **Google Drive API**.
2. Configure Google Auth Platform audience as **Internal** for Ablo's Workspace
   organization when available.
3. Create a **Web application** OAuth client. Add exactly this authorized
   redirect URI: `http://127.0.0.1:4788/api/oauth/callback`.
4. In the local Executor app's account connection form, enter the client ID
   and client secret, then sign in with the Ablo Google account and consent to
   the read-only Drive scope. Do not save these credentials in this repository.

The local server has no saved Google OAuth clients yet. Deployment alone does
not grant Drive access. After signing in, verify a read-only search retrieves
the company security policy. Both Claude and Codex use this same local app.
