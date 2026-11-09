# fleet-push-creds: keeps the provider keys in Fleet's Bifrost (namespace fleet on
# k8s, repo ~/projects/fleet, deploy/push-creds.sh) current, and reports the
# plans' usage to Fleet's control.
#
# It reads the access tokens from ~/.codex/auth.json and ~/.grok/auth.json and the
# OpenCode Go key from ~/.local/share/opencode/auth.json. Access tokens only: never
# a refresh token, never a refresh, so Erik's CLIs keep owning their logins
# (fleet docs/research/secrets.md 5.1). Nothing is printed. The body travels on
# stdin over ssh, so it never shows up in a process list.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  repo = "${config.home.homeDirectory}/projects/fleet";
in
{
  systemd.user.services.fleet-push-creds = {
    Unit = {
      Description = "Push provider access tokens into Fleet's Bifrost and report plan usage";
      ConditionPathExists = "${repo}/deploy/push-creds.sh";
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${repo}/deploy/push-creds.sh";
      Environment = [
        "PATH=${
          lib.makeBinPath [
            pkgs.bash
            pkgs.coreutils
            pkgs.curl
            pkgs.jq
            pkgs.openssh
          ]
        }"
      ];
      Nice = 15;
      MemoryMax = "256M";
      TimeoutStartSec = "4min";
    };
  };
  systemd.user.timers.fleet-push-creds = {
    Unit.Description = "Every 5 minutes: fleet-push-creds";
    Timer = {
      OnBootSec = "3min";
      OnUnitInactiveSec = "5min";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
