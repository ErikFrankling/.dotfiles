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
#   depend on KTH's 8-hour ADFS session. KTH caps tokens at 90 days; every
#   ~60 days (when under 30 days are left) the expiry is moved forward again
#   (the token value stays the same, so it can live in sops).
#   READ-ONLY BY RULE (Erik, 2026-10-21): agents only read Canvas. They never
#   push content to it: no submissions, posts, replies, comments, uploads,
#   messages, peer reviews, quiz answers, profile or setting changes. Only
#   the renewal below writes (the token's own expiry).
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
  # Agents use this token for reading only (GET). Never POST/PUT/DELETE to
  # Canvas; see the rule at the top of this file and the browser-use skill.
  canvasToken = pkgs.writeShellScriptBin "agent-canvas-token" ''
    set -euo pipefail
    api=https://canvas.kth.se/api/v1/users/self/tokens/${canvasTokenId}
    case "''${1:-print}" in
      print) cat ${canvasTokenSecret} ;;
      renew)
        # Only the renewal job writes, and only the token's own expiry.
        left=$(${pkgs.curl}/bin/curl -fsS -H "Authorization: Bearer $(cat ${canvasTokenSecret})" "$api" \
          | ${pkgs.jq}/bin/jq -r '(.expires_at | fromdateiso8601) - now | . / 86400 | floor')
        if [ "$left" -ge 30 ]; then
          echo "Canvas token has $left days left; renews when under 30"
          exit 0
        fi
        exp=$(${pkgs.coreutils}/bin/date -u -d '+89 days' +%FT%TZ)
        ${pkgs.curl}/bin/curl -fsS -X PUT \
          -H "Authorization: Bearer $(cat ${canvasTokenSecret})" \
          -H 'Content-Type: application/json' \
          -d "{\"token\":{\"expires_at\":\"$exp\"}}" \
          "$api" \
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
          # Daily check; it renews only when under 30 days are left, so in
          # practice every ~60 days.
          Timer = {
            OnCalendar = "daily";
            Persistent = true;
            RandomizedDelaySec = "1h";
          };
          Install.WantedBy = [ "timers.target" ];
        };
      })
    ]
  );
}
