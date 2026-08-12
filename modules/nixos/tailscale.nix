{ config, ... }:
{
  # Home VPN client. The Proxmox host runs a Tailscale subnet router that
  # advertises 192.168.50.0/24 (see homelab repo docs/tailscale.md), so joining
  # the tailnet gives the same LAN access the router's OpenVPN used to.
  # Replaces ./openvpn.nix, which is kept as an inactive archive. Tailscale's
  # WireGuard MTU is already 1280, so openvpn.nix's mssfix workaround for WARP
  # full-tunnel overlap has no equivalent here.
  services.tailscale = {
    enable = true;
    # An OAuth client secret (tskey-client-...) used as the pre-auth key, so
    # enrollment needs no browser login. Unlike normal auth keys (90-day max),
    # OAuth client secrets NEVER expire, and the tag they enroll with disables
    # node-key expiry automatically -- set up the secret once and both fresh
    # installs and enrolled machines work forever. Read by
    # tailscaled-autoconnect.service only when the backend needs login; on a
    # logged-in node the file is never opened. Create once in the admin
    # console (see homelab repo docs/tailscale.md): a `tag:client` tagOwners
    # entry, then an OAuth client with the auth_keys scope and tag:client.
    authKeyFile = config.sops.secrets.tailscale-authkey.path;
    # OAuth-based enrollment is unapproved by default; preauthorize it.
    authKeyParameters.preauthorized = true;
    # Applied only to the initial `tailscale up`; frozen into
    # /var/lib/tailscale afterwards and never re-applied to enrolled nodes.
    # --advertise-tags is mandatory when the auth key is an OAuth secret.
    extraUpFlags = [
      "--accept-routes"
      "--advertise-tags=tag:client"
    ];
    # Re-asserted via `tailscale set` (tailscaled-set.service) on every boot
    # and whenever the flags change, correcting manual drift. This, not
    # extraUpFlags, is the authoritative home of --accept-routes; Linux
    # ignores advertised subnet routes without it.
    extraSetFlags = [ "--accept-routes" ];
    # Sole effect of "client": networking.firewall.checkReversePath =
    # "loose", so subnet-routed replies are not dropped by strict rpfilter.
    # ("server"/"both" would pointlessly enable IP forwarding here.)
    useRoutingFeatures = "client";
  };

  # Each importing host must carry a `tailscale-authkey` entry in its default
  # sops file, i.e.:  sops hosts/<host>/secrets/secrets.yaml
  #   tailscale-authkey: tskey-auth-...
  # Rebuilds fail at activation until the entry exists.
  sops.secrets.tailscale-authkey = { };
}
