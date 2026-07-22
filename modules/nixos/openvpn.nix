{ username, config, ... }:
{
  services.openvpn.servers.homeVPN = {
    autoStart = true;
    updateResolvConf = true;
    config = ''
      config ${config.sops.secrets.openvpn.path}
      auth-user-pass ${config.sops.secrets.openvpn-auth.path}
    '';
  };

  # The Husk-managed WARP profile uses include-only split tunneling, so the
  # public OpenVPN endpoint already bypasses WARP. Clear the old CLI exclusion:
  # a local split-tunnel edit changes the client to consumer exclude mode and
  # overrides the organization-managed routes, including the Kubernetes API.
  systemd.services.cloudflare-warp-managed-settings = {
    description = "Clear local WARP overrides and use the managed device profile";
    after = [ "cloudflare-warp.service" ];
    requires = [ "cloudflare-warp.service" ];
    before = [ "openvpn-homeVPN.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${config.services.cloudflare-warp.package}/bin/warp-cli --accept-tos settings reset";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartMode = "direct";
      RestartSec = "5s";
    };
  };

  systemd.services.openvpn-homeVPN = {
    after = [ "cloudflare-warp-managed-settings.service" ];
    requires = [ "cloudflare-warp-managed-settings.service" ];
  };
  users.users."${username}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];
}
