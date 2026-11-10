# Screen lock: hypridle locks with hyprlock after 5 minutes idle and before
# sleep, and Hyprland locks once at startup: the session logs in by itself
# after the TPM has unlocked the disk, so this is where a person proves who
# they are. Hyprland wiki: hypridle, hyprlock.
{ username, ... }:
{
  # NixOS side: the package and its PAM service (checks the login password).
  programs.hyprlock.enable = true;

  # Lid closed on the charger: lock and stay awake for the nightly update.
  services.logind.settings.Login.HandleLidSwitchExternalPower = "lock";

  home-manager.users.${username} = {
    wayland.windowManager.hyprland.extraConfig = ''
      hl.on("hyprland.start", function() hl.exec_cmd("hyprlock") end)
    '';

    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
        };
        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
        ];
      };
    };

    programs.hyprlock = {
      enable = true;
      package = null; # installed by the NixOS module above
      settings = {
        general.hide_cursor = true;
        background = [ { color = "rgb(000000)"; } ]; # OLED
        input-field = [
          {
            # Empty monitor matches every output, including newly docked
            # screens. Keep the prompt visible: hyprlock otherwise fades
            # an empty field after two seconds, leaving a black screen.
            monitor = "";
            fade_on_empty = false;
            placeholder_text = "Password";
          }
        ];
      };
    };
  };
}
