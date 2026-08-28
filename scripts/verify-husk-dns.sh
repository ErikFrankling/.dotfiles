#!/usr/bin/env bash
# Verify the husk-security.dev split-DNS path end to end.
# See modules/nixos/husk-dns.nix for what each step is checking.
set -uo pipefail

fail=0
ok()   { printf '  \033[32mok\033[0m    %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }

echo "1. services"
systemctl is-active --quiet coredns        && ok "coredns running"        || bad "coredns not running"
systemctl is-active --quiet husk-dns-route && ok "husk-dns-route applied" || bad "husk-dns-route not applied"

echo "2. resolved routing"
if resolvectl domain huskdns 2>/dev/null | grep -q 'husk-security.dev'; then
  ok "huskdns carries ~husk-security.dev"
else
  bad "huskdns has no routing-only domain -- run: systemctl restart husk-dns-route"
fi
if resolvectl dns huskdns 2>/dev/null | grep -q '127.0.2.4'; then
  ok "huskdns points at the local resolver"
else
  bad "huskdns has no DNS server set"
fi
# Tailscale must still own everything else.
if resolvectl domain tailscale0 2>/dev/null | grep -q '~\.'; then
  ok "tailscale0 still holds the ~. default route (MagicDNS/AdGuard intact)"
else
  bad "tailscale0 lost its ~. default route"
fi

echo "3. resolution"
for host in analytics grafana prometheus admin auth hermes; do
  got=$(resolvectl query --legend=no "$host.husk-security.dev" 2>/dev/null | awk '/^'"$host"'/{print $2; exit}')
  [ "$got" = "10.0.127.250" ] && ok "$host -> $got" || bad "$host -> ${got:-<nothing>} (want 10.0.127.250)"
done
for host in staging auth-staging admin-staging grafana-staging analytics-staging; do
  got=$(resolvectl query --legend=no "$host.husk-security.dev" 2>/dev/null | awk '/^'"$host"'/{print $2; exit}')
  [ "$got" = "10.0.127.251" ] && ok "$host -> $got" || bad "$host -> ${got:-<nothing>} (want 10.0.127.251)"
done
# A name that does not exist yet must still resolve: that is the whole point.
got=$(resolvectl query --legend=no "not-deployed-yet.husk-security.dev" 2>/dev/null | awk '/^not-deployed-yet/{print $2; exit}')
[ "$got" = "10.0.127.250" ] && ok "unknown subdomain resolves without config changes" \
                            || bad "unknown subdomain -> ${got:-<nothing>}"

echo "4. public names untouched"
for host in husk-security.dev www.husk-security.dev; do
  got=$(resolvectl query --legend=no "$host" 2>/dev/null | awk '/^'"$host"'/{print $2; exit}')
  case "$got" in
    10.0.127.*) bad "$host hijacked to $got -- must stay public" ;;
    "")         bad "$host did not resolve" ;;
    *)          ok "$host -> $got (public)" ;;
  esac
done

echo "5. reachability over WARP"
warp-cli --accept-tos status 2>/dev/null | grep -q Connected && ok "WARP connected" || bad "WARP not connected"
for host in analytics grafana admin hermes; do
  code=$(curl -sS -o /dev/null -m 10 -w '%{http_code}' "https://$host.husk-security.dev/" 2>/dev/null)
  case "$code" in
    200|302) ok  "https://$host.husk-security.dev -> $code" ;;
    *)       bad "https://$host.husk-security.dev -> ${code:-no response}" ;;
  esac
done

echo
[ "$fail" -eq 0 ] && echo "all good" || echo "something is off -- see FAIL lines above"
exit "$fail"
