{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:

let
  system = pkgs.stdenv.hostPlatform.system;
  codexHome = "${config.home.homeDirectory}/.codex";
  t3CodexHome = "${config.home.homeDirectory}/.codex-t3";
  codexComputerUseMonitor = "codex-computer-use";
  codexCli = inputs.llm-agents.packages.${system}.codex;
  t3Cli =
    (inputs.t3code-nix.packages.${system}.t3code-cli.override { codex = codexCli; }).overrideAttrs
      (oldAttrs: {
        postPatch = (oldAttrs.postPatch or "") + ''
          node <<'NODE'
          const fs = require("fs");
          const bundlePath = "dist/bin.mjs";
          let source = fs.readFileSync(bundlePath, "utf8");

          function replaceOnce(before, after, description) {
            if (!source.includes(before)) {
              throw new Error("T3 compatibility patch no longer matches: " + description);
            }
            source = source.replace(before, after);
          }

          replaceOnce(
            "const V2ModelListResponse__ReasoningEffort = Schema.Literals([\n\t\"none\",\n\t\"minimal\",\n\t\"low\",\n\t\"medium\",\n\t\"high\",\n\t\"xhigh\"\n]).annotate",
            "const V2ModelListResponse__ReasoningEffort = Schema.String.annotate",
            "Codex model reasoning effort schema",
          );
          replaceOnce(
            "const REASONING_EFFORT_LABELS = {\n\tnone: \"None\",\n\tminimal: \"Minimal\",\n\tlow: \"Low\",\n\tmedium: \"Medium\",\n\thigh: \"High\",\n\txhigh: \"Extra High\"\n};",
            "const REASONING_EFFORT_LABELS = {\n\tnone: \"None\",\n\tminimal: \"Minimal\",\n\tlow: \"Low\",\n\tmedium: \"Medium\",\n\thigh: \"High\",\n\txhigh: \"Extra High\",\n\tmax: \"Max\",\n\tultra: \"Ultra\"\n};",
            "Codex reasoning effort labels",
          );

          const labelNeedle = "label: REASONING_EFFORT_LABELS[reasoningEffort]";
          const labelCount = source.split(labelNeedle).length - 1;
          if (labelCount !== 2) {
            throw new Error("T3 compatibility patch found " + labelCount + " reasoning labels");
          }
          source = source.replaceAll(
            labelNeedle,
            "label: REASONING_EFFORT_LABELS[reasoningEffort] ?? reasoningEffort",
          );

          replaceOnce(
            "const toProtocolMessage = (requestId, fields) => ({\n\tid: requestId,",
            "const toProtocolMessage = (requestId, fields) => ({\n\tjsonrpc: \"2.0\",\n\tid: requestId,",
            "Codex JSON-RPC response envelope",
          );
          replaceOnce(
            "\t\tyield* offerOutgoing({\n\t\t\tid: requestId,\n\t\t\tmethod,",
            "\t\tyield* offerOutgoing({\n\t\t\tjsonrpc: \"2.0\",\n\t\t\tid: requestId,\n\t\t\tmethod,",
            "Codex JSON-RPC request envelope",
          );
          replaceOnce(
            "\tconst notify = (method, payload) => offerOutgoing({\n\t\tmethod,",
            "\tconst notify = (method, payload) => offerOutgoing({\n\t\tjsonrpc: \"2.0\",\n\t\tmethod,",
            "Codex JSON-RPC notification envelope",
          );

          fs.writeFileSync(bundlePath, source);
          NODE
        '';
      });
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
    # ../../modules/home-manager/noctalia.nix
  ];

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
    t3Cli
  ];

  systemd.user.services.t3code = {
    Unit.Description = "T3 Code web server";

    Service = {
      ExecStartPre = t3CodexPrepare;
      ExecStart = "${t3Cli}/bin/t3 serve --host 0.0.0.0 --port 3773";
      Environment = [ "CODEX_HOME=${t3CodexHome}" ];
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

  wayland.windowManager.hyprland.settings.exec-once = [
    "hyprctl output create headless ${codexComputerUseMonitor}"
  ];

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
        {
          name = codexComputerUseMonitor;
          width = 1920;
          height = 1080;
          refreshRate = 60;
          x = 0;
          scale = "1";
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
