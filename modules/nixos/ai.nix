{ username, ... }:

{
  networking.firewall.allowedTCPPorts = [ 4096 ];

  # Required for the Codex user service to run at boot without a graphical login.
  users.users.${username}.linger = true;

  # API key ("agents") for Executor on the homelab, read at launch by the
  # agent harness wrappers (modules/home-manager/executor-harness.nix). Each
  # importing host needs an `executor-api-key` entry in its sops file.
  sops.secrets.executor-api-key.owner = username;
}
