{
  lib,
  pkgs,
  config,
  ...
}:

{
  imports = [ ./options.nix ];

  config =
    let
      cfg = config.hyprland;
    in
    {
      home.pointerCursor = {
        gtk.enable = true;
        # x11.enable = true;
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 16;
      };

      programs.wofi.enable = true;
      # services.cliphist.enable = true;

      home.packages = with pkgs; [
        brightnessctl
        playerctl
        grim
        swappy
        slurp
        networkmanagerapplet
        blueman
        spotify-tray
        wmname
        ibus
      ];

      home.file = {
        ".config/hypr/import_env".source = ./import_env;
      };

      home.sessionVariables = {
        # toolkit-specific scale
        GDK_SCALE = "2";
        XCURSOR_SIZE = "32";
        XDG_SESSION_DESKTOP = "Hyprland";

        # If your cursor becomes invisible
        # WLR_NO_HARDWARE_CURSORS = "1";
        # Hint electron apps to use wayland
        NIXOS_OZONE_WL = "1";
        MOZ_ENABLE_WAYLAND = "1";
      };

      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;

        extraConfig = ''
          # exec-once = hyprctl output create headless
          # exec-once = hyprctl keyword monitor HEADLESS-1,1920x1080@60,0x0,1


          # exec = pkill eww
          # exec = eww daemon
          # exec = eww open bar
          # exec = pkill waybar
          # exec-once = ags run
          exec-once = my-shell
          exec-once = waybar --config .config/waybar/cofig.jsonc
          exec-once = nm-applet
          exec-once = blueman-applet
          exec-once = blueman-tray
          exec-once = spotify-tray
          exec-once = /usr/lib/kdeconnectd 
          exec-once = kdeconnect-indicator

          exec-once = wmname LG3D
          exec-once = $HOME/.config/hypr/import_env tmux
          exec-once = $HOME/.config/hypr/import_env system

          # exec-once = wl-paste --type text --watch cliphist store #Stores only text data
          # exec-once = wl-paste --type image --watch cliphist store #Stores only image data
          exec-once = wl-paste --type text #Stores only text data
          exec-once = wl-paste --type image #Stores only image data

          # exec-once = ibus-daemon -drx --panel=/dev/null
          # exec-once = ibus-daemon -dr
          # exec-once = ${pkgs.ibus}/bin/ibus-daemon --daemonize --xim 
          # exec-once = ${pkgs.ibus}/libexec/ibus-ui-gtk3 --panel
          exec-once = ibus start --type wayland

          exec-once = lxqt-policykit-agent


          # exec-once=[workspace 1 silent] kitty tmux
          # exec-once=[workspace 2 silent] kitty tmux
          # exec-once=[workspace 3 silent] firefox
          # exec-once=[workspace 4 silent] webcord
          # exec-once=[workspace 4 silent] spotify-launcher

          ${lib.concatStrings (
            (map (w: ''
              exec-once=[workspace ${toString w.workspace} silent] ${w.exec}
            '') (cfg.initWindows))
          )}

          # exec-once = hyprctl workspace DP-1~1
          # exec-once = hyprctl workspace HDMI-1~10


          # Rusty Retirement Game Overlay
          windowrule = tag +rtr, match:title (Rusty's Retirement)
          windowrule = float 1, tag rtr

          # Remove this if you don't want rtr to appear in all workspaces
          windowrule = pin 1, tag rtr

          # windowrule = size 100% 350, tag rtr
          windowrule = size 100% 296, tag rtr

          # Move rtr to buttom of the screen
          # windowrule = move 0 730, tag rtr
          windowrule = move 0 784, tag rtr

          windowrule = no_blur 1, tag rtr
          windowrule = no_shadow 1, tag rtr
          windowrule = border_size 0, tag rtr
          # override rounded corners
          windowrule = rounding 0, tag rtr
          windowrule = opacity 1.0 override, tag rtr

          # rules for having it on the right side
          # windowrule = size 296 100%, tag rtr_right 

          exec-once = hyprctl workspace 10
          exec-once = hyprctl workspace 1

        '';

        settings = {
          monitor = map (
            m:
            let
              resolution = "${toString m.width}x${toString m.height}@${toString m.refreshRate}";
              position = "${toString m.x}x${toString m.y}";
            in
            "${m.name},${if m.enabled then "${resolution},${position},${m.scale}" else "disable"}"
          ) (cfg.monitors);
          # ++ "DP-1, addreserved, , 296, , ";

          # device = [
          #   {
          #     name = "tshort-dactyl-manuform-(5x6)";
          #     kb_layout = "us";
          #   }
          #   {
          #     name = "logitech-g512-carbon-tactile";
          #     kb_layout = "se";
          #   }
          # ];
          # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
          input = {
            kb_layout = "us,se";
            kb_variant = "";
            kb_model = "";
            kb_options = "caps:super";
            kb_rules = "";

            follow_mouse = 1;

            touchpad = {
              natural_scroll = true;
            };
          };

          # device = builtins.trace "${builtins.toString cfg.keyboards}" map (k: {
          device = map (k: {
            name = k.name;
            kb_layout = k.kb_layout;
          }) (cfg.keyboards);

          "$mod" = "SUPER";
          bind =
            let
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
            in
            [
              # "$mod, O, Exec, hyprctl switchxkblayout at-translated-set-2-keyboard next"
              "$mod, Return, Exec, ${terminal}"
              "$mod, D, Exec, ${menu}"
              "$mod, Q, killactive"
              "$mod, E, exit"
              "$mod, F, togglefloating"
              "$mod, A, layoutmsg, preselect l"
              ''$mod, P, exec, hyprctl --batch "dispatch setfloating; dispatch pin"''
              # "$mod, B, fullscreenstate 1"
              "$mod, R, fullscreen"
              # Screeenshot
              '', Print, exec, grim -g "$(slurp)" - | swappy -f -''
              # ", Print, exec, grimblast copy area"

              ", XF86AudioPlay, exec, playerctl play-pause" # the stupid key is called play , but it toggles
              ", XF86AudioNext, exec, playerctl next"
              ", XF86AudioPrev, exec, playerctl previous"

              "$mod, T, tagwindow, +rtr_right title:(Rusty's Retirement)"
              "$mod, T, exec, hyprctl monitor DP-1,addreserved,0,0,296,0"

              "$mod, Y, tagwindow, -rtr_right title:(Rusty's Retirement)"
              "$mod, Y, exec, hyprctl monitor DP-1,addreserved,0,296,0,0"
            ]
            ++
              # keyboard layout switching
              (map (k: "$mod, O, Exec, hyprctl switchxkblayout ${k.name} next") (
                builtins.filter (k: k.multilang) cfg.keyboards
              ))
            ++
              # change workspace
              (map (n: "$mod,${n},workspace,name:${n}") workspaces)
            ++ [ "$mod,0,workspace,name:10" ]
            ++

              # move window to workspace
              (map (n: "$mod SHIFT,${n},movetoworkspace,name:${n}") workspaces)
            ++ [ "$mod SHIFT,0,movetoworkspace,name:10" ]
            ++

              # move focus
              (lib.mapAttrsToList (key: direction: "$mod,${key},movefocus,${direction}") directions)
            ++

              # resize window
              (lib.mapAttrsToList (key: resize: "$mod ALT,${key},resizeactive,${resize}") resizes)
            ++

              # swap windows
              (lib.mapAttrsToList (key: direction: "$mod SHIFT,${key},swapwindow,${direction}") directions);

          bindm = [
            "$mod, mouse:272, movewindow"
            "$mod, mouse:273, resizewindow"
          ];

          # l -> do stuff even when locked
          # e -> repeats when key is held
          bindle = [
            # Example volume button that allows press and hold, volume limited to 150%
            ", XF86AudioRaiseVolume, exec, wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+"
            # Example volume button that will activate even while an input inhibitor is active
            ", XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"

            ", xf86monbrightnessup, exec, brightnessctl set 10%+"
            "$mod, U, exec, brightnessctl set 10%+"
            ", xf86monbrightnessdown, exec, brightnessctl set 10%-"
            "$mod, I, exec, brightnessctl set 10%-"
          ];

          bindl = [
            ", XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"
          ];

          workspace = [
            "w[tv1], gapsout:0, gapsin:0"
            "f[1], gapsout:0, gapsin:0"
          ]
          ++ (map (
            w: "${toString w.ID}, monitor:${w.monitor}${if w.default then " default:true" else ""}"
          ) cfg.workspaces);

          "$pip_size" = "40";
          windowrule = [
            # Ref https://wiki.hyprland.org/Configuring/Workspace-Rules/
            # "Smart gaps" / "No gaps when only"
            "border_size 0, match:float 0, match:workspace w[tv1]"
            "rounding 0, match:float 0, match:workspace w[tv1]"
            "border_size 0, match:float 0, match:workspace f[1]"
            "rounding 0, match:float 0, match:workspace f[1]"

            "float 1,match:title ^(Picture-in-Picture)$"
            "size $pip_size% $pip_size%,match:title ^(Picture-in-Picture)$"
            "move 100 100-$pip_size 0,match:title ^(Picture-in-Picture)$"
            "pin 1,match:title ^(Picture-in-Picture)$"
            "border_size 0,match:title ^(Picture-in-Picture)$,float 1"
            "keep_aspect_ratio 1,match:title ^(Picture-in-Picture)$,float 1"
            "opacity 0.3 1.0,match:title ^(Picture-in-Picture)$,float 1"

            # "suppressevent fullscreen, class:.*" # You'll probably like this.

            "rounding 10,match:float 1"
          ];

          general = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            gaps_in = 0;
            gaps_out = 0;
            border_size = 2;
            "col.active_border" = "rgba(33ccffee)"; # rgba(00ff99ee) 90deg
            "col.inactive_border" = "rgba(595959aa)";

            layout = "dwindle";

            # Please see https://wiki.hyprland.org/Configuring/Tearing/ before you turn this on
            allow_tearing = false;
            resize_on_border = true;
          };

          debug = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            disable_logs = false;
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

            # drop_shadow = true;
            # shadow_range = 4;
            # shadow_render_power = 3;
            # "col.shadow" = "rgba(1a1a1aee)";
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
          # unscale XWayland
          xwayland = {
            force_zero_scaling = true;
          };

          dwindle = {
            # See https://wiki.hyprland.org/Configuring/Dwindle-Layout/ for more
            preserve_split = true; # you probably want this
            # no_gaps_when_only = 1;
          };

          master = {
            # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
            # new_is_master = true;
            # no_gaps_when_only = 1;
          };

          # gestures = {
          #   # See https://wiki.hyprland.org/Configuring/Variables/ for more
          #   workspace_swipe = true;
          #   workspace_swipe_distance = 150;
          #   workspace_swipe_use_r = true;
          # };

          misc = {
            # See https://wiki.hyprland.org/Configuring/Variables/ for more
            force_default_wallpaper = 0; # Set to 0 to disable the anime mascot wallpapers
          };

        };
      };
    };
}
