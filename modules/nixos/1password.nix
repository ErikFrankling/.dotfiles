{ config, username, ... }:

# 1Password desktop app and CLI, using the upstream NixOS modules
# (https://wiki.nixos.org/wiki/1Password). The GUI module sets up the polkit
# policy for system authentication and the setgid wrapper the browser
# extension's native messaging needs.
{
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ username ];
  };

  # Under /nix/store the app looks for its helper binaries in
  # /run/wrappers/bin. The module only wraps 1Password-BrowserSupport, so
  # "Import from LastPass" failed with "Failed to find
  # `1Password-LastPass-Exporter`". Upstream installs it as a plain
  # executable, so this wrapper has no setuid/setgid.
  security.wrappers."1Password-LastPass-Exporter" = {
    source = "${config.programs._1password-gui.package}/share/1password/1Password-LastPass-Exporter";
    owner = "root";
    group = "root";
    setuid = false;
    setgid = false;
  };

  # Firefox and Chrome are allowed by default; other browsers must be listed
  # by executable name for the extension to connect to the desktop app.
  environment.etc."1password/custom_allowed_browsers" = {
    text = ''
      zen
      .zen-wrapped
      helium
    '';
    mode = "0755";
  };
}
