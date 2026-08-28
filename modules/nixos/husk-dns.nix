{
  config,
  lib,
  pkgs,
  ...
}:

# Split-DNS for the WARP-private Husk applications.
#
# The problem this solves
# -----------------------
# *.husk-security.dev has no public DNS. The names exist only inside
# Cloudflare Gateway, as an "override" resolver policy that rewrites an
# explicit list of FQDNs to the private ingress VIPs
# (husk_platform/deploy/tofu/modules/cloudflare/private_access.tf). Reaching
# that policy requires the WARP client to own DNS (WarpWithDnsOverHttps), and
# on this laptop it deliberately does not: Tailscale owns DNS here, so WARP
# runs in tunnelonly mode (see ./desktop.nix). The tunnel still carries the
# traffic -- the split-tunnel include list routes 10.0.127.250/.251 -- but
# nothing on the host can turn a hostname into one of those IPs.
#
# The previous plan was to have AdGuard (the tailnet's global resolver at
# 192.168.50.100) publish rewrites for these names. That path is three hops
# long -- resolved -> tailscale0 -> AdGuard over a subnet route -> rewrite --
# and every hop fails to NXDOMAIN rather than to an error, so a suspend/resume
# or an AdGuard blip silently breaks the dashboards. It also means every new
# subdomain has to be added by hand in a second place.
#
# What this does instead
# ----------------------
# Answer the names on the laptop itself, by rule rather than by list. A local
# CoreDNS serves the husk-security.dev zone with two regex templates: anything
# *-staging goes to the staging ingress, anything else goes to production. A
# brand-new subdomain therefore resolves the day it is deployed, with no edit
# here and no Terraform round-trip. The apex and www are explicitly *not*
# claimed -- they are the real public site -- so they keep resolving through
# the normal path.
#
# systemd-resolved is pointed at it for husk-security.dev only, via a
# routing-only domain on a dedicated dummy link. Nothing else changes:
# Tailscale keeps its '~.' default route (so MagicDNS and AdGuard ad-blocking
# are untouched), and WARP keeps its hands off port 53. resolved prefers the
# most specific matching domain, and "husk-security.dev" (two labels) beats
# Tailscale's zero-label '~.', so only these names are diverted.
#
# Security posture is unchanged. Resolution is not access: the Gateway L4
# policy that gates TCP 443 to the ingress VIPs is IP-based and identity-bound
# to the enrolled WARP device, so this makes names resolvable, not apps
# reachable. With WARP down the names still resolve and the connection simply
# fails -- loudly, at connect time, rather than as a confusing NXDOMAIN.

let
  # The private HTTPS ingress VIPs, from the tofu variables of the same name.
  # These are the two /32s in the WARP split-tunnel include list; keep them in
  # step with private_ingress_prod_ip / private_ingress_staging_ip.
  prodIngress = "10.0.127.250";
  stagingIngress = "10.0.127.251";

  # A loopback address of our own. 127.0.0.53/.54 belong to systemd-resolved
  # and 127.0.2.2/.3 to warp-svc, so this cannot collide with either even if
  # WARP is later switched back to a DNS-owning mode.
  listenAddress = "127.0.2.4";

  # Names that must keep resolving publicly. CoreDNS matches the longest
  # server block, so a block for a more specific name wins over the zone
  # below it. The apex needs no entry: it falls through the templates (which
  # only match names that have a label in front of husk-security.dev) to the
  # forwarder at the end of its block.
  publicNames = [ "www.husk-security.dev" ];

  # Upstream for the names we deliberately do not claim (the apex and www).
  #
  # This must NOT be either of resolved's own stubs. 127.0.0.53 is the obvious
  # loop, but 127.0.0.54 loops too: despite being the "proxy" stub it still
  # applies routing domains, so a query for the apex comes straight back here.
  #
  # DNS-over-TLS rather than plain 53, because plain 53 to a public resolver is
  # not reliably reachable: captive and hotel networks (and at least one
  # network this laptop uses) drop it to force their own resolver, which took
  # the apex down until this was changed. Port 853 is not filtered the same
  # way, and DoT means no per-network configuration to maintain.
  publicUpstream = ''
    forward . tls://1.1.1.1 tls://1.0.0.1 {
            tls_servername cloudflare-dns.com
        }'';

  # A dummy link exists purely to give resolved something to hang the
  # routing-only domain on. resolved ignores a link with no routable address
  # (link_relevant() in resolved-link.c requires one), hence the /32 below; it
  # carries no traffic, and the /32 keeps it from creating a subnet route.
  # The DNS server itself stays on loopback, which resolved special-cases by
  # skipping SO_BINDTODEVICE/IP_UNICAST_IF, so queries reach CoreDNS over lo.
  linkName = "huskdns";
  linkAddress = "10.99.53.1";

  resolvectl = "${config.systemd.package}/bin/resolvectl";
  ip = "${pkgs.iproute2}/bin/ip";
in
{
  services.coredns = {
    enable = true;
    config = ''
      ${lib.concatMapStringsSep "\n" (name: ''
        ${name}:53 {
            bind ${listenAddress}
            errors
            ${publicUpstream}
        }
      '') publicNames}

      husk-security.dev:53 {
          bind ${listenAddress}
          # Log upstream/template failures. Without this CoreDNS is silent and
          # a broken upstream looks identical to a name that does not exist.
          errors

          # staging.husk-security.dev and every *-staging.husk-security.dev
          # live on the staging ingress. Checked first: "-staging" names also
          # match the general rule below.
          template IN A {
              match "^(staging|[a-z0-9-]+-staging)\.husk-security\.dev\.$"
              answer "{{ .Name }} 60 IN A ${stagingIngress}"
              fallthrough
          }

          # Everything else with a label in front of the apex is production.
          template IN A {
              match "^[a-z0-9-]+(\.[a-z0-9-]+)*\.husk-security\.dev\.$"
              answer "{{ .Name }} 60 IN A ${prodIngress}"
              fallthrough
          }

          # The ingresses are IPv4-only. Answer AAAA with NODATA rather than
          # letting the query fall through to public DNS, where it would
          # NXDOMAIN and stall the browser's happy-eyeballs for every request.
          template IN AAAA {
              match "^[a-z0-9-]+(\.[a-z0-9-]+)*\.husk-security\.dev\.$"
              rcode NOERROR
              fallthrough
          }

          # The apex, and any query type the templates do not claim.
          ${publicUpstream}
      }
    '';
  };

  # NetworkManager would otherwise adopt the dummy link, try to DHCP on it and
  # push its own (empty) DNS config for it into resolved, undoing the below.
  networking.networkmanager.unmanaged = [ "interface-name:${linkName}" ];

  systemd.services.husk-dns-route = {
    description = "Route husk-security.dev DNS to the local Husk split resolver";
    # partOf, not just after: resolved forgets per-link DNS config when it
    # restarts, so this has to re-run whenever it does.
    after = [
      "systemd-resolved.service"
      "coredns.service"
    ];
    requires = [ "systemd-resolved.service" ];
    partOf = [ "systemd-resolved.service" ];
    wants = [ "coredns.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      ${ip} link show ${linkName} >/dev/null 2>&1 || ${ip} link add ${linkName} type dummy
      ${ip} link set ${linkName} up
      ${ip} address replace ${linkAddress}/32 dev ${linkName}

      ${resolvectl} dns ${linkName} ${listenAddress}
      ${resolvectl} domain ${linkName} '~husk-security.dev'
      # Belt and braces: a routing-only domain already stops resolved from
      # volunteering this scope as a default route, but say so explicitly so a
      # future edit cannot accidentally make CoreDNS the system resolver.
      ${resolvectl} default-route ${linkName} false
      ${resolvectl} llmnr ${linkName} no
      ${resolvectl} mdns ${linkName} no
    '';

    preStop = ''
      ${resolvectl} revert ${linkName} || true
      ${ip} link del ${linkName} || true
    '';
  };
}
