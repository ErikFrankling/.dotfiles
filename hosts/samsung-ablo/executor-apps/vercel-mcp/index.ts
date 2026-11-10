import { defineApp, accountRouter, withApprovals } from "apps"
import { mcpRouter } from "apps/mcp"
import { never } from "apps/operations/approval"
import { headers, provider, url } from "./provider.ts"

// Each member links their own accounts, and each tool takes the account to use.
export default defineApp({ user: { accounts: { service: provider.many() } } }, async ({ user, signal, cache }) => ({
  tools: await accountRouter(user?.accounts.service ?? [], async (account) => withApprovals(await mcpRouter({
    url,
    account,
    cache,
    headers: headers(account),
    signal,
  }),
    // Erik explicitly disabled local tool approval prompts (2026-11-10).
    () => never(),
  ), { signal }),
}))
