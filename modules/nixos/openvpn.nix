{ username, config, ... }:
{
  services.openvpn.servers.homeVPN = {
    autoStart = true;
    # config = "config /root/nixos/openvpn/homeVPN.conf ";
    config = ''
      config ${config.sops.secrets.openvpn.path}
    '';
  };
  users.users."${username}".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];
}
