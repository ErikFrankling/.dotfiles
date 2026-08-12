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
    # Pre-auth key so enrollment needs no browser login. Read by
    # tailscaled-autoconnect.service only when the backend state is
    # NeedsLogin/NeedsMachineAuth/Stopped (fresh enroll, logout) -- on a
    # logged-in node the file is never opened, so the key going stale is
    # harmless. Generate a reusable TAGGED key (admin console -> Settings ->
    # Keys; the tag needs a tagOwners entry first, see homelab repo
    # docs/tailscale.md): tagged nodes get node-key expiry disabled
    # automatically, so enrolled machines never need to re-auth.
    authKeyFile = config.sops.secrets.tailscale-authkey.path;
    # Applied only to the initial `tailscale up`; frozen into
    # /var/lib/tailscale afterwards and never re-applied to enrolled nodes.
    extraUpFlags = [ "--accept-routes" ];
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
