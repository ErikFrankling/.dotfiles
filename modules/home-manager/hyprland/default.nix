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
      toLua = lib.generators.toLua { };
      lua = lib.generators.mkLuaInline;
      # Every bind says what it does: under Lua, `hyprctl binds` reports only
      # `dispatcher: __lua` otherwise, and the shell's keys sheet (SUPER + B) reads
      # this. ~/projects/personal/quickshell/docs/keyboard.md.
      bindWith = key: description: action: opts: {
        _args = [
          key
          (lua action)
          (opts // { inherit description; })
        ];
      };
      bind =
        key: description: action:
        bindWith key description action { };
      bindExec =
        key: description: command:
        bind key description "hl.dsp.exec_cmd(${toLua command})";
    in
    {
      # Home Manager has its own package set; patch its Hyprland launcher too.
      nixpkgs.overlays = [ (import ../../../overlays/aquamarine.nix) ];

      home.pointerCursor = {
        enable = true;
        gtk.enable = true;
        # x11.enable = true;
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Classic";
        size = 16;
      };

      # The launcher is the shell's own now ($mod+D, see bindd below). Wofi is
      # left here commented rather than deleted — uncomment this and the $mod+D
      # bind further down to go back to it.
      # programs.wofi.enable = true;
      # services.cliphist.enable = true;

      home.packages = with pkgs; [
        brightnessctl
        playerctl
        grim
        swappy
        slurp
        wl-clipboard
        networkmanagerapplet
        blueman
        spotify-tray
        wmname
        ibus
        grimblast
        satty
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
        # Force Claude Desktop to use native Wayland (sharp HiDPI text)
        CLAUDE_USE_WAYLAND = "1";
      };

      # The same 2x scale over XSETTINGS, for X11 GTK apps that never see
      # GDK_SCALE: pkexec wipes the environment, so GParted running as root
      # rendered at 1x under force_zero_scaling.
      services.xsettingsd = {
        enable = true;
        settings = {
          "Gdk/WindowScalingFactor" = 2;
          "Gdk/UnscaledDPI" = 98304; # 96 * 1024, so fonts are not scaled twice
        };
      };

      xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

      wayland.windowManager.hyprland = {
        enable = true;
        xwayland.enable = true;
        # The NixOS module installs Hyprland; a second copy here would shadow it.
        package = null;
        portalPackage = null;
        # Hyprland 0.57 reads nothing but Lua. Everything below becomes one
        # generated ~/.config/hypr/hyprland.lua; other modules add to the same
        # `settings` lists (window_rule, bind, workspace_rule, monitor).
        configType = "lua";

        # `hl.curve` has to run before the `hl.animation` calls that name a curve.
        # Home Manager sorts the rest by name.
        importantPrefixes = [ "curve" ];

        # Hand the scaling/Wayland session variables to the systemd user
        # manager too. The shell (erikshell) is a user unit, so every app
        # started from its launcher inherits the manager's environment, not
        # Hyprland's. Without GDK_SCALE there, XWayland apps (Steam, Spotify)
        # render at 1x on the 2x monitors because of force_zero_scaling.
        # The `import_env system` exec-once below was meant to cover
        # XCURSOR_SIZE but the script is not executable, so it never ran.
        systemd.variables = [
          "DISPLAY"
          "HYPRLAND_INSTANCE_SIGNATURE"
          "WAYLAND_DISPLAY"
          "XDG_CURRENT_DESKTOP"
          "XDG_SESSION_TYPE"
        ]
        ++ builtins.attrNames config.home.sessionVariables;

        extraConfig =
          let
            start = lib.concatMapStrings (command: "  hl.exec_cmd(${toLua command})\n");
          in
          ''
            -- Old autostart, kept for reference:
            --   hyprctl output create headless
            --   pkill eww; eww daemon; eww open bar; pkill waybar
            --   ags run
            --   my-shell: the AGS shell. Replaced by erikshell, which is started by
            --   its own systemd user unit (see ../erikshell.nix) rather than from
            --   here: two shells would fight over org.freedesktop.Notifications and
            --   the tray.
            --   Waybar was managed by Home Manager systemd integration.
            --   wl-paste --type text --watch cliphist store
            --   wl-paste --type image --watch cliphist store
            --   ibus-daemon -drx --panel=/dev/null
            --   ibus-daemon -dr
            --   ''${pkgs.ibus}/bin/ibus-daemon --daemonize --xim
            --   ''${pkgs.ibus}/libexec/ibus-ui-gtk3 --panel
            --   hl.exec_cmd("kitty tmux", { workspace = "1 silent" })
            --   hl.exec_cmd("kitty tmux", { workspace = "2 silent" })
            --   hl.exec_cmd("firefox", { workspace = "3 silent" })
            --   hl.exec_cmd("webcord", { workspace = "4 silent" })
            --   hl.exec_cmd("spotify-launcher", { workspace = "4 silent" })
            --   hyprctl workspace DP-1~1
            --   hyprctl workspace HDMI-1~10
            hl.on("hyprland.start", function()
            ${
              start (
                [
                  "nm-applet"
                  "blueman-applet"
                  "blueman-tray"
                  "spotify-tray"
                  "/usr/lib/kdeconnectd"
                  "kdeconnect-indicator"
                  "wmname LG3D"
                  "$HOME/.config/hypr/import_env tmux"
                  "$HOME/.config/hypr/import_env system"
                  "wl-paste --type text" # Stores only text data
                  "wl-paste --type image" # Stores only image data
                ]
                # On pc, the patched IBus frontend is owned by ibus-wayland.service.
                ++ lib.optional (!(config.services.ibus-native-seat.enable or false)) "ibus start --type wayland"
                ++ [ "lxqt-policykit-agent" ]
              )
            }${
              lib.concatMapStrings (
                w: "  hl.exec_cmd(${toLua w.exec}, { workspace = ${toLua "${toString w.workspace} silent"} })\n"
              ) cfg.initWindows
            }${
              start [
                "hyprctl workspace 10"
                "hyprctl workspace 1"
              ]
            }end)

            -- Voxtype switches into this submap (via [output] pre_output_command)
            -- for the instant it injects each chunk of streamed text, then leaves
            -- it again (post_output_command -> reset). It is intentionally EMPTY:
            -- with no binds active, voxtype's synthetic keystrokes can't trigger
            -- any window shortcut or stop/cancel the session. Text input itself
            -- still passes through: submaps only gate keybinds, not typing.
            -- Hyprland registers a submap only when it holds a bind, hence the
            -- one on a key that does not exist on any of the keyboards.
            hl.define_submap("voxtype_suppress", function()
              hl.bind("F24", hl.dsp.no_op(), { description = "Nothing: keeps this submap registered" })
            end)
          '';

        settings = {
          monitor = map (
            m:
            if m.enabled then
              {
                output = m.name;
                mode = "${toString m.width}x${toString m.height}@${toString m.refreshRate}";
                position = "${toString m.x}x${toString m.y}";
                scale = m.scale;
              }
            else
              {
                output = m.name;
                disabled = true;
              }
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

          # device = builtins.trace "${builtins.toString cfg.keyboards}" map (k: {
          device = map (k: {
            name = k.name;
            kb_layout = k.kb_layout;
          }) (cfg.keyboards);

          bind =
            let
              terminal = "kitty";
              # menu = "wofi --allow-images --show=drun --lines=15"; # prompt=""";
              workspaces = map toString (lib.range 1 9);
              directions = {
                h = "left";
                l = "right";
                k = "up";
                j = "down";
              };
              resizes = {
                h = {
                  x = -30;
                  y = 0;
                };
                l = {
                  x = 30;
                  y = 0;
                };
                k = {
                  x = 0;
                  y = -30;
                };
                j = {
                  x = 0;
                  y = 30;
                };
              };
            in
            [
              # "SUPER + O": hyprctl switchxkblayout at-translated-set-2-keyboard next
              (bindExec "SUPER + Return" "Open a terminal" terminal)
              # SUPER + D is the shell's launcher now, see below.
              # (bindExec "SUPER + D" menu)
              (bind "SUPER + Q" "Close the window" "hl.dsp.window.close()")
              (bind "SUPER + SHIFT + G" "Exit Hyprland" "hl.dsp.exit()")
              (bind "SUPER + F" "Toggle floating" ''hl.dsp.window.float({ action = "toggle" })'')
              (bind "SUPER + A" "Open the next window to the left" ''hl.dsp.layout("preselect l")'')
              (bind "SUPER + P" "Float and pin the window" ''
                function()
                  hl.dispatch(hl.dsp.window.float({ action = "enable" }))
                  hl.dispatch(hl.dsp.window.pin())
                end'')
              # "SUPER + B", fullscreenstate 1: SUPER + B is the keys sheet now, see
              # below; revive this one on another key.
              (bind "SUPER + R" "Fullscreen" "hl.dsp.window.fullscreen()")
              # Screenshot selected area to clipboard.
              (bindExec "Print" "Screenshot an area to the clipboard" "grimblast copy area")
              (bindExec "SUPER + S" "Screenshot an area to the clipboard" "grimblast copy area")
              # "Print": grimblast save area /tmp/screenshot.png && satty -f /tmp/screenshot.png
              # "Print": grim -g "$(slurp)" - | swappy -f -

              (bindExec "XF86AudioPlay" "Play or pause" "playerctl play-pause") # the stupid key is called play , but it toggles
              (bindExec "XF86AudioNext" "Next track" "playerctl next")
              (bindExec "XF86AudioPrev" "Previous track" "playerctl previous")

              (bind "SUPER + T" "Tag Rusty's Retirement for the right side"
                ''hl.dsp.window.tag({ tag = "+rtr_right", window = "title:(Rusty's Retirement)" })''
              )
              (bindExec "SUPER + T" "Reserve the right side of DP-1" "hyprctl monitor DP-1,addreserved,0,0,296,0")

              (bind "SUPER + Y" "Untag Rusty's Retirement from the right side"
                ''hl.dsp.window.tag({ tag = "-rtr_right", window = "title:(Rusty's Retirement)" })''
              )
              (bindExec "SUPER + Y" "Reserve the left side of DP-1" "hyprctl monitor DP-1,addreserved,0,296,0,0")

              # Toggle dictation. Voxtype drops the compositor into the empty
              # `voxtype_suppress` submap for the instant it injects each chunk
              # of streamed text (via [output] pre/post_output_command in
              # voxtype.nix), so its synthetic keystrokes (letters, BackSpace,
              # etc.) can't trigger any window bind. See the submap in extraConfig.
              (bindExec "SUPER + E" "Toggle dictation" "voxtype record toggle")
            ]
            ++
              # keyboard layout switching
              (map (k: bindExec "SUPER + O" "Next keyboard layout" "hyprctl switchxkblayout ${k.name} next") (
                builtins.filter (k: k.multilang) cfg.keyboards
              ))
            ++
              # change workspace
              (map (
                n: bind "SUPER + ${n}" "Go to workspace ${n}" ''hl.dsp.focus({ workspace = "${n}" })''
              ) workspaces)
            ++ [ (bind "SUPER + 0" "Go to workspace 10" ''hl.dsp.focus({ workspace = "10" })'') ]
            ++

              # move window to workspace
              (map (
                n:
                bind "SUPER + SHIFT + ${n}" "Move the window to workspace ${n}"
                  ''hl.dsp.window.move({ workspace = "${n}" })''
              ) workspaces)
            ++ [
              (bind "SUPER + SHIFT + 0" "Move the window to workspace 10"
                ''hl.dsp.window.move({ workspace = "10" })''
              )
            ]
            ++

              # move focus
              (lib.mapAttrsToList (
                key: direction:
                bind "SUPER + ${key}" "Focus the window ${direction}"
                  ''hl.dsp.focus({ direction = "${direction}" })''
              ) directions)
            ++

              # resize window
              (lib.mapAttrsToList (
                key: size:
                bind "SUPER + ALT + ${key}" "Resize the window"
                  "hl.dsp.window.resize({ x = ${toString size.x}, y = ${toString size.y}, relative = true })"
              ) resizes)
            ++

              # swap windows
              (lib.mapAttrsToList (
                key: direction:
                bind "SUPER + SHIFT + ${key}" "Swap the window ${direction}"
                  ''hl.dsp.window.swap({ direction = "${direction}" })''
              ) directions)
            ++ [
              # The quickshell launcher: a centred overlay window, opened from the
              # keyboard only: it deliberately has no button anywhere in the shell.
              # `global` delivers the press straight to the running shell over
              # hyprland-global-shortcuts-v1 (the shell registers `quickshell:launcher`
              # as a GlobalShortcut), so nothing is forked on the keypress. It has
              # SUPER + D now, the key wofi used to have, because the shell is started
              # by a systemd unit that is always up: a `global` bind does nothing
              # at all when the shell is not running.
              #
              # A description so `hyprctl binds` reports what it is.
              # Themes and wallpapers is the same shape as the launcher: a centred
              # overlay, registered as `quickshell:looks` at ShellRoot level, so it
              # gets the same kind of bind. SUPER + SHIFT + T because SUPER + T is
              # already the Rusty's Retirement tag, and T is still the letter he will
              # reach for; SUPER + W and SUPER + C were the alternatives and both burn
              # a bare SUPER slot on something he touches twice a month.
              #
              # The keys sheet (the Dactyl's layers, these binds, and Neovim's
              # keymaps on three pages) is the third overlay of that shape, and it
              # is the one he reaches for precisely when he cannot remember a key.
              # So it gets a bare SUPER slot rather than a shifted one.
              #
              # SUPER + B, for board and for binds, because the letter it wants is gone:
              # SUPER + K, SUPER + SHIFT + K and SUPER + ALT + K are movefocus, swapwindow
              # and resizeactive up: the vim-direction cluster owns the whole K family
              # and none of it is negotiable. SUPER + SLASH is the conventional help
              # key and was rejected on the hardware: the G512 is Swedish-only
              # (hosts/pc/home.nix), where slash lives on SHIFT+7, i.e. the
              # movetoworkspace-7 chord. SUPER + B itself only ever held a
              # fullscreenstate bind that has been commented out since SUPER + R took
              # over fullscreen.
              #
              # The rail's other pages get nothing here on purpose. Their IpcHandler
              # lives inside the per-screen `Variants` block, so a GlobalShortcut
              # beside it would register once per monitor under one name. Giving the
              # control centre a key means first hoisting it out of `Variants`, and
              # that is a change to the shell, not to this file.
              (bind "SUPER + D" "Toggle the application launcher" ''hl.dsp.global("quickshell:launcher")'')
              (bind "SUPER + SHIFT + T" "Toggle the themes and wallpapers overlay"
                ''hl.dsp.global("quickshell:looks")''
              )
              (bind "SUPER + B" "Toggle the keyboard and keybind sheet" ''hl.dsp.global("quickshell:keys")'')

              (bindWith "SUPER + mouse:272" "Move the window with the mouse" "hl.dsp.window.drag()" {
                mouse = true;
              })
              (bindWith "SUPER + mouse:273" "Resize the window with the mouse" "hl.dsp.window.resize()" {
                mouse = true;
              })
            ]
            ++
              # locked -> do stuff even when locked
              # repeating -> repeats when key is held
              # These stay plain wpctl/brightnessctl calls: the shell's OSD has
              # nothing to be told. It watches its own Audio.vol/Audio.muted and
              # Sys.brightness properties, so the change signal *is* the event no
              # matter who caused it: a media key, pavucontrol, or the shell's own
              # slider. See Osd.qml. Routing the keys through the shell would only
              # add a fork per keypress and break them whenever it is not running.
              (map
                (
                  {
                    key,
                    description,
                    command,
                  }:
                  bindWith key description "hl.dsp.exec_cmd(${toLua command})" {
                    locked = true;
                    repeating = true;
                  }
                )
                [
                  # Example volume button that allows press and hold, volume limited to 150%
                  {
                    key = "XF86AudioRaiseVolume";
                    description = "Volume up";
                    command = "wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 2%+";
                  }
                  # Example volume button that will activate even while an input inhibitor is active
                  {
                    key = "XF86AudioLowerVolume";
                    description = "Volume down";
                    command = "wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-";
                  }

                  # -c backlight, because brightnessctl with no class falls back to
                  # the keyboard LEDs when there is no backlight: on pc, plain
                  # `brightnessctl set 10%+` was toggling the numlock light. With the
                  # class pinned it is the screen or nothing (pc has no backlight at
                  # all, so it is a no-op there and the OSD correctly stays away).
                  {
                    key = "xf86monbrightnessup";
                    description = "Brightness up";
                    command = "brightnessctl -c backlight set 10%+";
                  }
                  {
                    key = "SUPER + U";
                    description = "Brightness up";
                    command = "brightnessctl -c backlight set 10%+";
                  }
                  {
                    key = "xf86monbrightnessdown";
                    description = "Brightness down";
                    command = "brightnessctl -c backlight set 10%-";
                  }
                  {
                    key = "SUPER + I";
                    description = "Brightness down";
                    command = "brightnessctl -c backlight set 10%-";
                  }
                ]
              )
            ++ [
              (bindWith "XF86AudioMute" "Mute" ''hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")'' {
                locked = true;
              })
            ];

          workspace_rule = [
            {
              workspace = "w[tv1]";
              gaps_out = 0;
              gaps_in = 0;
            }
            {
              workspace = "f[1]";
              gaps_out = 0;
              gaps_in = 0;
            }
          ]
          ++ (map (w: {
            workspace = toString w.ID;
            monitor = w.monitor;
            default = w.default;
          }) cfg.workspaces);

          layer_rule = [
            # The notification popups are deliberately translucent; blurring what
            # is behind them is what keeps the text readable over a busy
            # wallpaper. ignorealpha skips the fully transparent margin around
            # each card so the blur stops at the card itself.
            {
              match.namespace = "notifications";
              blur = true;
              ignore_alpha = 0.4;
            }
          ];

          window_rule = [
            # Ref https://wiki.hyprland.org/Configuring/Workspace-Rules/
            # "Smart gaps" / "No gaps when only"
            {
              match = {
                float = false;
                workspace = "w[tv1]";
              };
              border_size = 0;
              rounding = 0;
            }
            {
              match = {
                float = false;
                workspace = "f[1]";
              };
              border_size = 0;
              rounding = 0;
            }

            {
              match.title = ".*Picture.in.Picture.*";
              float = true;
              pin = true;
              keep_aspect_ratio = true;
              border_size = 0;
              rounding = 0;
              size = [
                "monitor_w*0.4"
                "monitor_h*0.4"
              ];
              move = [
                0
                30
              ];
            }

            # "suppressevent fullscreen, class:.*" # You'll probably like this.

            {
              match.float = true;
              rounding = 10;
            }

            # Erik's T3 Code desktop app lives on workspace 1, whatever has focus
            # when it opens (2026-10-25: the 06:05 relaunch ran while focus sat on
            # the headless AGENT-1 output and the window opened on workspace
            # `agent`, out of Erik's reach). Workspace 1 is bound to the main
            # monitor in `workspaces` (hosts/pc/home.nix). Silent, so a relaunch
            # never pulls the view away. The "Speak reply" card shares the app-id
            # and has its own floating rules (modules/home-manager/speak); the
            # dev build is a different class, kept on AGENT-1 by computer-use.
            {
              match = {
                class = "^(com\\.t3tools\\.T3Code)$";
                title = "negative:^(T3 Code — Speak reply)$";
              };
              workspace = "1 silent";
            }

            # Rusty Retirement Game Overlay
            {
              match.title = "(Rusty's Retirement)";
              tag = "+rtr";
            }
            {
              match.tag = "rtr";
              float = true;
              # Remove this if you don't want rtr to appear in all workspaces
              pin = true;
              # size = 100% 350
              size = [
                "100%"
                "296"
              ];
              # Move rtr to buttom of the screen
              # move = 0 730
              move = [
                0
                784
              ];
              no_blur = true;
              no_shadow = true;
              border_size = 0;
              # override rounded corners
              rounding = 0;
              opacity = "1.0 override";
            }
            # rules for having it on the right side
            # size = 296 100%, tag rtr_right
          ];

          curve = {
            _args = [
              "myBezier"
              {
                type = "bezier";
                points = [
                  [
                    0.05
                    0.9
                  ]
                  [
                    0.1
                    1.05
                  ]
                ];
              }
            ];
          };

          # Some default animations, see https://wiki.hyprland.org/Configuring/Animations/ for more
          animation = [
            {
              leaf = "windows";
              enabled = true;
              speed = 7;
              bezier = "myBezier";
            }
            {
              leaf = "windowsOut";
              enabled = true;
              speed = 7;
              bezier = "default";
              style = "popin 80%";
            }
            {
              leaf = "border";
              enabled = true;
              speed = 10;
              bezier = "default";
            }
            {
              leaf = "borderangle";
              enabled = true;
              speed = 8;
              bezier = "default";
            }
            {
              leaf = "fade";
              enabled = true;
              speed = 7;
              bezier = "default";
            }
            {
              leaf = "workspaces";
              enabled = false;
              speed = 6;
              bezier = "default";
            }
          ];

          # For all categories, see https://wiki.hyprland.org/Configuring/Variables/
          config = {
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

            general = {
              # See https://wiki.hyprland.org/Configuring/Variables/ for more
              gaps_in = 0;
              gaps_out = 0;
              border_size = 2;
              col = {
                active_border = "rgba(33ccffee)"; # rgba(00ff99ee) 90deg
                inactive_border = "rgba(595959aa)";
              };

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

            # master = {
            #   # See https://wiki.hyprland.org/Configuring/Master-Layout/ for more
            #   # new_is_master = true;
            #   # no_gaps_when_only = 1;
            # };

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
    };
}
