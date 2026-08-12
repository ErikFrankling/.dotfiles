{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.main-user;
in
{
  options.main-user = {
    enable = lib.mkEnableOption "enable user module";

    userName = lib.mkOption {
      default = "erikf";
      description = ''
        username
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.userName} = {
      isNormalUser = true;
      initialPassword = "12345";
      description = "main user";
      shell = pkgs.fish;
      extraGroups = [
        "wheel"
        "networkmanager"
        # Lets the time-agent read /dev/input to tell whether a human is
        # actually at the machine. It counts events only and never records
        # which keys were pressed.
        #
        # Group membership only reaches a process started after the next
        # login, which is why the udev rule below exists as well: it grants
        # the same access to whoever is logged in now.
        "input"
      ];
    };

    # Grant the user at the current seat ACL access to input devices.
    #
    # The group above is not enough on its own: supplementary groups are fixed
    # when a session starts, so adding one only takes effect after the next
    # login -- and the systemd user manager, which owns the agent, is among the
    # things that would have to restart for it. uaccess applies to whoever is
    # logged in now, so a rebuild is enough and nobody has to log out.
    #
    # This is the mechanism desktops already use to hand input devices to the
    # active user. The agent counts events and never records which key.
    #
    # It has to be its own package rather than extraRules: those land in
    # 99-local.rules, and systemd acts on the tag in 70-uaccess.rules, so a tag
    # added at 99 is set after the only thing that reads it has already run.
    services.udev.packages = [
      (pkgs.writeTextFile {
        name = "udev-input-uaccess";
        destination = "/etc/udev/rules.d/60-input-uaccess.rules";
        text = ''
          SUBSYSTEM=="input", TAG+="uaccess"
        '';
      })
    ];
  };
}
