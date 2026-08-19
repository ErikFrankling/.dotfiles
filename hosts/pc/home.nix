{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  codexHome = "${config.home.homeDirectory}/.codex";
  t3CodexHome = "${config.home.homeDirectory}/.codex-t3";
  t3CodexPrepare = pkgs.writeShellScript "t3-code-codex-prepare" ''
    mkdir -p ${lib.escapeShellArg t3CodexHome}
    if [[ ! -e ${lib.escapeShellArg "${t3CodexHome}/state_5.sqlite"} ]]; then
      ${pkgs.sqlite}/bin/sqlite3 \
        ${lib.escapeShellArg "${codexHome}/state_5.sqlite"} \
        ".backup '${t3CodexHome}/state_5.sqlite'"
    fi
  '';
in
{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
    ../../modules/home-manager/vm-host.nix
    inputs.time.homeManagerModules.default
    # ../../modules/home-manager/noctalia.nix
  ];

  # Minute-by-minute activity tracking. The agent only screenshots and posts;
  # the server in the cluster holds the API key and does the classifying.
  services.time-agent = {
    enable = true;
    server = "https://time.erikfrankling.duckdns.org";
    device = "pc";
    # Near-live dashboard numbers: scan local git and agent transcripts every
    # minute (cheap — mtime caches skip unchanged sources) and post them.
    collect = {
      enable = true;
      roots = [ "~/projects" ];
      githubUser = "ErikFrankling";
    };
    metrics.enable = true;
    note = ''
      This machine runs AI computer-use sessions (codex). An agent can open
      windows, type, and drive the screen with nobody present, and one monitor
      is dedicated to it. Screen activity here is therefore NOT evidence the
      user is at the machine -- rely on the human input counters for that.
    '';
  };

  # Keep T3's mutable Codex database separate while sharing the authenticated
  # account, configuration, sessions, and user extensions.
  home.file = {
    ".codex-t3/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/auth.json";
    ".codex-t3/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/config.toml";
    ".codex-t3/sessions".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/sessions";
    ".codex-t3/archived_sessions".source =
      config.lib.file.mkOutOfStoreSymlink "${codexHome}/archived_sessions";
    ".codex-t3/attachments".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/attachments";
    ".codex-t3/skills".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/skills";
    ".codex-t3/rules".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/rules";
    ".codex-t3/plugins".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/plugins";
  };

  home.packages = with pkgs; [
    prismlauncher
  ];

  systemd.user.services.t3code = {
    Unit.Description = "T3 Code web server";

    Service = {
      ExecStartPre = t3CodexPrepare;
      ExecStart = "${pkgs.t3code}/bin/t3 serve --host 0.0.0.0 --port 3773";
      Environment = [
        "CODEX_HOME=${t3CodexHome}"
        # LAN/VPN-only deployment: serve without pairing, cookies, or tokens.
        "T3CODE_UNSAFE_NO_AUTH=1"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      WorkingDirectory = config.home.homeDirectory;
    };

    Install.WantedBy = [ "default.target" ];
  };

  home.sessionVariables = {
    # LIBSEAT_BACKEND = "logind";
    # AQ_DRM_DEVICES = "/dev/dri/card1"; # Disabled: crashes when card1 is missing
    # HYPRLAND_TRACE = "1";
    # AQ_TRACE = "1";
    # MESA_LOADER_DRIVER_OVERRIDE="radeonsi";
    # EGL_PLATFORM="GBM";
    # WLR_NO_HARDWARE_CURSORS="1";
  };

  # wayland.windowManager.hyprland.settings = {
  #   # mouse = {
  #   #   sensitivity = "0.2";
  #   #   scroll_factor = "0.5";
  #   # };
  #
  #   device = [
  #     {
  #       name = "tshort-dactyl-manuform-(5x6)";
  #       kb_layout = "us";
  #     }
  #     {
  #       name = "logitech-g512-carbon-tactile";
  #       kb_layout = "se";
  #     }
  #   ];
  # };

  hyprland =
    let
      monitor_1 = "HDMI-A-1";
      monitor_2 = "DP-3";
    in
    {
      keyboards = [
        {
          name = "erik-frankling-dactyl_manuform_5x6_64";
          kb_layout = "us, se";
          multilang = true;
        }
        {
          name = "logitech-g512-carbon-tactile";
          kb_layout = "se";
          multilang = false;
        }
      ];
      monitors = [
        {
          name = monitor_1;
          width = 3840;
          height = 2160;
          # width = 2560;
          # height = 1440;
          refreshRate = 60;
          x = 1920;
          # x = 2560;
          scale = "2";
        }
        {
          name = monitor_2;
          width = 3840;
          height = 2160;
          # width = 2560;
          # height = 1440;
          refreshRate = 60;
          x = 0;
          scale = "2";
        }
      ];
      initWindows = [
        {
          exec = "kitty";
          monitor = monitor_1;
          workspace = 1;
        }
        {
          exec = "kitty";
          monitor = monitor_1;
          workspace = 2;
        }
        {
          exec = "firefox";
          monitor = monitor_1;
          workspace = 3;
        }
        {
          exec = "obsidian";
          monitor = monitor_2;
          workspace = 9;
        }
        {
          exec = "webcord";
          monitor = monitor_2;
          workspace = 10;
        }
        {
          exec = "spotify";
          monitor = monitor_2;
          workspace = 10;
        }
      ];

      workspaces = [
        {
          ID = 1;
          monitor = monitor_1;
          default = true;
        }
        {
          ID = 2;
          monitor = monitor_1;
        }
        {
          ID = 3;
          monitor = monitor_1;
        }
        {
          ID = 9;
          monitor = monitor_2;
        }
        {
          ID = 10;
          monitor = monitor_2;
          # default = true;
        }
      ];
    };
}
