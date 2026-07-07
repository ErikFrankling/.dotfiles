{ username, ... }:

{
  networking.firewall.allowedTCPPorts = [ 4096 ];

  # Required for the Codex user service to run at boot without a graphical login.
  users.users.${username}.linger = true;
}
