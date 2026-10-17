---
name: phone-preview
description: Phone-reachable links for dev servers on Erik's PC. Load whenever you start a dev/preview server or give Erik a localhost / 127.0.0.1 / 0.0.0.0 URL (Vite, Next, Astro, Storybook, a static server, an API). Erik usually reads you from his phone over the VPN, where localhost links do not work; this explains the https://pc-<port>.erikfrankling.duckdns.org address that does.
---

# Phone previews of dev servers

Erik often drives agents from his phone (T3 Code over the home VPN). A
`http://localhost:5173` link is useless there. Every allowed loopback port on
the PC is also reachable from the LAN and the tailnet at:

```
https://pc-<port>.erikfrankling.duckdns.org
```

**When you give Erik a dev server URL, give both:**

```
Preview: http://localhost:5173
Phone:   https://pc-5173.erikfrankling.duckdns.org
```

Put the phone link first if he is clearly on mobile.

## Allowed ports

Only these ports are forwarded. Anything else returns 404 on purpose:

| Ports     | Typical server                             |
| --------- | ------------------------------------------ |
| 1234      | Parcel                                     |
| 1313      | Hugo                                       |
| 3000-3099 | Next, Remix, Rails, Express, most Node APIs |
| 4000-4099 | Phoenix, Jekyll                            |
| 4173      | `vite preview`                             |
| 4200      | Angular                                    |
| 4321      | Astro                                      |
| 5000-5199 | Flask, Vite (5173)                         |
| 6006      | Storybook                                  |
| 8080-8089 | webpack, Expo, generic                     |

If a server picked a port outside these ranges, restart it on an allowed one
(`--port 3001`, `PORT=3001`) rather than leaving Erik with a dead link. Do not
widen the list to make one server work. Loopback also holds Chromium's DevTools
(9222), the computer-use bridge (4790), Syncthing (8384) and more, and these
ranges are chosen to stay clear of them. Widening the list means editing
`~/.dotfiles/modules/nixos/dev-preview.nix` and this file together, and that
is Erik's call.

## What you do NOT need to do

- **Leave the server on localhost.** No `--host 0.0.0.0` and no firewall
  changes. The proxy connects to `localhost:<port>` on IPv4 or IPv6.
- **No host allowlists.** The proxy sends `Host: localhost:<port>` and rewrites
  `Origin`, so Vite's `allowedHosts`, Next's `allowedDevOrigins` and websocket
  (HMR) origin checks pass unchanged. Redirects to `localhost:<port>` are
  rewritten back to the phone URL.
- **No certificate work.** The page is real HTTPS with a valid certificate, so
  secure-context APIs (service workers, clipboard, camera) work on the phone.

## Things that can still break

- **Absolute `localhost` URLs inside the page.** Example: an app configured with
  `API_URL=http://localhost:8080`. The phone tries to reach its own localhost.
  Use relative URLs or the dev server's proxy. Otherwise point the variable at
  `https://pc-8080.erikfrankling.duckdns.org` for phone testing.
- **OAuth callbacks** registered as `http://localhost:<port>/...` will not
  return to the phone URL. Say so instead of guessing.
- **Cookies with `Secure`/`SameSite`** behave differently, because the phone is
  on HTTPS and the server thinks it is on plain HTTP at localhost. The proxy
  sends `X-Forwarded-Proto: https`.

- **Another project's favicon on the tab.** Browsers keep favicons per page
  URL and origin. A page that declares no icon, served by a server that 404s
  `/favicon.ico` (`python -m http.server`), shows whatever an earlier project on
  that port left behind. Example: the agent-company manifesto on
  `localhost:8081` showed the Neptune icon in Erik's Firefox, because NaiaClaw
  had run on 8081. When you serve a page that has no `<link rel="icon">`, add
  one, even `<link rel="icon" href="data:,">`. Also pick an uncommon port in the
  ranges above rather than the first default (8080, 8081, 3000, 5173).

## How it works (for debugging)

```
phone -> https://pc-5173.erikfrankling.duckdns.org
      -> DuckDNS wildcard: *.erikfrankling.duckdns.org = 192.168.50.100 (homelab VIP)
      -> Traefik on k3s: HostRegexp ^pc-[0-9]+\.erikfrankling\.duckdns\.org$,
         existing wildcard cert, lan-only (LAN + tailnet 100.64.0.0/10)
      -> PC 192.168.50.232:3999, Caddy (firewall admits only the k3s node/VIP)
      -> port read from the hostname, checked against the list above
      -> localhost:5173
```

- PC side: `~/.dotfiles/modules/nixos/dev-preview.nix` (Caddy `caddy.service`).
- Homelab side: `~/projects/personal/homelab/kubernetes/homelab/ingress/dev-preview.yaml`.
- Quick checks from the PC:
  - `curl -sI https://pc-5173.erikfrankling.duckdns.org` tests the full path.
  - `curl -sI -H 'Host: pc-5173.erikfrankling.duckdns.org' http://localhost:3999`
    tests Caddy alone.
- A 404 with "port not allowed" comes from Caddy: wrong or disallowed port. A
  502 means nothing is listening on that port. A 403 from Traefik means the
  client is not on the LAN or tailnet.
- The phone needs the home VPN (Tailscale) or home Wi-Fi. Nothing is public.

Only Erik's PC (`pc`) has this. On other machines, say the link is localhost-only.
