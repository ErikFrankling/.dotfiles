import {
  accountRouter,
  decodeJson,
  defineApp,
  defineProvider,
  oauth2,
  object,
  router,
  string,
  withApprovals,
} from "apps";
import { always } from "apps/operations/approval";
import { liveOpenapiRouter } from "apps/openapi";
import { icons } from "./icon.js";
import { addresses } from "./tools/shared.js";
import { gmail as gmailTools } from "./tools/gmail.js";
import { options } from "./openapi.js";

const Profile = object({ emailAddress: string() });

const gmail = defineProvider({
  name: "Gmail",
  hosts: ["gmail.googleapis.com"],
  auth: {
    // Google offers no client registration: the connect page asks for an OAuth client.
    oauth: oauth2({
      discover: "https://accounts.google.com",
      scopes: [
        "https://mail.google.com/",
        "https://www.googleapis.com/auth/gmail.settings.basic",
      ],
      // Google issues refresh tokens only when asked for offline access.
      authorizationParams: { access_type: "offline", prompt: "consent" },
    }),
  },
  async health({ account, fetch, signal }) {
    const response = await fetch("https://gmail.googleapis.com/gmail/v1/users/me/profile", {
      signal,
      headers: { Authorization: `Bearer ${account.fields.access_token}` },
    });
    const me = await decodeJson(response, Profile);
    return { accountInfo: { externalId: me.emailAddress, email: me.emailAddress } };
  },
});

export default defineApp(
  { user: { accounts: { gmail: gmail.many() } }, icons },
  async ({ user, cache, fetch, signal }) => {
    const curated = gmailTools({ accounts: user?.accounts.gmail ?? [], address: addresses.gmail, api: () => "api" });
    return {
      tools: router(
        {
          ...curated.tools,
          api: router(
            await accountRouter(
              user?.accounts.gmail ?? [],
              (account) =>
                withApprovals(liveOpenapiRouter({ ...options, cache, fetch, signal, account }), (tool) =>
                  tool.kind === "mutation" ? always() : undefined,
                ),
              { signal },
            ),
            {
              title: "Gmail API",
              description: "The complete Gmail API, per account: every tool takes accountId and the API's own input.",
            },
          ),
        },
        {
          instructions: curated.meta.instructions,
          title: "Gmail",
          description:
            "Read, search, send and organize Gmail messages, threads, drafts, labels, filters and settings.",
          icons,
        },
      ),
    };
  },
);
