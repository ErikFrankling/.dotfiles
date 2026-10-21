# Daily refresh of Erik's local Canvas archive (~/projects/kth/canvas-archive).
#
# Pulls every current course through the agents' Canvas API token
# (agent-canvas-token, computer-use/logins.nix), rebuilds the per-course
# ALL-TEXT/README, deadlines.json, catch-up.md and index.html, diffs against the
# previous run and pushes new, actionable items (announcement, changed
# deadline/room, new assignment, grade) to his phone with notify-erik
# (high when it affects today or tomorrow).
#
# READ-ONLY (Erik, 2026-10-21): canvas_session.py only issues GET requests.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  archive = "${config.home.homeDirectory}/projects/kth/canvas-archive";
in
{
  systemd.user.services.canvas-archive-refresh = {
    Unit.Description = "Refresh the local Canvas archive and notify about changes";
    Service = {
      Type = "oneshot";
      ExecStart = "${archive}/run-daily.sh";
      # Own the interpreter and pdftotext; notify-erik comes from the system profile.
      Environment = [
        "PATH=${
          lib.makeBinPath [
            (pkgs.python3.withPackages (_: [ ]))
            pkgs.poppler-utils
            pkgs.coreutils
            pkgs.bash
            pkgs.git
          ]
        }:/run/current-system/sw/bin:${config.home.homeDirectory}/.nix-profile/bin:/etc/profiles/per-user/${config.home.username}/bin"
      ];
      Nice = 15;
      IOSchedulingClass = "idle";
      MemoryMax = "2G";
      TimeoutStartSec = "30min";
    };
  };
  systemd.user.timers.canvas-archive-refresh = {
    Unit.Description = "Daily Canvas archive refresh";
    Timer = {
      OnCalendar = "*-*-* 06:30:00";
      Persistent = true;
      RandomizedDelaySec = "10min";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
