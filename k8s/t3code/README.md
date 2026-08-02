# T3 Code — HTTPS + admin/password access

Public-feeling URL, real Let's Encrypt TLS, and a normal login instead of the
per-browser pairing code.

## Access
- URL:  https://t3code.erikfrankling.duckdns.org/
- User: admin
- Pass: (see .credentials.env — store it in your password manager)

Resolves via the existing wildcard `*.erikfrankling.duckdns.org -> 192.168.50.100`
(Traefik LB) on the LAN/VPN, same as p9eval. If a device can't resolve it, add a
hosts entry:  `192.168.50.100 t3code.erikfrankling.duckdns.org`

## How it works
Browser --(HTTPS, LE wildcard cert)--> Traefik (k3s, 192.168.50.100)
  -> Middleware t3code-basic-auth   (admin/password gate; strips Basic creds)
  -> Middleware t3code-inject-bearer(adds 'Authorization: Bearer <t3 session>')
  -> Service t3code-backend         (EndpointSlice -> 192.168.50.232:3773)
     = the 't3 serve' backend (systemd user unit, host 'pc')

The injected bearer is a 1-year session token from 't3 auth session issue', so the
proxy authenticates to the backend for you. If the T3 web client still shows its
pairing screen (it may gate on local state), pair that browser ONCE with the
long-lived link below — it lasts a year and then never nags again.

Fallback pair link: http://192.168.50.232:3773/pair#token=BLNMQP596J5H

## Change the admin password
NEWPASS=<your-new-pass>
HASH=$(mkpasswd -m bcrypt "$NEWPASS")
kubectl -n t3code create secret generic t3code-basic-auth \
  --from-literal=users="admin:$HASH" --dry-run=client -o yaml | kubectl apply -f -

## Rotate the injected bearer
t3 auth session issue --ttl 365d --token-only    # then update the inject-bearer middleware
t3 auth session list / revoke                    # manage tokens

## Files (apply with: kubectl apply -f <file>)
- 10-backend-service.yaml   Service + EndpointSlice -> 192.168.50.232:3773
- 20-certificate.yaml       LE wildcard cert (cert-manager, duckdns DNS-01)
- 30-middleware-basicauth.yaml
- 31-middleware-injectbearer.EXAMPLE.yaml  (real token applied imperatively; not in git)
- 40-ingressroute.yaml      Traefik IngressRoute, host + TLS + middleware chain

## Cluster bootstrap done once (not in these files)
- helm repo add duckdns https://csp33.github.io/cert-manager-duckdns-webhook
- helm install cert-manager-duckdns-webhook (namespace cert-manager) -> ClusterIssuers
  duckdns-letsencrypt-prod / -staging, using the existing kube-system/duckdns-acme token.
