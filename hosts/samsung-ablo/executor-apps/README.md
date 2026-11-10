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
| [Drive](google-drive-readonly/README.md) | Read-only app; GET-only API schema | Ablo Google OAuth client and Drive consent |
| [Gmail](gmail-readonly/README.md) | Read-only search/message/thread/attachment/labels queries | Same Google client, Gmail API enabled, Gmail consent |
| [Linear](linear-readonly/README.md) | Official read-only endpoint, OAuth `read` | Sign in and consent to Ablo workspace |
| [PostHog](posthog-readonly/README.md) | Official MCP, advertised read scopes only | Sign in and select Ablo project |
| AWS | Not installed/authenticated | Ablo SSO start URL, SSO region, account/role, workload region |
| 1Password vault access | `op` CLI installed; account list empty | Ablo account and allowed vault access |

For Google, use an Ablo-owned Cloud project, enable **Google Drive API** and
**Gmail API**, configure Internal audience if available, and create a **Web
application** OAuth client with exactly
`http://127.0.0.1:4788/api/oauth/callback` as an authorized redirect. Enter client
credentials only into Executor's secure account forms. Connect each app's
account separately. Scopes are `drive.readonly` and `gmail.readonly`.

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
No vault contents were read for this setup.

After each account is linked, verify a real read through Executor. Retrieve the
company security policy from Drive before drawing policy compliance conclusions.
The Needs-you list contains `ablo-google-drive-oauth`, `ablo-linear-oauth`,
`ablo-posthog-oauth`, and `ablo-aws-1password-access` for the remaining actions.
