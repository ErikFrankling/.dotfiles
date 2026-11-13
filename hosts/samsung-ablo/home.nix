{
  inputs,
  lib,
  pkgs,
  ...
}:
let
  # Hyprland's disconnect fallback is the first remaining monitor, which can
  # be AGENT-1. Kanshi configures outputs but cannot relocate workspaces: use
  # its native exec hook and Hyprland's Lua API, leaving agent workspaces alone.
  # A store script is necessary because kanshi reparses/escapes inline Lua
  # quotes before passing exec to sh. It also keeps Lua out of kanshi syntax.
  moveWorkspaces =
    monitor:
    toString (
      pkgs.writeShellScript "dock-workspaces" (
        "hyprctl -i 0 eval "
        + lib.escapeShellArg ''
          for _, workspace in ipairs(hl.get_workspaces()) do
            if workspace.name ~= "agent" and workspace.name ~= "agent-park" then
              hl.dispatch(hl.dsp.workspace.move({ workspace = workspace.addressable_name, monitor = ${builtins.toJSON monitor} }))
            end
          end
          hl.dispatch(hl.dsp.focus({ monitor = ${builtins.toJSON monitor} }))
        ''
      )
    );

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
in
{
  imports = [
    ./aws.nix
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/computer-use
    ../../modules/home-manager/print
    ../../modules/home-manager/auto-update
    ../../modules/home-manager/machines
    ../../modules/home-manager/notify # phone notifications skill
    ../../modules/home-manager/bro
    ../../modules/home-manager/speak # `speak` tool: refuses here (PC speakers only)
    inputs.time.homeManagerModules.agent-v2
    ./t3code.nix # work agents run here, not on the pc
    ../../modules/home-manager/t3code-connect.nix # T3 Connect: remote access, webhook URLs
  ];

  # Ablo marketing 3D work (Blender scenes, MCP for Blender add-on).
  home.packages = [ pkgs.blender ];

  # Local browser, agent monitor and input seat. Harnesses get these local
  # MCP servers from ai.nix; work desktop control stays on this laptop.
  programs.agent-desktop.enable = true;

  # Native AWS CLI SSO; authenticate with `aws sso login --sso-session ablo`.
  # Account/role profiles are added only after Identity Center lists access.
  programs.awscli = {
    enable = true;
    settings."sso-session ablo" = {
      sso_start_url = "https://d-c36766d895.awsapps.com/start";
      sso_region = "eu-north-1";
      sso_registration_scopes = "sso:account:access";
    };
  };

  # Time v2: screen, input, lid, lock, battery and Wi-Fi each minute, to the
  # local Alloy (queued on disk while away from home).
  services.time-agent-v2 = {
    enable = true;
    device = "samsung-ablo";
  };

  # Nothing on the iGPU worth watching (same as the framework).
  programs.erikshell.metrics.gpu = false;

  # At the desk the KVM gives the laptop the pc's two screens; the built-in
  # one turns off, as on the framework. Matched by model, not connector: the
  # KVM's DP-n names change each time it switches.
  services.kanshi = {
    enable = true;
    systemdTarget = "hyprland-session.target";
    settings = [
      # Positions come from the shell's displays window (erikshell
      # DisplaysWindow.qml), which writes `output "<criteria>" position X,Y`
      # defaults here and runs `kanshictl reload`. kanshi applies a default
      # only where a profile uses the identical criteria string, so profiles
      # name outputs the way the window does: eDP-1, or "<make> <model> *".
      # Profiles set no position for those outputs, or the default is ignored.
      { include = "$HOME/.local/state/kanshi/positions"; }
      {
        profile.name = "office";
        profile.exec = [
          (moveWorkspaces "desc:Dell Inc. DELL U2724DE")
          "grep -q open /proc/acpi/button/lid/*/state && ${kanshictl} switch office-lid-open"
        ];
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "Dell Inc. DELL U2724DE *";
            status = "enable";
            mode = "2560x1440@120Hz";
            scale = 1.333333;
          }
          {
            criteria = "AGENT-1";
            status = "enable";
            position = "10000,0";
          }
        ];
      }
      # Lid open at the office (a call that needs the webcam): the built-in
      # screen joins, below the Dell. Same outputs as "office", so kanshi picks
      # "office" on hotplug and its exec switches here when the lid is open;
      # the lid binds below switch between the two.
      {
        profile.name = "office-lid-open";
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
          {
            criteria = "Dell Inc. DELL U2724DE *";
            status = "enable";
            mode = "2560x1440@120Hz";
            scale = 1.333333;
          }
          {
            criteria = "AGENT-1";
            status = "enable";
            position = "10000,0";
          }
        ];
      }
      {
        profile.name = "undocked";
        profile.exec = [ (moveWorkspaces "eDP-1") ];
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "enable";
          }
          {
            criteria = "AGENT-1";
            status = "enable";
            position = "10000,0";
          }
        ];
      }
      {
        profile.name = "docked";
        profile.exec = [ (moveWorkspaces "desc:Samsung Electric Company U28E590") ];
        profile.outputs = [
          {
            criteria = "eDP-1";
            status = "disable";
          }
          {
            criteria = "Samsung Electric Company U28E590 *";
            status = "enable";
          }
          {
            criteria = "Samsung Electric Company U28D590 *";
            status = "enable";
          }
          {
            criteria = "AGENT-1";
            status = "enable";
            position = "10000,0";
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

  # At the office dock the built-in screen follows the lid. Away from the
  # office dock the "office" profiles do not match and kanshictl just fails.
  wayland.windowManager.hyprland.settings.bind = [
    (lidBind "off" "Lid opened: built-in screen on at the office" "office-lid-open")
    (lidBind "on" "Lid closed: built-in screen off at the office" "office")
  ];

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
        height = 1800;
        scale = "2";
        refreshRate = 120;
        x = 0;
        y = 0;
      }
      # The KVM cannot carry both screens at 4K/60. These are the modes
      # verified together on the laptop; the U28D590 has no 4K/30 mode.
      {
        name = "desc:Samsung Electric Company U28E590";
        width = 3840;
        height = 2160;
        refreshRate = 30;
        scale = "2";
        x = 0;
        y = 0;
      }
      {
        name = "desc:Samsung Electric Company U28D590";
        width = 2560;
        height = 1440;
        refreshRate = 60;
        scale = "2";
        x = 1920;
        y = 0;
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
    ];
  };
}
