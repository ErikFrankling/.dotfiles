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
import { drive as driveTools } from "./tools/drive.js";
import { options } from "./openapi.js";

const About = object({ user: object({ permissionId: string(), displayName: string() }) });

const drive = defineProvider({
  name: "Google Drive",
  hosts: ["www.googleapis.com"],
  auth: {
    oauth: oauth2({
      discover: "https://accounts.google.com",
      scopes: ["https://www.googleapis.com/auth/drive"],
      // Google issues refresh tokens only when asked for offline access.
      authorizationParams: { access_type: "offline", prompt: "consent" },
    }),
  },
  async health({ account, fetch, signal }) {
    const response = await fetch(
      "https://www.googleapis.com/drive/v3/about?fields=user(permissionId,displayName)",
      { signal, headers: { Authorization: `Bearer ${account.fields.access_token}` } },
    );
    const { user } = await decodeJson(response, About);
    return { accountInfo: { externalId: user.permissionId, displayName: user.displayName } };
  },
});

export default defineApp(
  { user: { accounts: { drive: drive.many() } }, icons },
  async ({ user, cache, fetch, signal }) => {
    const curated = driveTools({ accounts: user?.accounts.drive ?? [], address: addresses.drive, api: () => "api" });
    return {
      tools: router(
        {
          ...curated.tools,
          api: router(
            await accountRouter(
              user?.accounts.drive ?? [],
              (account) =>
                withApprovals(liveOpenapiRouter({ ...options, cache, fetch, signal, account }), (tool) =>
                  tool.kind === "mutation" ? always() : undefined,
                ),
              { signal },
            ),
            {
              title: "Google Drive API",
              description: "The complete Google Drive API, per account: every tool takes accountId and the API's own input.",
            },
          ),
        },
        {
          instructions: curated.meta.instructions,
          title: "Google Drive",
          description:
            "Files, folders, shared drives, permissions, comments, revisions and changes in Google Drive.",
          icons,
        },
      ),
    };
  },
);
