# calendar: Erik's calendar, read-only, in every agent's context (Erik,
# 2026-10-23: "I just want you to be aware of my calendar ... available to your
# context often").
#
# - Executor app `calendar` (executor-app/, deploy with ./deploy.sh): Google
#   Calendar with the calendar.readonly scope, tools.calendar.upcoming({days}),
#   day({date}), calendars(). Connect: tools.executor.appAccounts.userConnect.
# - `calendar-next`: the next 24 h as a compact block (Google through the
#   Executor app + the KTH Canvas calendar feed). todo-nudge puts it in every
#   review (TODO_NUDGE_CALENDAR_CMD).
# - calendar-remind.timer (PC only, `speak` talks on the PC speakers only):
#   every minute, `speak say "<title> in ten minutes" normal` about 10 minutes
#   before each timed event. Log: ~/.local/state/calendar/reminders.log.
{ pkgs, lib, ... }:

let
  python = pkgs.python3;

  # The logic's tests run at build time: a failing test fails the rebuild.
  src = pkgs.runCommand "calendar-next-src" { nativeBuildInputs = [ python ]; } ''
    mkdir -p $out
    cp ${./calendar_next.py} $out/calendar_next.py
    cp ${./test_calendar_next.py} test_calendar_next.py
    cp ${./calendar_next.py} calendar_next.py
    PYTHONDONTWRITEBYTECODE=1 python -m unittest -v test_calendar_next
  '';

  calendarNext = pkgs.writeShellApplication {
    name = "calendar-next";
    text = ''exec ${python}/bin/python3 ${src}/calendar_next.py "$@"'';
  };
in
{
  home.packages = [ calendarNext ];

  systemd.user.services.calendar-remind = {
    Unit.Description = "Speak a reminder about Erik's meetings ten minutes before they start";
    Service = {
      Type = "oneshot";
      ExecStart = "${lib.getExe calendarNext} remind";
      # agent-canvas-token and speak live in the user profile.
      Environment = [
        "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
      ];
    };
  };

  systemd.user.timers.calendar-remind = {
    Unit.Description = "Check Erik's calendar for meetings starting in ten minutes";
    Timer = {
      OnBootSec = "2m";
      OnUnitActiveSec = "1m";
      AccuracySec = "10s";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
