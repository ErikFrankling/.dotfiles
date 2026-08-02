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
        "input"
      ];
    };
  };
}
