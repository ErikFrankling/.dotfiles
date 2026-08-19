// Patches applied to T3 Code's server bundle at build time. Each replacement is
// guarded by name: when upstream moves the code out from under one, the build
// fails and says which patch to re-derive, instead of silently dropping it.
//
// Run by the t3code-unwrapped override in flake.nix with T3CODE_BUNDLE set.

const fs = require("fs");

const bundlePath = process.env.T3CODE_BUNDLE;
let source = fs.readFileSync(bundlePath, "utf8");

function replaceOnce(before, after, description) {
  const count = source.split(before).length - 1;
  if (count !== 1) {
    throw new Error(
      `T3 patch "${description}" matched ${count} times, expected 1`,
    );
  }
  source = source.replace(before, after);
}

// Codex speaks strict JSON-RPC 2.0 and rejects messages without the envelope
// field; T3 omits it on responses, requests, and notifications alike.
replaceOnce(
  'const toProtocolMessage = (requestId, fields) => ({\n\tid: requestId,',
  'const toProtocolMessage = (requestId, fields) => ({\n\tjsonrpc: "2.0",\n\tid: requestId,',
  "Codex JSON-RPC response envelope",
);
replaceOnce(
  '\t\tyield* offerOutgoing({\n\t\t\tid: requestId,\n\t\t\tmethod,',
  '\t\tyield* offerOutgoing({\n\t\t\tjsonrpc: "2.0",\n\t\t\tid: requestId,\n\t\t\tmethod,',
  "Codex JSON-RPC request envelope",
);
replaceOnce(
  '\tconst notify = (method, payload) => offerOutgoing({\n\t\tmethod,',
  '\tconst notify = (method, payload) => offerOutgoing({\n\t\tjsonrpc: "2.0",\n\t\tmethod,',
  "Codex JSON-RPC notification envelope",
);

// T3's auth contract has an `unsafe-no-auth` policy but never implements it.
// With T3CODE_UNSAFE_NO_AUTH=1, a request carrying no credential -- or a stale
// one, so browsers holding a cookie from an earlier pairing are not locked out
// -- resolves to a fully scoped session instead of a 401. The fallback goes
// through a real session row (subject `no-auth`, reused across restarts), so
// websocket tickets and the access UI keep working. Unset, the server behaves
// exactly as upstream, which is why this is safe to carry for every host.
replaceOnce(
  "\tconst authenticateRequest = (request) => {\n\t\tconst cookieToken = request.cookies[sessions.cookieName];",
  "\tconst authenticateRequestStrict = (request) => {\n\t\tconst cookieToken = request.cookies[sessions.cookieName];",
  "no-auth: rename the strict path",
);
replaceOnce(
  "\tconst getSessionState = (request) => authenticateRequest(request).pipe(",
  `const noAuthEnabled = process.env.T3CODE_UNSAFE_NO_AUTH === "1";
let noAuthPrincipal = null;
const loadNoAuthSession = Effect.gen(function* () {
	const active = yield* sessions.listActive();
	const existing = active.find((session) => session.subject === "no-auth");
	const session = existing ?? (yield* sessions.issue({
		method: "browser-session-cookie",
		subject: "no-auth",
		scopes: AuthAdministrativeScopes,
		client: { deviceType: "unknown", label: "unauthenticated LAN access" },
		ttl: Duration.days(3650)
	}));
	noAuthPrincipal = {
		sessionId: session.sessionId,
		subject: session.subject ?? "no-auth",
		method: session.method,
		scopes: session.scopes,
		...session.expiresAt ? { expiresAt: session.expiresAt } : {}
	};
	return noAuthPrincipal;
}).pipe(mapSessionVerificationErrors);
const noAuthSession = Effect.suspend(() => noAuthPrincipal === null ? loadNoAuthSession : Effect.succeed(noAuthPrincipal));
const authenticateRequest = noAuthEnabled ? (request) => authenticateRequestStrict(request).pipe(Effect.catchIf(isServerAuthCredentialError, () => noAuthSession)) : authenticateRequestStrict;
\tconst getSessionState = (request) => authenticateRequest(request).pipe(`,
  "no-auth: unauthenticated fallback",
);

fs.writeFileSync(bundlePath, source);
console.log(`t3code: patched ${bundlePath}`);
