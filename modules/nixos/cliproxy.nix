{ username, ... }:

# Keys for CLIProxyAPI on the homelab (homelab repo apps/cliproxy.yaml,
# docs/cliproxy.md): the client key every Claude Code / Codex sends, and the
# management key `cliproxy-login` uses to sign accounts in. Shared by all hosts.
# Clients: modules/home-manager/cliproxy.nix.
{
  sops.secrets.cliproxy-client-key = {
    sopsFile = ../../secrets/cliproxy.yaml;
    owner = username;
  };
  sops.secrets.cliproxy-management-key = {
    sopsFile = ../../secrets/cliproxy.yaml;
    owner = username;
  };
}
