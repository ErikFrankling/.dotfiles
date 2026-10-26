# school-sync: pushes Erik's KTH deadlines to the school calendar
# (homelab kubernetes/homelab/apps/school.yaml,
# https://school.erikfrankling.duckdns.org).
#
# export.py reads only local files: the Canvas archive that
# canvas-archive-refresh just updated (archive.json, deadlines.json, TimeEdit
# schedule.json) and the curated rules in ~/projects/kth/school/overrides.json
# (which course code is Erik's, items settled for a later round, notes). It
# never talks to Canvas. It writes ~/projects/kth/school/items.json and POSTs
# it to /api/ingest; the server keeps Erik's done toggles.
#
# Started by canvas-archive-refresh on success (OnSuccess), and daily at 07:30
# by its own timer so a failed refresh still re-sends the last archive.
{
  config,
  osConfig,
  pkgs,
  ...
}:
{
  systemd.user.services.school-sync = {
    Unit = {
      Description = "Push KTH deadlines to school.erikfrankling.duckdns.org";
      After = [ "canvas-archive-refresh.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.python3}/bin/python3 -I ${./export.py}";
      Environment = [
        "SCHOOL_INGEST_TOKEN_FILE=${osConfig.sops.secrets.school-ingest-token.path}"
        "CANVAS_ARCHIVE=${config.home.homeDirectory}/projects/kth/canvas-archive"
        "SCHOOL_DIR=${config.home.homeDirectory}/projects/kth/school"
      ];
      Nice = 15;
      TimeoutStartSec = "5min";
    };
  };
  systemd.user.timers.school-sync = {
    Unit.Description = "Daily push of KTH deadlines to the school calendar";
    Timer = {
      OnCalendar = "*-*-* 07:30:00";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
