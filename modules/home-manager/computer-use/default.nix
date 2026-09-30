{
  config,
  lib,
  pkgs,
  osConfig,
  inputs,
  ...
}:

let
  hyprland = osConfig.programs.hyprland.package;
  system = pkgs.stdenv.hostPlatform.system;
  cuaDriver = inputs.cua.packages.${system}.cua-driver;
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
  liveTest = pkgs.writeShellScriptBin "agent-desktop-self-test" ''
    export PATH=${lib.makeBinPath [ bridge ]}:${runtimePath}:"$PATH"
    exec ${pkgs.python3}/bin/python3 ${./tests/live_e2e.py} "$@"
  '';
  package = pkgs.symlinkJoin {
    name = "agent-desktop";
    paths = [
      desktop
      bridge
      liveTest
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

  # The agent's own browser: a separate Chromium process on AGENT-1 with the
  # agent seat, a permanent profile (LastPass stays logged in) and a loopback
  # DevTools port for Playwright. --hyprland-agent-seat is the opt-in marker
  # the seat plugin and supervisor read from the command line, because
  # Chromium overwrites its environment block at startup.
  chromiumProfile = "${config.xdg.dataHome}/agent-desktop/chromium";
  cdpPort = 9222;
  chromiumFlags = [
    "--user-data-dir=${chromiumProfile}"
    "--password-store=basic"
    "--no-first-run"
    "--no-default-browser-check"
    "--hide-crash-restore-bubble"
    "--ozone-platform=wayland"
  ];
  agentChromiumArgs = lib.escapeShellArgs (
    chromiumFlags
    ++ [
      "--class=agent-chromium"
      "--hyprland-agent-seat"
      "--remote-debugging-port=${toString cdpPort}"
      "--force-renderer-accessibility"
    ]
  );
  # For the rare manual login (LastPass re-login, passkeys, phone approval):
  # the same profile as a normal window on Erik's monitor with his own input.
  browserLogin = pkgs.writeShellScriptBin "agent-browser-login" ''
    set -u
    systemctl --user stop agent-chromium.service
    ${pkgs.chromium}/bin/chromium ${
      lib.escapeShellArgs (chromiumFlags ++ [ "--class=agent-chromium-login" ])
    } "''${1:-chrome-extension://hdokiejnpimakedhajhdlcegeplioahd/vault.html}"
    systemctl --user start agent-chromium.service
    echo "Agent browser is back on AGENT-1."
  '';
  browserLoginDesktop = pkgs.makeDesktopItem {
    name = "agent-browser-login";
    desktopName = "Agent Browser Login";
    comment = "Open the agent's Chromium on this screen to log in (LastPass etc.)";
    exec = "${browserLogin}/bin/agent-browser-login";
    icon = "chromium";
  };

  cuaEnv = {
    CUA_DRIVER_RS_ENABLE_WAYLAND = "1";
    CUA_DRIVER_RS_TELEMETRY_ENABLED = "false";
  };
in
{
  options.programs.agent-desktop.enable = lib.mkEnableOption "agent desktop with independent keyboard and pointer";
  options.programs.agent-desktop.mcpServers = lib.mkOption {
    type = lib.types.attrs;
    readOnly = true;
    default = {
      # Playwright on the agent's Chromium (DevTools protocol, loopback only).
      browser = {
        command = "${pkgs.playwright-mcp}/bin/playwright-mcp";
        args = [
          "--cdp-endpoint"
          "http://127.0.0.1:${toString cdpPort}"
          # Coordinate mouse tools, for canvas pages and iframes such as
          # LastPass's autofill dropdown.
          "--caps"
          "vision"
          "--output-dir"
          "${config.xdg.cacheHome}/playwright-mcp"
        ];
        # The nixpkgs wrapper exports PLAYWRIGHT_MCP_ISOLATED=1 unless this is
        # set, which puts every page in a fresh incognito-like context: no
        # cookies, no LastPass. With it set, pages open in the real profile.
        env.PLAYWRIGHT_MCP_USER_DATA_DIR = chromiumProfile;
      };
      # Cua Driver: windows, accessibility trees, captures, element actions.
      cua = {
        # exec-session supplies HYPRLAND_INSTANCE_SIGNATURE/WAYLAND_DISPLAY,
        # which harness shells often lack; without them it finds no windows.
        command = "${package}/bin/agent-desktop";
        args = [
          "exec-session"
          "${cuaDriver}/bin/cua-driver"
          "mcp"
        ];
        env = cuaEnv;
      };
      # Raw keyboard/pointer on the agent seat, window capture and recording.
      agent-seat = {
        command = "${package}/bin/agent-computer-use";
        args = [ "mcp" ];
        env = { };
      };
    };
    description = "Local computer-use MCP servers for agent harnesses on this host.";
  };
  options.programs.agent-desktop.package = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default = package;
    description = "Shared agent desktop commands and MCP bridge.";
  };

  config = lib.mkIf config.programs.agent-desktop.enable {
    home.packages = [
      package
      cuaDriver
      browserLogin
      browserLoginDesktop
      pkgs.wf-recorder
      pkgs.grim
    ];

    # One immutable plugin, built with the same compiler/dependencies as the
    # actual compositor. Do not hot-unload a plugin that owns a Wayland seat.
    wayland.windowManager.hyprland.settings = {
      # A gap keeps ordinary pointer motion from entering the headless output.
      monitor = [ "AGENT-1,1920x1080@30,10000x0,1" ];
      # `agent` is what AGENT-1 shows (and the only workspace the seat plugin
      # accepts input on); `agent-park` is a hidden shelf for windows that
      # should not be on screen, e.g. while recording a demo.
      workspace = [
        "name:agent,monitor:AGENT-1,default:true,persistent:true"
        "name:agent-park,monitor:AGENT-1,persistent:true"
      ];
      windowrule = [
        "workspace name:agent silent, match:class ^(agent-chromium)$"
        "no_initial_focus on, match:class ^(agent-chromium)$"
        "focus_on_activate off, match:class ^(agent-chromium)$"

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

    # Powering the monitors off leaves AGENT-1 as the only output, so Hyprland
    # parks the pointer and focus there and keeps them after reconnect.
    systemd.user.services.agent-desktop-return-focus = {
      Unit = sessionUnit // {
        Description = "Return pointer and focus from AGENT-1 when a display connects";
      };
      Service = {
        ExecStart = "${package}/bin/agent-desktop watch-focus";
        Restart = "always";
        RestartSec = 3;
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

    # The same stdio MCP, bridged to streamable HTTP (/mcp) and SSE (/sse) on
    # :4790 so Executor on the homelab can proxy it to every agent. One shared
    # stdio child serves all clients. mcp-proxy has no inbound auth: the host
    # firewall admits only the k3s VM (hosts/pc/configuration.nix), and
    # approvals still go through the local tray like any other client.
    # --pass-environment keeps XDG_RUNTIME_DIR/HYPRLAND_INSTANCE_SIGNATURE,
    # which the bridge needs to find the broker and the session.
    systemd.user.services.agent-computer-use-http = {
      Unit = sessionUnit // {
        Description = "Computer-use MCP over HTTP for Executor";
        After = sessionUnit.After ++ [ "agent-computer-use.service" ];
        Requires = sessionUnit.Requires ++ [ "agent-computer-use.service" ];
      };
      Service = {
        ExecStart = "${pkgs.mcp-proxy}/bin/mcp-proxy --host 0.0.0.0 --port 4790 --pass-environment -- ${package}/bin/agent-computer-use mcp";
        Restart = "always";
        RestartSec = 5;
        UMask = "0077";
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

    # Replaced by agent-chromium below: Chromium has the widest site
    # compatibility, Playwright drives it over DevTools, and its permanent
    # profile keeps LastPass logged in.
    # systemd.user.services.agent-firefox = {
    #   Unit = sessionUnit // {
    #     Description = "Persistent Firefox for the agent workspace";
    #     After = sessionUnit.After ++ [ "agent-input-plugin.service" ];
    #     Requires = sessionUnit.Requires ++ [ "agent-input-plugin.service" ];
    #   };
    #   Service = {
    #     ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${profile}";
    #     ExecStart = "${package}/bin/agent-desktop exec-session ${osConfig.programs.firefox.finalPackage}/bin/firefox --no-remote --name agent-firefox --profile ${profile} about:blank";
    #     Environment = [
    #       "HYPRLAND_AGENT_SEAT=1"
    #       "GTK_IM_MODULE=gtk-im-context-simple"
    #       "MOZ_ENABLE_WAYLAND=1"
    #       "GDK_BACKEND=wayland"
    #       "GDK_SCALE=1"
    #     ];
    #     Restart = "on-failure";
    #     RestartSec = 5;
    #     UMask = "0077";
    #   };
    #   Install.WantedBy = [ "hyprland-session.target" ];
    # };

    systemd.user.services.agent-chromium = {
      Unit = sessionUnit // {
        Description = "Agent Chromium on AGENT-1 (agent seat, permanent profile)";
        After = sessionUnit.After ++ [ "agent-input-plugin.service" ];
        Wants = [ "agent-input-plugin.service" ];
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${chromiumProfile}";
        ExecStart = "${package}/bin/agent-desktop exec-session ${pkgs.chromium}/bin/chromium ${agentChromiumArgs} --no-startup-window";
        Environment = [ "HYPRLAND_AGENT_SEAT=1" ];
        Restart = "always";
        RestartSec = 3;
        UMask = "0077";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };

    # Cua Driver daemon; `cua-driver mcp` and `cua-driver call` connect to it.
    # No overlay: its cursor layer would cover Erik's monitors too.
    systemd.user.services.cua-driver = {
      Unit = sessionUnit // {
        Description = "Cua Driver computer-use daemon";
      };
      Service = {
        ExecStart = "${package}/bin/agent-desktop exec-session ${cuaDriver}/bin/cua-driver serve --no-overlay";
        Environment = lib.mapAttrsToList (n: v: "${n}=${v}") cuaEnv;
        Restart = "always";
        RestartSec = 3;
        UMask = "0077";
      };
      Install.WantedBy = [ "hyprland-session.target" ];
    };
    home.sessionVariables = cuaEnv;

    home.file = lib.mergeAttrsList (
      lib.mapCartesianProduct ({ dir, skill }: { "${dir}/${skill}".source = ./skill + "/${skill}"; }) {
        dir = [
          ".agents/skills"
          ".claude/skills"
          ".codex/skills"
        ];
        skill = [
          "computer-use"
          "browser-use"
          "screen-recording"
        ];
      }
    );
  };
}
