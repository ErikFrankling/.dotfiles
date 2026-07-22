{ username, config, ... }:
let
  openvpnEndpoint = "lohman.asuscomm.com";
  warpExclusionUnit = "cloudflare-warp-openvpn-exclusion.service";
in
{
  services.openvpn.servers.homeVPN = {
    autoStart = true;
    updateResolvConf = true;
    config = ''
      config ${config.sops.secrets.openvpn.path}
      auth-user-pass ${config.sops.secrets.openvpn-auth.path}
    '';
  };

  # Keep the OpenVPN transport outside WARP. Nesting OpenVPN's 1500-byte
  # tunnel through WARP's 1280-byte tunnel black-holes larger SSH packets.
  systemd.services.cloudflare-warp-openvpn-exclusion = {
    description = "Exclude the OpenVPN endpoint from Cloudflare WARP";
    after = [ "cloudflare-warp.service" ];
    requires = [ "cloudflare-warp.service" ];
    before = [ "openvpn-homeVPN.service" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.services.cloudflare-warp.package}/bin/warp-cli --accept-tos tunnel host add ${openvpnEndpoint}";
      Restart = "on-failure";
      RestartSec = "5s";
    };
  };

  systemd.services.openvpn-homeVPN = {
    after = [ warpExclusionUnit ];
    requires = [ warpExclusionUnit ];
  };
  users.users."${username}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];
}
