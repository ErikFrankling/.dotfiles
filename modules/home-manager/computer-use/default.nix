{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

let
  hyprland = osConfig.programs.hyprland.package;
  backend = pkgs.callPackage ../../../packages/computer-use { inherit hyprland; };
  runtimePath = lib.makeBinPath [
    hyprland
    pkgs.systemd
    pkgs.grim
    pkgs.tigervnc
  ];
  pythonSource = pkgs.runCommand "agent-desktop-python" { } ''
    mkdir -p $out
    cp ${./desktop.py} $out/desktop.py
    cp ${./supervisor.py} $out/supervisor.py
    cp ${./test_policy.py} $out/test_policy.py
    PYTHONDONTWRITEBYTECODE=1 ${pkgs.python3}/bin/python3 $out/test_policy.py
  '';
  desktop = pkgs.writeShellScriptBin "agent-desktop" ''
    export PATH=${runtimePath}:"$PATH"
    exec ${pkgs.python3}/bin/python3 ${./desktop.py} "$@"
  '';
  bridge = pkgs.writeShellScriptBin "agent-computer-use" ''
    export PATH=${runtimePath}:"$PATH"
    exec ${pkgs.python3}/bin/python3 -c '
    import os, sys
    sys.path.insert(0, ${builtins.toJSON "${pythonSource}"})
    from desktop import session
    session()
    os.execv(${builtins.toJSON "${backend}/bin/hyprland-computer-use"},
             ["hyprland-computer-use", *sys.argv[1:]])
    ' "$@"
  '';
  package = pkgs.symlinkJoin {
    name = "agent-desktop";
    paths = [
      desktop
      bridge
    ];
  };
  sessionUnit = {
    After = [
      "hyprland-session.target"
      "agent-desktop.service"
    ];
    Requires = [ "agent-desktop.service" ];
    PartOf = [ "hyprland-session.target" ];
  };
  profile = "${config.xdg.dataHome}/agent-desktop/firefox";
in
{
  options.programs.agent-desktop.enable = lib.mkEnableOption "experimental agent desktop (disabled after human keyboard regression)";
  options.programs.agent-desktop.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = package;
    description = "Shared agent desktop commands and MCP bridge.";
  };

  config = lib.mkIf config.programs.agent-desktop.enable {
    home.packages = [ package ];

    # One immutable plugin, built with the same compiler/dependencies as the
    # actual compositor. Do not hot-unload a plugin that owns a Wayland seat.
    wayland.windowManager.hyprland.settings = {
      # A gap keeps ordinary pointer motion from entering the headless output.
      monitor = [ "AGENT-1,1920x1080@30,10000x0,1" ];
      workspace = [ "name:agent,monitor:AGENT-1,default:true,persistent:true" ];
      windowrule = [
        "workspace name:agent silent, match:class ^(agent-firefox)$"
        "no_initial_focus on, match:class ^(agent-firefox)$"
        "focus_on_activate off, match:class ^(agent-firefox)$"
      ];
    };

    systemd.user.services.agent-desktop = {
      Unit = {
        Description = "Agent headless output in the current Hyprland session";
        After = [ "hyprland-session.target" ];
        PartOf = [ "hyprland-session.target" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${package}/bin/agent-desktop ensure-output";
        RemainAfterExit = true;
        TimeoutStartSec = 30;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.agent-computer-use = {
      Unit = sessionUnit // {
        Description = "Computer-use MCP broker with independent input";
        After = sessionUnit.After ++ [ "agent-input-plugin.service" ];
        Requires = sessionUnit.Requires ++ [ "agent-input-plugin.service" ];
        StartLimitIntervalSec = 0;
      };
      Service = {
        ExecStart = "${package}/bin/agent-computer-use serve";
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.agent-input-plugin = {
      Unit = sessionUnit // {
        Description = "Load the Nix-built independent input plugin";
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${package}/bin/agent-desktop load-plugin ${backend.plugin}/lib/guard-seat.so";
        RemainAfterExit = true;
        TimeoutStartSec = 30;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.agent-desktop-permissions = {
      Unit = sessionUnit // {
        Description = "Approve computer-use requests confined to agent windows";
        After = sessionUnit.After ++ [ "agent-computer-use.service" ];
        Requires = sessionUnit.Requires ++ [ "agent-computer-use.service" ];
      };
      Service = {
        ExecStart = "${pkgs.python3}/bin/python3 ${pythonSource}/supervisor.py";
        Environment = [
          "PATH=${runtimePath}"
          "PYTHONDONTWRITEBYTECODE=1"
        ];
        Restart = "always";
        RestartSec = 3;
        UMask = "0077";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.agent-desktop-vnc = {
      Unit = sessionUnit // {
        Description = "View-only agent desktop on localhost:5903";
      };
      Service = {
        ExecStart = "${package}/bin/agent-desktop exec-session ${pkgs.wayvnc}/bin/wayvnc --disable-input --disable-resizing --output=AGENT-1 --max-fps=30 --socket=%t/wayvnc-agent.sock 127.0.0.1 5903";
        Restart = "always";
        RestartSec = 3;
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    systemd.user.services.agent-firefox = {
      Unit = sessionUnit // {
        Description = "Persistent Firefox for the agent workspace";
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${profile}";
        ExecStart = "${package}/bin/agent-desktop exec-session ${osConfig.programs.firefox.finalPackage}/bin/firefox --no-remote --name agent-firefox --profile ${profile} about:blank";
        Environment = [
          "MOZ_ENABLE_WAYLAND=1"
          "GDK_BACKEND=wayland"
          "GDK_SCALE=1"
        ];
        Restart = "on-failure";
        RestartSec = 5;
        UMask = "0077";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    home.file =
      lib.genAttrs
        [
          ".agents/skills/computer-use"
          ".claude/skills/computer-use"
          ".codex/skills/computer-use"
        ]
        (_: {
          source = ./skill/computer-use;
        });
  };
}
