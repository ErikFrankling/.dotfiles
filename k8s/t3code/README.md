# T3 Code — HTTPS, no auth

Public-feeling URL with real Let's Encrypt TLS and **no authentication at all**:
no pairing code, no login, no bearer token. Anyone who can reach the host gets a
full agent with shell access as `erikf` on `pc`, so this only holds up because
the name resolves to a LAN/VPN address (192.168.50.100) and is never exposed to
the internet.

## Access
- URL: https://t3code.erikfrankling.duckdns.org/ — open it, you're in.

Resolves via the existing wildcard `*.erikfrankling.duckdns.org -> 192.168.50.100`
(Traefik LB) on the LAN/VPN, same as p9eval. If a device can't resolve it, add a
hosts entry:  `192.168.50.100 t3code.erikfrankling.duckdns.org`

Direct backend, no TLS: http://192.168.50.232:3773/ — equally unauthenticated.

## How it works
Browser --(HTTPS, LE wildcard cert)--> Traefik (k3s, 192.168.50.100)
  -> Service t3code-backend    (EndpointSlice -> 192.168.50.232:3773)
     = the 't3 serve' backend (systemd user unit, host 'pc')

The backend runs with `T3CODE_UNSAFE_NO_AUTH=1` (see `hosts/pc/home.nix`). T3 has
no such flag upstream, so the unit's `t3` build carries a patch: with the
variable set, a request with no credential — or with a stale cookie from an
earlier pairing — resolves to a long-lived, fully scoped session instead of a
401. That session is a real row in T3's auth DB (subject `no-auth`), reused
across restarts, so websocket tickets and the Access settings page keep working.
Without the variable the build behaves exactly like upstream.

## Turning auth back on
1. Drop `T3CODE_UNSAFE_NO_AUTH=1` from `systemd.user.services.t3code` in
   `hosts/pc/home.nix`, rebuild, restart the unit.
2. Revoke the leftover session: `t3 auth session list` / `t3 auth session revoke`.
3. Pair each browser once, or put a Traefik basicAuth middleware back in front —
   the removed manifests are in git history (`30-middleware-basicauth.yaml`,
   `31-middleware-injectbearer.EXAMPLE.yaml`).

## Files (apply with: kubectl apply -f <file>)
- 10-backend-service.yaml   Service + EndpointSlice -> 192.168.50.232:3773
- 20-certificate.yaml       LE wildcard cert (cert-manager, duckdns DNS-01)
- 40-ingressroute.yaml      Traefik IngressRoute, host + TLS, no middleware

## Cluster bootstrap done once (not in these files)
- helm repo add duckdns https://csp33.github.io/cert-manager-duckdns-webhook
- helm install cert-manager-duckdns-webhook (namespace cert-manager) -> ClusterIssuers
  duckdns-letsencrypt-prod / -staging, using the existing kube-system/duckdns-acme token.

## Updating T3 itself
`hosts/pc/home.nix` pins the npm artifact (`t3Version`) instead of following
`inputs.t3code-nix`, which is stuck on 0.0.25. To bump:

1. `curl -s https://registry.npmjs.org/t3 | jq -r .dist-tags.latest`
2. Set `t3Version` + the `src` hash (npm's `dist.integrity` is already SRI:
   `curl -s https://registry.npmjs.org/t3/<version> | jq -r .dist.integrity`)
3. Regenerate `hosts/pc/t3-npm/`: unpack the tarball, delete the `overrides`
   block from `package.json` (pnpm syntax, npm rejects it), run
   `npm install --package-lock-only --ignore-scripts`, copy both files over
4. `rebuild` — the bundle patches throw by name if upstream moved out from
   under them, which is the signal to re-derive that specific patch
