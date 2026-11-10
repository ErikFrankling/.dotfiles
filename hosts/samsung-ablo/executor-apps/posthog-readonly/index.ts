// Official Executor PostHog adapter, OAuth-only with the server's advertised
// read scopes. Keep upstream approval protection for non-read MCP tools.
import { accountRouter, defineApp, defineProvider, oauth2, router, toolAnnotations, withApprovals } from "apps";
import { mcpHealth, mcpRouter } from "apps/mcp";
import { always } from "apps/operations/approval";
import { icons } from "./icon.js";
import scopes from "./scopes.json" with { type: "json" };
const url = "https://mcp.posthog.com/mcp";
const headers = (account: { fields: { access_token: string } }) => ({ Authorization: `Bearer ${account.fields.access_token}` });
const posthog = defineProvider({
  name: "PostHog (read scopes)",
  hosts: ["mcp.posthog.com", "oauth.posthog.com"],
  auth: { oauth: oauth2({ discover: url, scopes, tokenEndpointAuthMethod: "none" }) },
  health: (check) => mcpHealth(check, { url, headers: headers(check.account) }),
});
export default defineApp({ user: { accounts: { posthog: posthog.many() } }, icons },
  async ({ user, cache, signal }) => ({
    tools: router(await accountRouter(user?.accounts.posthog ?? [], async (account) =>
      withApprovals(await mcpRouter({ url, account, headers: headers(account), cache, signal }),
        (tool) => toolAnnotations(tool)?.readOnlyHint === true ? undefined : always()),
      { signal }), {
        title: "PostHog (read scopes)",
        description: "PostHog analytics with read-only OAuth scopes. Provider permission checks enforce read access; upstream non-read tools still require approval.",
        icons,
      }),
  }),
);
