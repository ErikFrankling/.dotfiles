# Native logind -> hypridle -> hyprlock integration, shared by the power menu
# and Super+Ctrl+L. Idle timeouts and login locking remain host policy.
# https://wiki.hypr.land/Hypr-Ecosystem/hypridle/
{ username, lib, ... }:
{
  programs.hyprlock.enable = true;
  home-manager.users.${username} = {
    services.hypridle = {
      enable = true;
      settings.general = {
        lock_cmd = "pidof hyprlock || hyprlock";
        before_sleep_cmd = "loginctl lock-session";
        after_sleep_cmd = "hyprctl dispatch 'hl.dsp.dpms({action=\"on\"})'";
      };
    };
    programs.hyprlock = {
      enable = true;
      package = null;
      settings = {
        general = {
          immediate_render = true;
          hide_cursor = false;
        };
        background = lib.mkDefault [ { color = "rgb(101827)"; } ];
        label = lib.mkDefault [
          {
            monitor = "";
            text = "$TIME";
            font_size = 80;
            color = "rgb(f1f5f9)";
            position = "0, 180";
            halign = "center";
            valign = "center";
          }
          {
            monitor = "";
            text = "Welcome back, Erik";
            font_size = 28;
            color = "rgb(f1f5f9)";
            position = "0, 65";
            halign = "center";
            valign = "center";
          }
        ];
        input-field = lib.mkDefault [
          {
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
          }
        ];
      };
    };
  };
}
