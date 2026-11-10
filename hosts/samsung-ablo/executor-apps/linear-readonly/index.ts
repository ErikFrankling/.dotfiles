// Adapted from the official Executor Linear app. Only Linear's read-only MCP
// is exposed; the full GraphQL API and API-key alternative are omitted.
import { accountRouter, defineApp, defineProvider, oauth2, router } from "apps";
import { mcpHealth, mcpRouter } from "apps/mcp";
import { icons } from "./icon.js";

const url = "https://mcp.linear.app/mcp/readonly";
const headers = (account: { fields: { access_token: string } }) => ({
  Authorization: `Bearer ${account.fields.access_token}`,
});
const linear = defineProvider({
  name: "Linear (read-only)",
  hosts: ["mcp.linear.app"],
  auth: { oauth: oauth2({ discover: url, scopes: ["read"] }) },
  health: (check) => mcpHealth(check, { url, headers: headers(check.account) }),
});
export default defineApp(
  { user: { accounts: { linear: linear.many() } }, icons },
  async ({ user, cache, signal }) => ({
    tools: router(
      await accountRouter(user?.accounts.linear ?? [],
        (account) => mcpRouter({ url, account, headers: headers(account), cache, signal }),
        { signal }),
      { title: "Linear (read-only)", description: "Read Linear issues, projects and documents through its official read-only MCP endpoint.", icons },
    ),
  }),
);
