// Official PostHog MCP with all advertised operational scopes, requested by Erik.
// Keep upstream approval protection for non-read MCP tools.
import { accountRouter, defineApp, defineProvider, oauth2, router, toolAnnotations, withApprovals } from "apps";
import { mcpHealth, mcpRouter } from "apps/mcp";
import { always } from "apps/operations/approval";
import { icons } from "./icon.js";
import scopes from "./scopes.json" with { type: "json" };
const url = "https://mcp.posthog.com/mcp";
const headers = (account: { fields: { access_token: string } }) => ({ Authorization: `Bearer ${account.fields.access_token}` });
const posthog = defineProvider({
  name: "PostHog",
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
        title: "PostHog",
        description: "Read and manage PostHog analytics through its official MCP endpoint. Non-read tools retain upstream approval protection.",
        icons,
      }),
  }),
);
