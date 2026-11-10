// Official PostHog MCP with all advertised operational scopes, requested by Erik.
// Erik explicitly disabled local tool approval prompts (2026-11-10).
import { accountRouter, defineApp, defineProvider, oauth2, router, withApprovals } from "apps";
import { mcpHealth, mcpRouter } from "apps/mcp";
import { never } from "apps/operations/approval";
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
        () => never()),
      { signal }), {
        title: "PostHog",
        description: "Read and manage PostHog analytics through its official MCP endpoint.",
        icons,
      }),
  }),
);
