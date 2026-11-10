# Google Drive

Official Executor catalog app from
https://catalog.executor.sh/apps/google-drive.json, refreshed 2026-11-10.
The historical directory name is retained; this is now the full Drive app,
following Erik's request for full work-service access.

The complete upstream Drive v3 OpenAPI document and its generator are included.
Curated `search` and `read` tools remain available, with all imported API
operations under `api`. OAuth requests `https://www.googleapis.com/auth/drive`
and offline access. Imported mutations retain upstream Executor approval prompts.
Access capability does not authorize sharing files, editing shared documents,
or communicating with people without Erik's explicit approval.

The package pins the installed host framework, `apps` 0.0.1-beta.95. Source
passes a strict TypeScript check and deploys on native Executor 2.0.0-beta.24.

App ID remains `app_660e5f3c-0fc4-4f0e-9f95-b0006664fa7a`.
Setup: http://127.0.0.1:4788/apps/app_660e5f3c-0fc4-4f0e-9f95-b0006664fa7a/setup

Google Cloud needs an Ablo-owned Web application OAuth client with the exact
redirect URI `http://127.0.0.1:4788/api/oauth/callback`, Google Drive API enabled,
and an Internal consent audience when available. Enter client credentials only
in Executor's secure connection form. No credentials belong in this repository.
Google Cloud currently requires fresh user verification; no Google account is
linked yet. Deployment alone does not grant access. After consent, verify a
read-only search before claiming the connection is working.
