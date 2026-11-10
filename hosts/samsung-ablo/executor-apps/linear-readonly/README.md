# Linear (read-only)

Adapted from https://catalog.executor.sh/apps/linear.json on 2026-11-10.
Uses Linear's official https://mcp.linear.app/mcp/readonly endpoint and explicitly
requests only OAuth scope `read`. The full GraphQL API and API-key alternative
are omitted. Reference: https://linear.app/docs/mcp.

Deployed on this laptop's native Executor beta24 / framework beta95:
`app_d5bfa251-b235-4ec7-aa47-725ebb49b4bb`.

Open http://127.0.0.1:4788/apps/app_d5bfa251-b235-4ec7-aa47-725ebb49b4bb/setup
and connect your Ablo Linear account. OAuth client registration is automatic;
no client ID/secret needs to be created. Select the Ablo workspace during
consent. Both Claude and Codex use the resulting local account connection.

Deployment and OAuth discovery passed; account consent and authenticated
Linear reads still require the user's sign-in.
