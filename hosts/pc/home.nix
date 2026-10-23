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
  # T3 orders runs by time. This PC keeps its RTC in local time
  # (time.hardwareClockInLocalTime), so after a hard reboot the clock can run
  # two hours ahead until NTP corrects it; runs that end in that window look
  # newer than everything after them, and T3 stopped continuing those threads
  # after later restarts (2026-10-23). Wait for NTP, but never block a start.
  t3WaitForClock = pkgs.writeShellScript "t3-code-wait-for-clock" ''
    for _ in $(${pkgs.coreutils}/bin/seq 60); do
      [ "$(${pkgs.systemd}/bin/timedatectl show -p NTPSynchronized --value)" = yes ] && exit 0
      ${pkgs.coreutils}/bin/sleep 1
    done
    echo "t3code: clock not NTP-synchronized after 60 s; starting anyway" >&2
  '';
  t3CodexPrepare = pkgs.writeShellScript "t3-code-codex-prepare" ''
    mkdir -p ${lib.escapeShellArg t3CodexHome}
    if [[ ! -e ${lib.escapeShellArg "${t3CodexHome}/state_5.sqlite"} ]]; then
      ${pkgs.sqlite}/bin/sqlite3 \
        ${lib.escapeShellArg "${codexHome}/state_5.sqlite"} \
        ".backup '${t3CodexHome}/state_5.sqlite'"
    fi
  '';
  # Grok Build (the `grok` CLI from llm-agents, see modules/home-manager/ai.nix)
  # and Cursor (@cursor/sdk, bundled with T3) are built-in T3 providers, but
  # they start switched off. Both run on Erik's SuperGrok plan (grok.com and
  # cursor.com share one xAI account). settings.json is the server's own
  # mutable state, so only flip these flags and keep the rest; the server
  # watches the file and applies the change without a restart. The logins are
  # not declarative: grok keeps its OAuth token in ~/.grok/auth.json (`grok
  # login --oauth`), Cursor's browser sign-in lives in T3's credential store.
  t3EnableProviders = pkgs.writeShellApplication {
    name = "t3code-enable-providers";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.jq
    ];
    text = ''
      file="$HOME/.t3/userdata/settings.json"
      current='{}'
      if [ -e "$file" ]; then
        if ! current=$(jq -e . "$file" 2>/dev/null); then
          echo "t3code: cannot parse $file, leaving it alone" >&2
          exit 0
        fi
      fi
      filter='.providers.grok.enabled == true and .providers.cursor.enabled == true'
      if jq -e "$filter" <<<"$current" >/dev/null; then
        exit 0
      fi
      mkdir -p "$(dirname "$file")"
      jq '.providers.grok.enabled = true | .providers.cursor.enabled = true' \
        <<<"$current" >"$file.tmp"
      mv "$file.tmp" "$file"
      echo "t3code: enabled the Grok and Cursor providers in $file"
    '';
  };
  # Runs as ExecStop of t3code.service, i.e. only when systemd is stopping the
  # unit (systemctl stop/restart, t3 doctor, a reboot). Tells health-watch and
  # Alertmanager that the outage is expected so no repair session starts for
  # it (Erik, 2026-10-23: "when you do a restart, mark in the alert system
  # that this is expected"). A crash does not go through a stop job, so it
  # still alerts. Everything is best effort: it must never block a stop.
  t3codeExpectStop = pkgs.writeShellApplication {
    name = "t3code-expect-stop";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.jq
      pkgs.systemd
    ];
    text = ''
      # Only for a deliberate stop: a stop or restart job is queued for the unit.
      if ! systemctl --user list-jobs --no-legend 2>/dev/null \
        | grep -Eq 't3code\.service +(stop|restart)'; then
        exit 0
      fi
      # t3code itself, and the transient build units (voice-apk-build8, ...)
      # that the restart kills along with the agent sessions that started them.
      unit_regex='t3code|.*-build[0-9]*'
      ${config.home.homeDirectory}/.nix-profile/bin/health-watch maintenance 20 \
        "t3code.service is being stopped (restart, deploy or t3 doctor)" \
        't3code|-build[0-9]*$' || true
      # Log-based alerts stay active for 30 minutes after the event, so the
      # silence has to outlive that.
      now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
      end=$(date -u -d '+45 minutes' +%Y-%m-%dT%H:%M:%SZ)
      jq -n --arg start "$now" --arg end "$end" --arg re "$unit_regex" '{
        matchers: [
          {name: "alertname", value: "SystemdUnitFailed", isRegex: false, isEqual: true},
          {name: "host_name", value: "pc", isRegex: false, isEqual: true},
          {name: "service_name", value: $re, isRegex: true, isEqual: true}],
        startsAt: $start, endsAt: $end, createdBy: "t3code-expect-stop",
        comment: "t3code.service is being stopped on purpose"}' \
        | curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' \
          -d @- https://alertmanager.erikfrankling.duckdns.org/api/v2/silences \
          >/dev/null || true
    '';
  };
in
{
  imports = [
    ../../modules/home-manager
    ../../modules/home-manager/desktop.nix
    ../../modules/home-manager/print
    ../../modules/home-manager/vm-host.nix
    ../../modules/home-manager/wayvnc.nix
    ../../modules/home-manager/computer-use
    ../../modules/home-manager/ibus-native-seat.nix
    ../../modules/home-manager/auto-update
    ../../modules/home-manager/dev-preview
    ../../modules/home-manager/notify # phone notifications skill
    ../../modules/home-manager/company-brain.nix
    ../../modules/home-manager/canvas-archive.nix
    ../../modules/home-manager/x-graph.nix
    ../../modules/home-manager/machines
    ../../modules/home-manager/heavy # `heavy`: heavy agent work on the homelab worker
    ../../modules/home-manager/bro
    ../../modules/home-manager/todo-nudge # wake the personal agent while its to-do list has actionable items
    ../../modules/home-manager/speak # the personal agent may talk out loud on the PC speakers
    inputs.time.homeManagerModules.agent-v2
    # ../../modules/home-manager/noctalia.nix
  ];

  programs.agent-desktop.enable = true;
  speak.speakers = true;

  # Agents read email codes from Thunderbird on this machine.
  thunderbird.autostart = true;

  # This machine drives the nightly flake update and the homelab build.
  autoUpdateNightly.enable = true;

  # Time v2: what is on screen, input counts, lock, power and network each
  # minute, to the local Alloy, which forwards to Time in the cluster. Commits
  # and PRs every 15 minutes, and the nightly off-cluster backup of Time's
  # database (with a restore test) lands in ~/backups/time on this machine.
  # Input counts come from physical devices only, so the AI computer-use
  # sessions on this machine do not count as Erik being here.
  services.time-agent-v2 = {
    enable = true;
    device = "pc";
    collect.enable = true;
    backup.enable = true;
  };

  # Keep T3's mutable Codex database separate while sharing the authenticated
  # account, configuration, sessions, and user extensions.
  home.file = {
    # Time as an MCP server for the personal agent only (a project-level
    # .mcp.json, so no other session sees it). The bearer token comes from
    # $TIME_MCP_TOKEN, which the claude launcher
    # (modules/home-manager/executor-harness.nix) sets for sessions started
    # in this folder. Server: homelab time-v2, github.com/ErikFrankling/time.
    ".t3/personal/.mcp.json".text = builtins.toJSON {
      mcpServers.time = {
        type = "http";
        url = "https://time.erikfrankling.duckdns.org/mcp";
        headers.Authorization = "Bearer \${TIME_MCP_TOKEN}";
      };
    };
    ".codex-t3/auth.json".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/auth.json";
    ".codex-t3/config.toml".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/config.toml";
    ".codex-t3/sessions".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/sessions";
    ".codex-t3/archived_sessions".source =
      config.lib.file.mkOutOfStoreSymlink "${codexHome}/archived_sessions";
    ".codex-t3/attachments".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/attachments";
    ".codex-t3/skills".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/skills";
    ".codex-t3/rules".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/rules";
    ".codex-t3/plugins".source = config.lib.file.mkOutOfStoreSymlink "${codexHome}/plugins";
  }
  # math-video skill lives in the mathvid repo (~/projects/mathvid/skill); a live
  # symlink so improvements to the workflow doc apply without a rebuild.
  //
    lib.genAttrs
      [
        ".claude/skills/math-video"
        ".agents/skills/math-video"
        ".codex/skills/math-video"
      ]
      (_: {
        source = config.lib.file.mkOutOfStoreSymlink "/home/erikf/projects/mathvid/skill";
      });

  home.packages = with pkgs; [
    prismlauncher
  ];

  # VNC into this desktop from the laptop and the phone (LAN/tailnet only —
  # the ports are opened on eno1 alone in configuration.nix). One port per
  # view because wayvnc captures one output per process: 5900 is both 4K
  # monitors side by side (fine on the laptop), 5901/5902 are the single
  # monitors (what the phone wants — half the pixels, and AVNC fits the
  # remote resolution to the screen). Monitor names match the hyprland
  # monitors block below.
  wayvnc.instances = [
    {
      name = "desktop";
      port = 5900;
    }
    {
      name = "left";
      port = 5901;
      output = "DP-3";
    }
    {
      name = "right";
      port = 5902;
      output = "HDMI-A-1";
    }
  ];

  systemd.user.services.t3code = {
    Unit.Description = "T3 Code web server";
    # Rebuilds update CLI dependencies too. Restarting this server interrupts
    # every active agent turn; apply updates on the next deliberate restart.
    # In particular, rebuilding the MCP adapter patch does not repair live
    # Codex sessions. See research/t3code-executor-activation.md.
    Unit.X-SwitchMethod = "keep-old";
    # Tells `t3 service status` / `t3 doctor` that Nix owns this unit, so t3
    # reports it healthy instead of trying to re-render it (fork: bootService.ts).
    Unit.X-T3-Externally-Managed = "true";

    Service = {
      ExecStartPre = [
        "${t3WaitForClock}"
        "${t3CodexPrepare}"
      ];
      ExecStart = "${pkgs.t3code}/bin/t3 serve --host 0.0.0.0 --port 3773";
      # Marks every deliberate stop as expected for health-watch/Alertmanager.
      ExecStop = "-${lib.getExe t3codeExpectStop}";
      Environment = [
        # `t3 doctor` and `t3 service` only treat a unit as theirs when it
        # names the data directory in T3CODE_HOME (the default, ~/.t3). Without
        # it doctor cannot pause the server for database maintenance.
        "T3CODE_HOME=${config.home.homeDirectory}/.t3"
        "CODEX_HOME=${t3CodexHome}"
        # LAN/VPN-only deployment: serve without pairing, cookies, or tokens.
        "T3CODE_UNSAFE_NO_AUTH=1"
        # Android dictation uploads AAC; the fork decodes it for local-stt.
        "T3CODE_FFMPEG=${lib.getExe pkgs.ffmpeg-headless}"
        # Read aloud: small voice = Kokoro on the homelab GTX 1060 (af_heart,
        # 1.2x), big voice = Higgs through llama-swap (erik, 1.0x). The other
        # defaults (summary model, Higgs) live in the fork; see
        # research/read-aloud/2026-10-18.
        "T3CODE_READ_ALOUD_SMALL_TTS_URL=http://192.168.50.100:8880/v1/audio/speech"
        "T3CODE_READ_ALOUD_SMALL_VOICE=af_heart"
        "T3CODE_READ_ALOUD_SMALL_SPEED=1.2"
        # Native push to Erik's T3 app (the fork's apps/server/src/erikPush.ts):
        # agents' notify-erik / Executor notify send through /api/push/send.
        "T3CODE_FCM_SERVICE_ACCOUNT_FILE=/run/secrets/t3code-fcm-service-account"
      ];
      Restart = "on-failure";
      RestartSec = 5;
      # t3 exits 130 (128 + SIGINT, the Effect runtime's interrupt exit) when
      # systemd stops it. Without this every stop is recorded as "Failed with
      # result 'exit-code'" and the homelab SystemdUnitFailed alert fires.
      SuccessExitStatus = "130";
      WorkingDirectory = config.home.homeDirectory;
    };

    Install.WantedBy = [ "default.target" ];
  };

  home.activation.t3codeEnableProviders = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${lib.getExe t3EnableProviders}
  '';

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
