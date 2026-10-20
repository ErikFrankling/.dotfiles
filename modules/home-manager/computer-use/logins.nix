{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:

# Agents use Erik's logins instead of signing in themselves (each agent login
# meant another phone 2FA prompt).
# - agent-cookie-sync: copies his Firefox cookies into the agent Chromium
#   every few minutes, so the agent is logged in wherever he is.
# - agent-canvas-token: a Canvas API token for KTH Canvas, which does not
#   depend on KTH's 8-hour ADFS session. KTH caps tokens at 90 days; a weekly
#   timer moves the expiry forward (the token value stays the same, so it can
#   live in sops).
let
  cdpPort = 9222;
  # Sites never copied from Firefox:
  # - lastpass.com: the agent's LastPass extension has its own session.
  # - linkedin.com: LinkedIn revokes a session (li_at) as soon as it is used
  #   from a second browser, logging out Firefox and the agent alike
  #   (2026-10-21). The agent keeps its own LinkedIn login.
  syncExcluded = [
    "lastpass.com"
    "linkedin.com"
  ];
  python = pkgs.python3.withPackages (p: [
    p.lz4
    p.websocket-client
  ]);
  cookieSync = pkgs.writeShellScriptBin "agent-cookie-sync" ''
    exec ${python}/bin/python3 -I ${./cookie-sync.py} \
      --port ${toString cdpPort} ${lib.concatMapStringsSep " " (s: "--exclude ${s}") syncExcluded} "$@"
  '';

  canvasTokenSecret = osConfig.sops.secrets.canvas-token.path or null;
  # Database id of the token (not secret); Canvas needs it to update one.
  canvasTokenId = "458282";
  canvasToken = pkgs.writeShellScriptBin "agent-canvas-token" ''
    set -euo pipefail
    case "''${1:-print}" in
      print) cat ${canvasTokenSecret} ;;
      renew)
        exp=$(${pkgs.coreutils}/bin/date -u -d '+89 days' +%FT%TZ)
        ${pkgs.curl}/bin/curl -fsS -X PUT \
          -H "Authorization: Bearer $(cat ${canvasTokenSecret})" \
          -H 'Content-Type: application/json' \
          -d "{\"token\":{\"expires_at\":\"$exp\"}}" \
          https://canvas.kth.se/api/v1/users/self/tokens/${canvasTokenId} \
          | ${pkgs.jq}/bin/jq -r '"Canvas token expires " + .expires_at'
        ;;
      *) echo "usage: agent-canvas-token [print|renew]" >&2; exit 2 ;;
    esac
  '';
in
{
  config = lib.mkIf config.programs.agent-desktop.enable (
    lib.mkMerge [
      {
        home.packages = [ cookieSync ];

        systemd.user.services.agent-cookie-sync = {
          Unit = {
            Description = "Copy Erik's Firefox logins into the agent Chromium";
            After = [ "agent-chromium.service" ];
          };
          Service = {
            Type = "oneshot";
            ExecStart = "${cookieSync}/bin/agent-cookie-sync --wait 60";
            UMask = "0077";
          };
        };
        systemd.user.timers.agent-cookie-sync = {
          Unit.Description = "Copy Erik's Firefox logins into the agent Chromium";
          Timer = {
            OnActiveSec = "1min";
            OnUnitActiveSec = "5min";
          };
          Install.WantedBy = [ "timers.target" ];
        };
        # A restarted Chromium has lost its session cookies: sync right away.
        systemd.user.services.agent-chromium.Service.ExecStartPost =
          "-${pkgs.systemd}/bin/systemctl --user start --no-block agent-cookie-sync.service";
      }

      (lib.mkIf (canvasTokenSecret != null) {
        home.packages = [ canvasToken ];
        systemd.user.services.agent-canvas-token-renew = {
          Unit.Description = "Keep the agents' Canvas API token from expiring";
          Service = {
            Type = "oneshot";
            ExecStart = "${canvasToken}/bin/agent-canvas-token renew";
          };
        };
        systemd.user.timers.agent-canvas-token-renew = {
          Unit.Description = "Keep the agents' Canvas API token from expiring";
          Timer = {
            OnCalendar = "weekly";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      })
    ]
  );
}
