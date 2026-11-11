import { defineProvider, oauth2 } from "apps"
import { mcpHealth } from "apps/mcp"

export const url = "https://mcp.eu.vanta.com/mcp"

/** The headers that send an account's token to the server. */
export const headers = (account: { fields: { access_token: string } }) => ({
  Authorization: "Bearer " + account.fields.access_token,
})

export const provider = defineProvider({
  name: "Vanta MCP",
  hosts: ["mcp.eu.vanta.com"],
  auth: {
    oauth: oauth2({
  "discover": "https://mcp.eu.vanta.com/mcp"
})
  },
  // Check an account by connecting to the server with it and listing its tools.
  health: (check) => mcpHealth(check, { url, headers: headers(check.account) }),
})
