{
  inputs,
  pkgs,
  lib,
  ...
}:
let
  # The office dock, as on the Ablo laptop (hosts/samsung-ablo/home.nix): the
  # built-in screen follows the lid while the office Dell is attached.
  kanshictl = lib.getExe' pkgs.kanshi "kanshictl";
  lidBind = state: description: profile: {
    _args = [
      "switch:${state}:Lid Switch"
      (lib.generators.mkLuaInline "hl.dsp.exec_cmd(${builtins.toJSON "${kanshictl} switch ${profile}"})")
      {
        inherit description;
        locked = true;
      }
    ];
  };
  dell = {
    criteria = "Dell Inc. DELL U2724DE *";
    status = "enable";
    mode = "2560x1440@120Hz";
    scale = 1.333333;
  };
in
{
  # Keep the running 0.56 session's bindings when Home Manager installs Lua.
  # Hyprland 0.57 ignores this file; remove after Framework has logged into 0.57.
  xdg.configFile."hypr/hyprland.conf".source = ./hyprland-0.56.conf;

  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
    ../../modules/home-manager/auto-update
    ../../modules/home-manager/machines
    ../../modules/home-manager/notify # phone notifications skill
    ../../modules/home-manager/bro
    ../../modules/home-manager/speak # `speak` tool: refuses here (PC speakers only)
    inputs.time.homeManagerModules.agent-v2
  ];

  # Time v2: screen, input, lid, lock, battery and Wi-Fi each minute, to the
  # local Alloy (queued on disk while away from home).
  services.time-agent-v2 = {
    enable = true;
    device = "framework";
  };

  # The laptop does nothing on its iGPU worth watching: no gpu or vram rings
  # in the shell's rail (Erik, 2026-11-06).
  programs.erikshell.metrics.gpu = false;

  wayland.windowManager.hyprland.settings = {
    device = [
      {
        name = "pixa3854:00-093a:0274-touchpad";
        sensitivity = 0.2;
      }
    ];

    # At the office dock the built-in screen follows the lid. Away from the
    # office dock the "office" profiles do not match and kanshictl just fails.
    bind = [
      (lidBind "off" "Lid opened: built-in screen on at the office" "office-lid-open")
      (lidBind "on" "Lid closed: built-in screen off at the office" "office")
    ];
  };

  services.kanshi = {
    enable = true;
    systemdTarget = "hyprland-session.target";

    settings = [
      # Positions come from the shell's displays window (SUPER+SHIFT+D), which
      # writes `output "<criteria>" position X,Y` defaults here; profiles set
      # no position for eDP-1 or the Dell, or those defaults are ignored.
      { include = "$HOME/.local/state/kanshi/positions"; }
      {
        profile.name = "office";
        profile.exec = [
          "grep -q open /proc/acpi/button/lid/*/state && ${kanshictl} switch office-lid-open"
        ];
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          dell
        ];
      }
      # Lid open at the office: the built-in screen joins, below the Dell.
      # Same outputs as "office", so kanshi picks "office" on hotplug and its
      # exec switches here when the lid is open.
      {
        profile.name = "office-lid-open";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
          dell
        ];
      }
      {
        profile.name = "undocked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
        ];
      }
      {
        profile.name = "docked";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "DP-9"; # Change to your monitor name
            status = "enable";
          }
          {
            criteria = "DP-10"; # Change to your second monitor name
            status = "enable";
          }
        ];
      }
      {
        profile.name = "hack";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "DP-4"; # Change to your monitor name
            status = "enable";
          }
        ];
      }
    ];
  };

  # kanshi refuses its whole config when an include is missing. Seeded with
  # the office layout (built-in screen centred below the Dell); the displays
  # window owns the file afterwards.
  home.activation.kanshiPositions = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    f="$HOME/.local/state/kanshi/positions"
    if [ ! -e "$f" ]; then
      run mkdir -p "$(dirname "$f")"
      printf '%s\n' 'output "eDP-1" position 240,1080' 'output "Dell Inc. DELL U2724DE *" position 0,0' > "$f"
    fi
  '';

  hyprland = {
    keyboards = [
      {
        name = "erik-frankling-dactyl_manuform_5x6_64";
        kb_layout = "us, se";
        multilang = true;
      }
      {
        name = "at-translated-set-2-keyboard";
        kb_layout = "us, se";
        multilang = true;
      }
    ];
    monitors = [
      {
        name = "desc:Dell Inc. DELL U2724DE";
        width = 2560;
        height = 1440;
        refreshRate = 120;
        scale = "1.333333";
        x = 0;
        y = 0;
      }
      {
        name = "eDP-1";
        width = 2880;
        height = 1920;
        scale = "2";
        refreshRate = 120;
        x = 0;
        y = 0;
      }
      {
        name = "DP-9";
        width = 3840;
        height = 2160;
        scale = "2";
        refreshRate = 60;
        x = 1920;
        y = 0;
        # enabled = true;
      }
      {
        name = "DP-10";
        width = 3840;
        height = 2160;
        scale = "2";
        refreshRate = 60;
        x = 0;
        y = 0;
        # enabled = true;
      }
      {
        name = "DP-4";
        width = 1920;
        height = 1080;
        scale = "1";
        refreshRate = 60;
        # x = 1920;
        # y = 1080;
        x = 0;
        y = 0;
        # enabled = true;
      }
    ];

    initWindows = [
      {
        exec = "kitty";
        monitor = "eDP-1";
        workspace = 1;
      }
      {
        exec = "kitty";
        monitor = "eDP-1";
        workspace = 2;
      }
      {
        exec = "firefox";
        monitor = "eDP-1";
        workspace = 3;
      }
      {
        exec = "obsidian";
        monitor = "eDP-1";
        workspace = 4;
      }
      {
        exec = "webcord";
        monitor = "eDP-1";
        workspace = 10;
      }
      {
        exec = "spotify";
        monitor = "eDP-1";
        workspace = 10;
      }
    ];

    # workspaces = [
    #   {
    #     ID = 1;
    #     monitor = "eDP-1";
    #     default = true;
    #   }
    #   {
    #     ID = 2;
    #     monitor = "eDP-1";
    #   }
    #   {
    #     ID = 3;
    #     monitor = "eDP-1";
    #   }
    #   {
    #     ID = 4;
    #     monitor = "eDP-1";
    #   }
    #   {
    #     ID = 10;
    #     monitor = "eDP-1";
    #   }
    # ];
  };
  home.activation.configureOpenCodePcServer = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    stateFile="$HOME/.config/ai.opencode.desktop/opencode.global.dat"
    mkdir -p "$(dirname "$stateFile")"
    if [[ ! -s "$stateFile" ]]; then
      printf '{}\n' > "$stateFile"
    fi

    serverState="$(${pkgs.jq}/bin/jq -r '.server // empty' "$stateFile")"
    if [[ -z "$serverState" ]]; then
      serverState='{"list":[],"projects":{},"lastProject":{},"recentlyClosed":{}}'
    fi

    serverState="$(
      ${pkgs.jq}/bin/jq -c \
        --arg url "http://192.168.50.232:4096" \
        --arg name "PC" \
        '
          .list = (
            [
              (.list // [])[] |
              select(
                (if type == "string" then . else (.http.url // .url // "") end) != $url
              )
            ] + [{
              type: "http",
              http: { url: $url },
              displayName: $name
            }]
          )
        ' <<< "$serverState"
    )"

    temporaryFile="$(mktemp "$stateFile.tmp.XXXXXX")"
    ${pkgs.jq}/bin/jq --arg server "$serverState" '.server = $server' "$stateFile" > "$temporaryFile"
    mv "$temporaryFile" "$stateFile"
  '';

}
