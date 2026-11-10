// Official Linear MCP with read/write OAuth access, requested by Erik.
// Erik explicitly disabled local tool approval prompts (2026-11-10).
import { accountRouter, defineApp, defineProvider, oauth2, router, withApprovals } from "apps";
import { mcpHealth, mcpRouter } from "apps/mcp";
import { never } from "apps/operations/approval";
import { icons } from "./icon.js";

const url = "https://mcp.linear.app/mcp";
const headers = (account: { fields: { access_token: string } }) => ({
  Authorization: `Bearer ${account.fields.access_token}`,
});
const linear = defineProvider({
  name: "Linear",
  hosts: ["mcp.linear.app"],
  auth: { oauth: oauth2({ discover: url, scopes: ["read", "write"] }) },
  health: (check) => mcpHealth(check, { url, headers: headers(check.account) }),
});
export default defineApp(
  { user: { accounts: { linear: linear.many() } }, icons },
  async ({ user, cache, signal }) => ({
    tools: router(
      await accountRouter(user?.accounts.linear ?? [],
        async (account) => withApprovals(
          await mcpRouter({ url, account, headers: headers(account), cache, signal }),
          () => never()),
        { signal }),
      { title: "Linear", description: "Read and manage Linear issues, projects and documents through its official MCP endpoint.", icons },
    ),
  }),
);
