{ username, ... }:

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
