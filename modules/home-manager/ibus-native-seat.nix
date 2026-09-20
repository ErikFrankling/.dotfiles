{
  config,
  lib,
  pkgs,
  ...
}:
let
  ibus = pkgs.callPackage ../../packages/ibus-native-seat.nix { };
  prepare = pkgs.writeScript "ibus-wayland-prepare" ''
    #!${pkgs.python3}/bin/python3
    import os, pathlib, signal, time
    # Transfer only the old, unmanaged Wayland frontend to the user service.
    # Do not signal application processes; --exec-daemon restores the daemon if needed.
    targets = []
    for entry in pathlib.Path('/proc').glob('[0-9]*'):
        try:
            if entry.stat().st_uid != os.getuid():
                continue
            args = (entry / 'cmdline').read_bytes().split(b'\0')
            if not args or b'--enable-wayland-im' not in args:
                continue
            name = os.path.basename(os.fsdecode(args[0]))
            if name not in ('ibus-ui-gtk3', '.ibus-ui-gtk3-wrapped'):
                continue
            pid = int(entry.name)
            os.kill(pid, signal.SIGTERM)
            targets.append(entry)
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    deadline = time.monotonic() + 5
    while any(entry.exists() for entry in targets):
        if time.monotonic() >= deadline:
            raise SystemExit('Old IBus Wayland frontend did not exit; refusing a duplicate')
        time.sleep(0.05)
  '';
in
{
  options.services.ibus-native-seat.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Use the native-seat IBus Wayland frontend";
  };
  config.systemd.user.services.ibus-wayland = lib.mkIf config.services.ibus-native-seat.enable {
    Unit = {
      Description = "IBus Wayland frontend retaining the native keyboard seat";
      After = [ "hyprland-session.target" ];
      PartOf = [ "hyprland-session.target" ];
    };
    Service = {
      ExecStartPre = "${prepare}";
      ExecStart = "${ibus}/libexec/ibus-ui-gtk3 --enable-wayland-im --exec-daemon --daemon-args \"--xim --panel disable\"";
      Restart = "on-failure";
      RestartSec = 3;
      TimeoutStartSec = 15;
    };
    Install.WantedBy = [ "hyprland-session.target" ];
  };
}
