{ ... }: {
  services.openvpn.servers.homeVPN = {
    config = "config /root/nixos/openvpn/homeVPN.conf ";
  };
  users.users."erikf".openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXhLc3vVBQPQLGlf4kMJ/WHXPlsXWzuustUwzFj/AaX erikf@arch-erik-pc"
  ];
}
