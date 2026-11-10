# T3 Code server for work: agents working on Ablo code run here, never on the
# pc (SOC 2). Home Manager's own module runs `t3 serve` as a user service on
# 127.0.0.1:3773 with the same state as the desktop app (~/.t3). The app also
# lists the pc's server (modules/home-manager/t3code-connection.nix), for
# dotfiles and homelab work.
#
# One-time, in the app: Settings > Environments > turn off "Local
# environment" (the app's built-in server, which dies with the window), then
# `t3 pair` and open the pairing link to add this server.
{ lib, pkgs, ... }:
{
  # Home Manager exposes server/client settings, but not Electron's
  # desktop-settings.json. Merge this upstream setting, preserving the
  # app's other preferences; its own server already owns the data directory.
  home.activation.t3codeRemoteDesktop = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    file="$HOME/.t3/userdata/desktop-settings.json"
    if [ -e "$file" ]; then
      run ${pkgs.jq}/bin/jq '.localEnvironmentEnabled = false' "$file" > "$file.tmp"
    else
      run mkdir -p "$(dirname "$file")"
      printf '%s\n' '{"localEnvironmentEnabled":false}' > "$file.tmp"
    fi
    run mv "$file.tmp" "$file"
  '';

  programs.t3code = {
    enable = true;
    server.enable = true;
    # No server-to-server links with the pc, and new threads never land there
    # on their own.
    userSettings.linkedEnvironmentsEnabled = false;
    clientSettings.loadBalancingEnabled = false;
  };

  systemd.user.services.t3code = {
    # A restart kills running agents, so the 06:00 auto-update leaves it be;
    # a new build starts with the next login.
    Unit.X-SwitchMethod = "keep-old";
    # 78: the app's built-in server still owns ~/.t3 (see above). Wait for
    # that instead of restarting in a loop.
    Service.RestartPreventExitStatus = 78;
  };
}
