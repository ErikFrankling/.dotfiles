# My own Quickshell desktop shell — the bar, the rail, the launcher, the OSD and
# the notification daemon, all in one process. Replaces waybar (./waybar) and the
# AGS shell (`my-shell`), both of which are still in the repo, just unimported.
#
# The source lives in its own repo, ~/projects/personal/quickshell, and comes in
# as the `erikshell` flake input. That repo owns the module and the package; this
# file only says "run it here, and here is how to point it at the working tree".
#
# Three paths:
#
#   production  the systemd unit below, running the store copy of the QML. What
#               is on screen after a `rebuild`.
#   design      `cd ~/projects/personal/quickshell && nix run .` — the same shell
#               off the working tree, hot-reloading on save. No rebuild involved.
#               Stop the unit first (`systemctl --user stop erikshell`) so the two
#               do not fight over org.freedesktop.Notifications and the tray, and
#               `systemctl --user start erikshell` when done.
#   swapped     `erikshell-dev on` — the unit itself runs the working tree, from
#               now until `erikshell-dev off` or the next reboot. No rebuild
#               either way. This is the one to reach for.
#
# `programs.erikshell.localDev.enable = true` is the declarative version of
# `erikshell-dev on`: the unit runs the working tree, so the desktop that comes
# up on login is the one that hot-reloads. It costs a rebuild each way, which is
# why the imperative command exists — but this is the one that survives a reboot.
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

  # The same swap as localDev, without the rebuild: a runtime systemd drop-in
  # that overrides the unit's own ExecStart. Runtime drop-ins live under
  # $XDG_RUNTIME_DIR, i.e. /run, so nothing Nix manages is touched and the
  # override cannot outlive the session that set it — a reboot puts the store
  # copy back on its own. `user.control/` rather than `user/` because that is
  # the directory `systemctl --user edit --runtime` writes to, and the only one
  # that outranks the unit home-manager installs in ~/.config/systemd/user.
  devSwap = pkgs.writeShellApplication {
    name = "erikshell-dev";
    runtimeInputs = [
      pkgs.systemd
      pkgs.procps
    ];
    text = ''
      dropin="$XDG_RUNTIME_DIR/systemd/user.control/erikshell.service.d"

      report() {
        if [ -e "$dropin/override.conf" ]; then
          echo "erikshell: WORKING TREE — ${devTree}"
          echo "  hot-reloads on save. Off again with 'erikshell-dev off', and"
          echo "  a reboot reverts to the store copy by itself."
        else
          echo "erikshell: store copy"
        fi
        echo "  ExecStart: $(systemctl --user show erikshell -p ExecStart --value)"
        echo "  unit:      $(systemctl --user is-active erikshell)"
        running=$(pgrep -c quickshell || true)
        if [ "$running" -gt 1 ]; then
          echo "  WARNING: $running quickshell processes are running — they will"
          echo "  fight over org.freedesktop.Notifications and the tray."
        fi
      }

      # A QML error kills the process, Restart=on-failure restarts it, and a few
      # seconds later systemd gives up and latches the unit into `failed` — where
      # it stays, refusing to start anything, until it is reset. So every swap
      # clears that latch first, and none of this is allowed to abort the script:
      # a restart that fails is the case the caller has to handle, not exit on.
      swap() {
        systemctl --user daemon-reload
        systemctl --user reset-failed erikshell || true
        systemctl --user restart erikshell || true
        sleep 3
      }

      case "''${1:-status}" in
        on)
          mkdir -p "$dropin"
          # ExecStart is a list, so it has to be cleared before it can be reset.
          printf '[Service]\nExecStart=\nExecStart=%s\n' ${lib.escapeShellArg runFromTree} \
            > "$dropin/override.conf"
          swap
          # A working tree that does not load must not leave him with no shell.
          if ! systemctl --user is-active --quiet erikshell; then
            rm -rf "$dropin"
            swap
            echo "the working tree did not start — reverted to the store copy" >&2
            report
            exit 1
          fi
          ;;
        off)
          rm -rf "$dropin"
          swap
          ;;
        status) ;;
        *)
          echo "usage: erikshell-dev [on|off|status]" >&2
          exit 2
          ;;
      esac

      report
    '';
  };

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
    home.packages = [
      pkgs.libnotify
      devSwap
    ];

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
