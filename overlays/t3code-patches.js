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
  // Replace through a function so `$` sequences in `after` -- `succeed$1` and
  // friends -- are inserted literally rather than read as replacement patterns.
  source = source.replace(before, () => after);
}

// The bundle tree-shakes `effect` into flat, renamed top-level imports, and
// those names drift between releases: 0.0.34 dropped the `Effect` and `Duration`
// namespaces the injected code below used to call through, which the call-site
// anchors could not notice -- the build stayed green and the server died at
// boot with `ReferenceError: Effect is not defined`. So assert up front that
// every binding the injected code borrows from the bundle is still bound.
//
// Imports and locals are checked separately, because accepting either form hid
// a second boot failure: 0.0.40 renamed effect's `gen` to `gen$1` and, in the
// same release, bundled stream-chain, whose own top-level `const gen` satisfied
// a guard that accepted any declaration. The injected code then called
// stream-chain's gen and died at boot with `gen(...).pipe is not a function`.
// An effect combinator must come from the import list and must not be shadowed;
// a module local must be declared in the bundle.
function escapeName(name) {
  return name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function requireImport(name) {
  const escaped = escapeName(name);
  if (!new RegExp(`\\bas ${escaped}\\s*[,}]`).test(source)) {
    throw new Error(
      `T3 patch: bundle no longer imports effect's "${name}"; re-derive the no-auth patch`,
    );
  }
  // A top-level declaration of the same name shadows the import for the whole
  // module, which is exactly how the gen/gen$1 breakage reached runtime.
  if (new RegExp(`^(?:const|let|var|function)\\s+${escaped}\\b`, "m").test(source)) {
    throw new Error(
      `T3 patch: "${name}" is shadowed by a top-level declaration in the bundle; ` +
        `use the effect import's actual alias instead`,
    );
  }
}

function requireLocal(name) {
  const escaped = escapeName(name);
  if (!new RegExp(`^(?:const|let|var|function)\\s+${escaped}\\b`, "m").test(source)) {
    throw new Error(
      `T3 patch: bundle no longer declares "${name}"; re-derive the no-auth patch`,
    );
  }
}

// effect combinators, borrowed from the bundle's flattened import list.
["gen$1", "suspend", "succeed$1", "catchIf", "days"].forEach(requireImport);

// auth-module locals the fallback reuses.
[
  "mapSessionVerificationErrors",
  "isServerAuthCredentialError",
  "AuthAdministrativeScopes",
  "selectRequestCredential",
].forEach(requireLocal);

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
  "\tconst authenticateRequest = (request) => {\n\t\tconst credential = selectRequestCredential(request, sessions.cookieName, sessions.legacyCookieName);",
  "\tconst authenticateRequestStrict = (request) => {\n\t\tconst credential = selectRequestCredential(request, sessions.cookieName, sessions.legacyCookieName);",
  "no-auth: rename the strict path",
);
replaceOnce(
  "\tconst getSessionState = (request) => authenticateRequest(request).pipe(",
  `const noAuthEnabled = process.env.T3CODE_UNSAFE_NO_AUTH === "1";
let noAuthPrincipal = null;
const loadNoAuthSession = gen$1(function* () {
	const active = yield* sessions.listActive();
	const existing = active.find((session) => session.subject === "no-auth");
	const session = existing ?? (yield* sessions.issue({
		method: "browser-session-cookie",
		subject: "no-auth",
		scopes: AuthAdministrativeScopes,
		client: { deviceType: "unknown", label: "unauthenticated LAN access" },
		ttl: days(3650)
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
const noAuthSession = suspend(() => noAuthPrincipal === null ? loadNoAuthSession : succeed$1(noAuthPrincipal));
const authenticateRequest = noAuthEnabled ? (request) => authenticateRequestStrict(request).pipe(catchIf(isServerAuthCredentialError, () => noAuthSession)) : authenticateRequestStrict;
\tconst getSessionState = (request) => authenticateRequest(request).pipe(`,
  "no-auth: unauthenticated fallback",
);

fs.writeFileSync(bundlePath, source);
console.log(`t3code: patched ${bundlePath}`);
