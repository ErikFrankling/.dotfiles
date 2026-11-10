import {
  ProviderError,
  accountRouter,
  decodeJson,
  defineApp,
  defineProvider,
  object,
  router,
  secrets,
  string,
  withApprovals,
} from "apps";
import { never } from "apps/operations/approval";
import { liveOpenapiRouter } from "apps/openapi";
import { icons } from "./icon.js";
import { options } from "./openapi.js";

const User = object({ id: string(), username: string(), email: string() });

const vercel = defineProvider({
  name: "Vercel",
  hosts: ["api.vercel.com"],
  auth: {
    apiKey: secrets({
      label: "Access token",
      fields: object({ token: string({ minLength: 1 }) }),
    }),
  },
  async health({ account, fetch, signal }) {
    const response = await fetch("https://api.vercel.com/v2/user", {
      signal,
      headers: { Authorization: `Bearer ${account.fields.token}` },
    });
    // Vercel answers an unknown or revoked token with 403 and `invalidToken: true`.
    if (response.status === 403 && (await response.clone().json()).error?.invalidToken === true)
      throw new ProviderError({ reason: "unauthorized", status: 403 });
    const { user } = await decodeJson(response, object({ user: User }));
    return {
      accountInfo: {
        externalId: user.id,
        username: user.username,
        email: user.email,
      },
    };
  },
});

export default defineApp(
  { user: { accounts: { vercel: vercel.many() } }, icons },
  async ({ user, cache, fetch, signal }) => ({
    tools: router(
      await accountRouter(
        user?.accounts.vercel ?? [],
        (account) =>
          withApprovals(liveOpenapiRouter({ ...options, cache, fetch, signal, account }), () => never(),
          ),
        { signal },
      ),
      {
        title: "Vercel",
        description: "Projects, deployments, domains, environment variables, teams and the rest of the Vercel API.",
        instructions:
          "Most endpoints act on the token's personal scope unless you pass teamId (or slug). List teams first when the user names a team.",
        icons,
      },
    ),
  }),
);
