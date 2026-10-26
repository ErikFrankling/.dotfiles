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
#
# Retention (Erik, 2026-10-26: "we don't need infinite copies of the same
# info"): after each run canvas-archive-retain.py keeps archive.json (latest)
# and archive-prev.json, one gzipped full snapshot per ISO week in snapshots/,
# and each day's changes in changes/ (JSON of added/removed/changed Canvas
# objects plus diff.py's changes.md). Old daily full copies are deleted only
# once their week's snapshot reads back as a valid archive.
#
# On success it starts school-sync (modules/home-manager/school-sync), which
# pushes the deadlines to https://school.erikfrankling.duckdns.org.
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
    Unit = {
      Description = "Refresh the local Canvas archive and notify about changes";
      OnSuccess = [ "school-sync.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${archive}/run-daily.sh";
      ExecStartPost = "${pkgs.python3}/bin/python3 -I ${./canvas-archive-retain.py} ${archive}";
      # Own the interpreter (with pymupdf for the scrub/pdf_honour_scan.py
      # redaction step in run-daily.sh) and pdftotext; notify-erik comes from
      # the system profile.
      Environment = [
        "PATH=${
          lib.makeBinPath [
            (pkgs.python3.withPackages (ps: [ ps.pymupdf ]))
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
