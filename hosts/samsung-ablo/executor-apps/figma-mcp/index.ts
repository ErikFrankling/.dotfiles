import { defineApp, accountRouter, withApprovals } from "apps"
import { mcpRouter } from "apps/mcp"
import { never } from "apps/operations/approval"
import { headers, provider, url } from "./provider.ts"

// Official Figma remote MCP. Each member links their own Figma account.
// Erik explicitly disabled local tool approval prompts (2026-11-10).
export default defineApp({ user: { accounts: { figma: provider.many() } } }, async ({ user, signal, cache }) => ({
  tools: await accountRouter(user?.accounts.figma ?? [], async (account) => withApprovals(await mcpRouter({
    url,
    account,
    cache,
    headers: headers(account),
    signal,
  }),
    () => never(),
  ), { signal }),
}))
