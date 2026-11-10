// Official Executor Gmail app, reduced to read-only OAuth and curated queries.
import { decodeJson, defineApp, defineProvider, oauth2, object, router, string } from "apps";
import { icons } from "./icon.js";
import { addresses } from "./tools/shared.js";
import { gmail as gmailTools } from "./tools/gmail.js";
const gmail = defineProvider({
  name: "Gmail (read-only)",
  hosts: ["gmail.googleapis.com"],
  auth: { oauth: oauth2({
    discover: "https://accounts.google.com",
    scopes: ["https://www.googleapis.com/auth/gmail.readonly"],
    authorizationParams: { access_type: "offline", prompt: "consent" },
  }) },
  async health({ account, fetch, signal }) {
    const response = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/profile", {
      signal, headers: { Authorization: `Bearer ${account.fields.access_token}` },
    });
    const me = await decodeJson(response, object({ emailAddress: string() }));
    return { accountInfo: { externalId: me.emailAddress, email: me.emailAddress } };
  },
});
export default defineApp({ user: { accounts: { gmail: gmail.many() } }, icons }, async ({ user }) => {
  const curated = gmailTools({ accounts: user?.accounts.gmail ?? [], address: addresses.gmail, api: () => "" });
  return { tools: router(curated.tools, { ...curated.meta, title: "Gmail (read-only)", icons }) };
});
