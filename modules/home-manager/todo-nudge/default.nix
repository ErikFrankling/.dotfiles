# todo-nudge: the personal agent may only go idle when every to-do item is
# blocked, standing or in flight (Erik, 2026-10-23). Every minute this reads
# the front matter of ~/.t3/personal/todo/*.md (contract: todo/README.md) and,
# when the personal-agent thread is idle while something is actionable, sends
# it the entire list (blocked items too) through `t3 thread send`; with
# nothing able to move it still sends a full review once an hour.
# Decisions log to ~/.local/state/todo-nudge/decisions.log.
{ pkgs, lib, ... }:

let
  python = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  # The decision logic's tests run at build time: a failing test fails the rebuild.
  src = pkgs.runCommand "todo-nudge-src" { nativeBuildInputs = [ python ]; } ''
    mkdir -p $out
    cp ${./todo_nudge.py} $out/todo_nudge.py
    cp ${./test_todo_nudge.py} test_todo_nudge.py
    cp ${./todo_nudge.py} todo_nudge.py
    PYTHONDONTWRITEBYTECODE=1 python -m unittest -v test_todo_nudge
  '';

  todoNudge = pkgs.writeShellApplication {
    name = "todo-nudge";
    runtimeInputs = [ pkgs.t3code ];
    text = ''exec ${python}/bin/python3 ${src}/todo_nudge.py "$@"'';
  };
in
{
  home.packages = [ todoNudge ];

  systemd.user.services.todo-nudge = {
    Unit = {
      Description = "Nudge the personal agent when its to-do list has actionable items";
      After = [ "t3code.service" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = lib.getExe todoNudge;
      # The hourly review's "Time, last hour" line: the Time server's one-line
      # summary (minutes per category, productive vs unproductive, what he is
      # doing now). Lan-only, no token. github.com/ErikFrankling/time README.
      Environment = [
        "TODO_NUDGE_TIME_URL=https://time.erikfrankling.duckdns.org/api/summary/line"
        # The hourly review also shows Erik's next 24 hours (modules/home-manager/calendar).
        "TODO_NUDGE_CALENDAR_CMD=calendar-next --hours 24"
        "PATH=%h/.nix-profile/bin:/etc/profiles/per-user/%u/bin:/run/current-system/sw/bin"
      ];
    };
  };

  systemd.user.timers.todo-nudge = {
    Unit.Description = "Check the personal agent's to-do list every minute";
    Timer = {
      OnBootSec = "3m";
      OnUnitActiveSec = "1m";
      AccuracySec = "10s";
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
