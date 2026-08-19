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
  codexCli = inputs.llm-agents.packages.${system}.codex;
  # Sawrz/t3code-nix has been pinned to 0.0.25 since June and T3 only learned
  # about the Claude 5 family in 0.0.33, so keep its derivation but point it at
  # the newer npm artifact with a locally vendored lockfile (npm/package.json in
  # the tarball uses pnpm-style overrides that npm refuses; the vendored copy
  # has them stripped, exactly like the upstream packaging does).
  t3Version = "0.0.33";
  t3NpmPackage = ./t3-npm/package.json;
  t3NpmLock = ./t3-npm/package-lock.json;
  t3Cli =
    (inputs.t3code-nix.packages.${system}.t3code-cli.override { codex = codexCli; }).overrideAttrs
      (_oldAttrs: {
        version = t3Version;

        src = pkgs.fetchurl {
          url = "https://registry.npmjs.org/t3/-/t3-${t3Version}.tgz";
          hash = "sha512-TpXtftAVkRi5X6Bse01WKNISyrflXMukOppMAH9duWMw9hswAPI6IChjNNaxHXI3ZfcN5CgKoNmh19XCvrOkYw==";
        };

        npmDeps = pkgs.importNpmLock {
          package = lib.importJSON t3NpmPackage;
          packageLock = lib.importJSON t3NpmLock;
          fetcherOpts = {
            "node_modules/@effect/platform-node" = {
              name = "platform-node.tgz";
            };
            "node_modules/@effect/platform-node-shared" = {
              name = "platform-node-shared.tgz";
            };
            "node_modules/@effect/sql-sqlite-bun" = {
              name = "sql-sqlite-bun.tgz";
            };
            "node_modules/effect" = {
              name = "effect.tgz";
            };
          };
        };

        postPatch = ''
          cp ${t3NpmPackage} package.json
          cp ${t3NpmLock} package-lock.json
          sed -i "s/var version = \".*\";/var version = \"${t3Version}\";/" dist/bin.mjs

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

          // Codex speaks strict JSON-RPC 2.0; T3 omits the envelope field.
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

          // With T3CODE_UNSAFE_NO_AUTH=1 every request that carries no
          // credential -- or a stale one -- resolves to a fully scoped session
          // instead of failing, so the LAN/VPN-only deployment needs no
          // pairing, cookie, or bearer token. The fallback still goes through a
          // real session row, so websocket tickets and the access UI keep
          // working. Unset, the server behaves exactly as upstream.
          replaceOnce(
            "\tconst authenticateRequest = (request) => {\n\t\tconst cookieToken = request.cookies[sessions.cookieName];",
            "\tconst authenticateRequestStrict = (request) => {\n\t\tconst cookieToken = request.cookies[sessions.cookieName];",
            "Unauthenticated LAN access: rename the strict path",
          );
          replaceOnce(
            "\tconst getSessionState = (request) => authenticateRequest(request).pipe(",
            `const noAuthEnabled = process.env.T3CODE_UNSAFE_NO_AUTH === "1";
          let noAuthPrincipal = null;
          const loadNoAuthSession = Effect.gen(function* () {
            const active = yield* sessions.listActive();
            const existing = active.find((session) => session.subject === "no-auth");
            const session = existing ?? (yield* sessions.issue({
              method: "browser-session-cookie",
              subject: "no-auth",
              scopes: AuthAdministrativeScopes,
              client: { deviceType: "unknown", label: "unauthenticated LAN access" },
              ttl: Duration.days(3650)
            }));
            noAuthPrincipal = {
              sessionId: session.sessionId,
              subject: session.subject ?? "no-auth",
              method: session.method,
              scopes: session.scopes,
              ...session.expiresAt ? { expiresAt: session.expiresAt } : {}
            };
            return noAuthPrincipal;
          }).pipe(mapSessionVerificationErrors);
          const noAuthSession = Effect.suspend(() => noAuthPrincipal === null ? loadNoAuthSession : Effect.succeed(noAuthPrincipal));
          const authenticateRequest = noAuthEnabled ? (request) => authenticateRequestStrict(request).pipe(Effect.catchIf(isServerAuthCredentialError, () => noAuthSession)) : authenticateRequestStrict;
          const getSessionState = (request) => authenticateRequest(request).pipe(`,
            "Unauthenticated LAN access fallback",
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
    t3Cli
  ];

  systemd.user.services.t3code = {
    Unit.Description = "T3 Code web server";

    Service = {
      ExecStartPre = t3CodexPrepare;
      ExecStart = "${t3Cli}/bin/t3 serve --host 0.0.0.0 --port 3773";
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
