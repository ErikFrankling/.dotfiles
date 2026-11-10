# Ablo connectors on the work laptop

Native Executor is at http://127.0.0.1:4788. Both installed Claude and Codex
launchers use its `/mcp` endpoint and the work API key supplied by SOPS. Personal
Executor accounts have not been copied here. Dashboard access uses native
one-use device pairing, not a password. Pairing must run with access to the
executor-work service's state directory; ask the setup agent for a fresh link.

Validated 2026-11-10: authenticated MCP initialize, tool listing, search and
`tools.executor.apps.list` succeeded. These checks verify the common endpoint
and API key; they do not establish access to any external work account.

| Integration | Installed | Remaining user step |
| --- | --- | --- |
| [Drive](google-drive-readonly/README.md) | Full Drive API; connected and file-list read verified | None |
| [Gmail](gmail-readonly/README.md) | Curated tools and full Gmail API; profile and mail search verified | None |
| [Linear](linear-readonly/README.md) | Official MCP, OAuth `read write`; connected and read verified | None |
| [PostHog](posthog-readonly/README.md) | Official MCP, operational read/write scopes; connected | None |
| Vercel | Official OAuth MCP connected; Ablo project read verified | None for MCP; separate API-token app remains unlinked |
| AWS | Native AWS CLI and `ablo` SSO session installed | SSO authentication, then account/role selection; AWS MCP not yet installed |
| 1Password vault access | `op` CLI working; native desktop Environments MCP configured in both harnesses | Desktop unlock/authorization when requested |

For Google, use an Ablo-owned Cloud project, enable **Google Drive API** and
**Gmail API**, configure Internal audience if available, and create a **Web
application** OAuth client with exactly
`http://127.0.0.1:4788/api/oauth/callback` as an authorized redirect. Enter client
credentials only into Executor's secure account forms. Connect each app's
account separately. The full apps use `drive`, `mail.google.com`, and
`gmail.settings.basic` scopes. The historical directory names are retained;
these apps are no longer read-only. Local tool approval prompts are disabled at Erik’s explicit request. Provider login/MFA requirements and the separate rule against unapproved human communication still apply.

The official Vercel MCP endpoint is `https://mcp.vercel.com`, connected using
Executor's native **Connect a service** form. It supports OAuth; the separate
Vercel API app requires a team-scoped token. Both enforce the team's 2FA
requirement. Do not substitute a personal team when work access is blocked.

Keep only one or two Executor dashboard tabs open. Each uses streaming
connections; enough tabs can exhaust Chromium's HTTP/1 per-origin connection
limit and make new pages stall while the server itself remains healthy.

AWS's official [AWS API MCP server](https://github.com/awslabs/mcp/tree/main/src/aws-api-mcp-server)
supports native `AWS_API_MCP_TRANSPORT=streamable-http`, loopback host/port,
`AWS_API_MCP_PROFILE_NAME`, and `READ_OPERATIONS_ONLY=true`. Use scoped IAM
permissions and an approved Ablo SSO profile. It needs a declarative Nix package
and service after the account configuration is supplied; no stdio-to-HTTP
wrapper is necessary. The catalog's AWS Marketplace app is not AWS account access.

For 1Password, sign into Ablo in the desktop app and enable **Settings > Developer
> Integrate with 1Password CLI**. Identify the permitted work vaults. Desktop
integration may require interactive unlock; unattended automation needs a
vault-scoped service account supplied through a secure secret prompt. The
catalog's 1Password app is Events Reporting (audit data), and the public
1Password developer MCP is documentation, neither provides vault access.
Vault access was verified. The Vercel item's authenticator and recovery codes
were saved in 1Password while enabling the team's required 2FA. The native
desktop MCP manages 1Password Environments; use `op` for vault items.

After each account is linked, verify a real read through Executor. Retrieve the
company security policy from Drive before drawing policy compliance conclusions.
Google and Vercel setup are complete. AWS SSO authentication remains on the
Needs-you list; no AWS credential was found in the accessible work vaults.
