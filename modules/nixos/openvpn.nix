{ username, config, ... }:
{
  services.openvpn.servers.homeVPN = {
    autoStart = true;
    config = ''
      config ${config.sops.secrets.openvpn.path}
      auth-user-pass ${config.sops.secrets.openvpn-auth.path}
    '';
  };
  users.users."${username}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];
}
