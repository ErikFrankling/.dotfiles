# Screen lock: hypridle locks with hyprlock after 5 minutes idle and before
# sleep, and Hyprland locks once at startup: the session logs in by itself
# after the TPM has unlocked the disk, so this is where a person proves who
# they are. Hyprland wiki: hypridle, hyprlock.
# Native Home Manager pattern and visible clock/input widgets:
# https://github.com/fufexan/dotfiles/blob/main/home/programs/wayland/hyprlock.nix
# Idle lifecycle and Lua DPMS commands:
# https://github.com/hyprwm/hypridle/blob/main/assets/example.conf
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
          after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({action=\"on\"})'";
        };
        listener = [
          {
            timeout = 300;
            on-timeout = "loginctl lock-session";
          }
          {
            # Show the lock screen for another five idle minutes before
            # powering down the displays. Any input wakes them again.
            timeout = 600;
            on-timeout = "hyprctl dispatch 'hl.dsp.dpms({action=\"off\"})'";
            on-resume = "hyprctl dispatch 'hl.dsp.dpms({action=\"on\"})'";
          }
        ];
      };
    };

    programs.hyprlock = {
      enable = true;
      package = null; # installed by the NixOS module above
      settings = {
        general = {
          immediate_render = true;
          hide_cursor = false;
        };
        background = [ { color = "rgb(101827)"; } ];
        label = [
          {
            monitor = "";
            text = "$TIME";
            font_family = "Sans";
            font_size = 80;
            color = "rgb(f1f5f9)";
            position = "0, 180";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "Welcome back, Erik";
            font_family = "Sans";
            font_size = 28;
            color = "rgb(f1f5f9)";
            position = "0, 65";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "Enter your password to unlock";
            font_family = "Sans";
            font_size = 14;
            color = "rgb(94a3b8)";
            position = "0, -130";
            halign = "center";
            valign = "center";
          }
        ];
        input-field = [
          {
            # Empty monitor matches every output, including newly docked
            # screens. Keep the prompt visible: hyprlock otherwise fades
            # an empty field after two seconds, leaving a black screen.
            monitor = "";
            fade_on_empty = false;
            placeholder_text = "Password";
            size = "340, 64";
            position = "0, -35";
            rounding = 14;
            outline_thickness = 2;
            inner_color = "rgb(1e293b)";
            outer_color = "rgb(60a5fa)";
            font_color = "rgb(f1f5f9)";
            check_color = "rgb(34d399)";
            fail_color = "rgb(f87171)";
          }
        ];
      };
    };
  };
}
