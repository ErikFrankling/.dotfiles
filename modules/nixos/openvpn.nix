# ARCHIVED 2026-08-12: the router's OpenVPN server is gone; the home VPN is
# now Tailscale (see ./tailscale.nix). Kept unimported for reference.
{ username, config, ... }:
{
  services.openvpn.servers.homeVPN = {
    autoStart = true;
    updateResolvConf = true;
    config = ''
      config ${config.sops.secrets.openvpn.path}
      auth-user-pass ${config.sops.secrets.openvpn-auth.path}
      # WARP's tunnel is 1280 MTU. If it ever full-tunnels us again the ~1500
      # byte outer datagrams get blackholed with no working PMTUD, and SSH dies
      # the moment anything emits a full-size packet. Clamping TCP MSS keeps
      # sessions alive through that; costs some throughput on bulk transfers.
      mssfix 1280
    '';
  };

  users.users."${username}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];
}
