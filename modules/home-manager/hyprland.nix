{ lib, pkgs, ... }:

{
  programs.wofi.enable = true;
  
  home.sessionVariables = {
    XCURSOR_SIZE = "15";
  };

  home.packages = with pkgs; [
  ];

  services.cliphist.enable = true;

  wayland.windowManager.hyprland = {
      enable = true;
      xwayland.enable = true;

    extraConfig = ''
      exec-once = wl-paste --type text --watch cliphist store #Stores only text data

      exec-once = wl-paste --type image --watch cliphist store #Stores only image data
    '';

      settings = {        # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
        input = {
            kb_layout = "us";
            kb_variant = "";
            kb_model = "";
            kb_options = "caps:super";
            kb_rules = "";

            follow_mouse = 1;

            touchpad = {
                natural_scroll = false;
            };

            sensitivity = 0; # -1.0 - 1.0, 0 means no modification.
        };

        general = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more

            gaps_in = 0;
            gaps_out = 0;
            border_size = 2;
            "col.active_border" = "rgba(33ccffee)"; #rgba(00ff99ee) 90deg
            "col.inactive_border" = "rgba(595959aa)";

            layout = "dwindle";

            # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
            allow_tearing = false;
        };

        decoration = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more

            rounding = 0;

            blur = {
                enabled = true;
                size = 3;
                passes = 1;
                vibrancy = 0.1696;
            };

            drop_shadow = true;
            shadow_range = 4;
            shadow_render_power = 3;
            "col.shadow" = "rgba(1a1a1aee)";
        };

        animations = {
            enabled = true;

            # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more

            bezier = "myBezier, 0.05, 0.9, 0.1, 1.05";

            animation = [
                "windows, 1, 7, myBezier"
                "windowsOut, 1, 7, default, popin 80%"
                "border, 1, 10, default"
                "borderangle, 1, 8, default"
                "fade, 1, 7, default"
                "workspaces, 0, 6, default"
            ];
        };

        dwindle = {
            # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
            preserve_split = true; # you probably want this
        };

        master = {
            # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
            new_is_master = true;
        };

        gestures = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            workspace_swipe = false;
        };

        misc = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            force_default_wallpaper = 0; # Set to 0 to disable the anime mascot wallpapers
        };

        "$mod" = "SUPER";
        bind = let 
            terminal = "kitty";
            menu = "wofi --allow-images --show=drun --lines=15"; # prompt=""";
          workspaces = map toString (lib.range 1 9);
          directions = {
            h = "l";
            l = "r";
            k = "u";
            j = "d";
          };
          resizes = {
            h = "-30 0";
            l = "30 0";
            k = "0 -30";
            j = "0 30";
          };
        in [
            "$mod, Return, Exec, ${terminal}"
            "$mod, D, Exec, ${menu}"
            "$mod, Q, killactive"
            "$mod, E, exit"
            "$mod, F, togglefloating"
            "$mod, A, layoutmsg, preselect l"
            # "$mod, F, exec, firefox"
            # ", Print, exec, grimblast copy area"
          ] ++
        # change workspace
        (map (n: "$mod,${n},workspace,name:${n}") workspaces) ++

        # move window to workspace
        (map (n: "$mod SHIFT,${n},movetoworkspacesilent,name:${n}") workspaces) ++

        # move focus
        (lib.mapAttrsToList (key: direction: "$mod,${key},movefocus,${direction}")
          directions) ++

        # resize window 
        (lib.mapAttrsToList (key: resize: "$mod ALT,${key},resizeactive,${resize}")
          resizes) ++

        # swap windows
        (lib.mapAttrsToList
          (key: direction: "$mod SHIFT,${key},swapwindow,${direction}") directions);

        bindm = [
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
        ];

        bindle = [
            # Example volume button that allows press and hold, volume limited to 150%
            ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+"

            # Example volume button that will activate even while an input inhibitor is active
            ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"

            ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
        ];

        windowrule = [
            "rounding 10,floating:1"
        ];
      };
  };
}
