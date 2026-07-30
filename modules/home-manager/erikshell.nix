# My own Quickshell desktop shell — the bar, the rail, the launcher, the OSD and
# the notification daemon, all in one process. Replaces waybar (./waybar) and the
# AGS shell (`my-shell`), both of which are still in the repo, just unimported.
#
# The source lives in its own repo, ~/projects/personal/quickshell, and comes in
# as the `erikshell` flake input. That repo owns the module and the package; this
# file only says "run it here, and here is how to point it at the working tree".
#
# Two paths, deliberately, and never a third:
#
#   production  the systemd unit below, running the store copy of the QML. What
#               is on screen after a `rebuild`.
#   design      `cd ~/projects/personal/quickshell && nix run .` — the same shell
#               off the working tree, hot-reloading on save. No rebuild involved.
#               Stop the unit first (`systemctl --user stop erikshell`) so the two
#               do not fight over org.freedesktop.Notifications and the tray, and
#               `systemctl --user start erikshell` when done.
#
# `programs.erikshell.localDev.enable = true` welds the two together: the unit
# itself then runs the working tree, so the desktop that comes up on login is the
# one that hot-reloads. That costs one rebuild to turn on and one to turn off,
# which is why it is a flag and not the default.
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;

  # Where the shell is developed. `nix run .` in here runs the same shell
  # straight off disk, and quickshell reloads a .qml file the moment it is
  # saved — no rebuild, no reinstall.
  devTree = "${config.home.homeDirectory}/projects/personal/quickshell";

  # The flake's `apps.default`: a script that puts the shell's runtime
  # dependencies on PATH and then runs `quickshell -p <dir>`, defaulting to
  # $PWD. Reusing it means localDev cannot drift from the packaged version's
  # runtime environment.
  runFromTree = "${inputs.erikshell.apps.${system}.default.program} ${devTree}";

  cfg = config.programs.erikshell;
in
{
  imports = [ inputs.erikshell.homeManagerModules.default ];

  options.programs.erikshell.localDev.enable = lib.mkEnableOption ''
    running the autostarted shell out of ${devTree} instead of the store copy,
    so saving a .qml file hot-reloads the live desktop
  '';

  config = {
    # The client half of the notification spec. The shell is the daemon, so
    # nothing here provides `notify-send` — and without it a script has no way
    # to raise a notification, and no way to check the daemon is alive.
    home.packages = [ pkgs.libnotify ];

    programs.erikshell = {
      enable = true;

      # A user unit, not `exec-once`. It is bound to the Hyprland session, so it
      # comes up with the compositor and dies with it, `systemctl --user restart
      # erikshell` is the whole restart story, and Restart=on-failure means a QML
      # error that kills the process does not leave the desktop bare. Running it
      # from both a unit and exec-once is the one thing not to do: two instances
      # fight over org.freedesktop.Notifications and the tray.
      systemd.enable = true;
    };

    systemd.user.services.erikshell = {
      # The shell's own module orders the unit against
      # `config.wayland.systemd.target`, which home-manager leaves at
      # graphical-session.target — the Hyprland module creates
      # hyprland-session.target but never points wayland.systemd.target at it.
      # hyprland-session.target is the one Hyprland starts itself, immediately
      # after `dbus-update-activation-environment` has put WAYLAND_DISPLAY and
      # HYPRLAND_INSTANCE_SIGNATURE into the user manager's environment, so it is
      # the honest "the compositor is up and reachable" signal.
      #
      # Done here rather than by setting wayland.systemd.target globally,
      # because that option is read by every wayland service in the generation
      # (syncthingtray, voxtype, ydotoold) and there is no reason to move those.
      Unit = {
        After = lib.mkForce [ "hyprland-session.target" ];
        PartOf = lib.mkForce [ "hyprland-session.target" ];
      };
      Install.WantedBy = lib.mkForce [ "hyprland-session.target" ];

      Service = {
        # Apps launched from the shell's launcher land in this unit's cgroup — a
        # double fork does not escape it — so the default KillMode=control-group
        # would SIGTERM every one of them on `systemctl --user restart erikshell`.
        # The shell repo has since grown the same line; once the input is bumped
        # past fa0366a this one is redundant and can go.
        KillMode = "process";

        ExecStart = lib.mkIf cfg.localDev.enable (lib.mkForce runFromTree);
      };
    };
  };
}
