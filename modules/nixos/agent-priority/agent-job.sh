# agent-job: run a long command in a systemd user unit of its own, so it
# outlives the agent that started it, and attach to it again by name.
#
# T3 Code stops every agent's scope and slice when its server restarts
# (apps/server/src/process/agentScope.ts, stopLeftoverAgents), and a session's
# tool call can time out. Both killed long builds started from a session: on
# 2026-10-23 a T3 restart silently killed the nightly's homelab build. A job
# runs as agent-job-NAME.service in app-t3code-jobs.slice, still inside
# app-t3code.slice (same CPU, memory and disk caps, lag-guard) but outside
# the slices T3 stops. Output goes to ~/.local/state/agent-job/NAME.log.
#
#   agent-job run NAME -- CMD...    start CMD as job NAME and follow it; if NAME
#                                   is already running, follow that one instead
#   agent-job wrap NAME -- CMD...   `run` when called from an agent session,
#                                   else just exec CMD (used by nix-nightly
#                                   build, rebuild and heavy)
#   agent-job attach NAME           follow a running (or finished) job
#   agent-job status [NAME]         running jobs, or one job's state
#   agent-job logs NAME             its whole log
#   agent-job stop NAME             stop it
#
#   agent-job daemon start NAME [--notify-thread ID] -- CMD...
#                                   run CMD for good as agent-daemon@NAME.service
#                                   (restarts an existing one with the new CMD)
#   agent-job daemon stop NAME      stop it and forget it
#   agent-job daemon list           registered daemons and their state
#   agent-job daemon logs NAME      its journal
#
# A daemon is for small infra processes that must stay up (a build scheduler,
# a disk gate, a status page). Unlike a job it is a declared unit,
# agent-daemon@.service (default.nix): same slice and caps, OOMScoreAdjust
# 500 (below agents and jobs, so the OOM killer takes a big rustc first),
# OOMPolicy=continue, Restart=on-failure. Its command and environment are kept
# in ~/.local/state/agent-job/daemons/, and agent-daemons.service starts every
# registered daemon that is not running at login, after the user manager was
# killed, and after each T3 Code server start; it then tells Erik and each
# daemon's --notify-thread which ones it had to bring back. Transient units
# (systemd-run, `run`) are lost when the user manager dies: on 2026-11-14 an
# agent's `ps -e --ppid X | xargs kill -KILL` (-e selects everything) killed
# every process of Erik's, user manager included, and all wasm-box infra
# units with it.
#
# `run` and `attach` exit with the command's exit status. Interrupting or
# killing them only detaches: the job keeps running. AGENT_JOB=off in the
# environment makes `wrap` run the command in the caller instead.

set -u
state=${XDG_STATE_HOME:-$HOME/.local/state}/agent-job
mkdir -p "$state"
chmod 700 "$state"

die() {
  echo "agent-job: $*" >&2
  exit 2
}
unit() { echo "agent-job-$1.service"; }
running() { systemctl --user is-active --quiet "$(unit "$1")"; }
valid() { [[ $1 =~ ^[A-Za-z0-9_.-]{1,100}$ ]] || die "bad job name '$1' (letters, digits, . _ -)"; }

is_agent() {
  case "$(cat /proc/self/cgroup)" in
    */t3code-terminal-*) return 1 ;;
    */app-t3code.slice/*) return 0 ;;
    *) return 1 ;;
  esac
}

# Follow NAME's log until the unit is gone, then exit with its status.
follow() {
  local name=$1 lines=$2 log=$state/$1.log
  echo "agent-job: following $(unit "$name") (log: $log; reattach: agent-job attach $name)" >&2
  tail -n "$lines" -F "$log" 2>/dev/null &
  local tailpid=$!
  trap 'kill $tailpid 2>/dev/null; echo "agent-job: detached; $name keeps running (agent-job attach $name)" >&2; exit 130' INT TERM HUP
  while running "$name"; do sleep 2; done
  sleep 1
  kill "$tailpid" 2>/dev/null || true
  wait "$tailpid" 2>/dev/null || true
  trap - INT TERM HUP
  if [ -s "$state/$name.status" ]; then
    local status
    status=$(cat "$state/$name.status")
    echo "agent-job: $name finished with status $status" >&2
    exit "$status"
  fi
  echo "agent-job: $name ended without an exit status (killed or stopped)" >&2
  exit 125
}

start() {
  local name=$1
  shift
  [ $# -gt 0 ] || die "usage: agent-job run NAME -- CMD..."
  if running "$name"; then
    echo "agent-job: $name is already running; attaching instead of starting it again" >&2
    follow "$name" 40
  fi
  rm -f "$state/$name.status"
  : >"$state/$name.log"
  # The unit starts with the user manager's environment; give it this one,
  # minus this script's own tools at the front of PATH. With them, a job's
  # `systemd-run` and `systemctl` were systemd's own, not the agents' wrappers
  # (default.nix): `systemd-run --user --scope` in a job made its scope in
  # app.slice, outside the agents' caps, where lag-guard took it for one of
  # Erik's apps (2026-11-13: wasm-box's supply-r3f-scope.scope; its disk
  # stall had the agents capped and a process stopped every 30 s for two
  # hours), and the guard on `systemctl restart t3code` did not apply.
  (umask 077 && env -0 | sed -z 's|^PATH=@binPath@:|PATH=|' >"$state/$name.env")
  printf '%s\0' "$PWD" "$@" >"$state/$name.cmd"
  local slice=()
  if is_agent; then
    # Inside the agents' caps, outside what T3 stops; same niceness and OOM
    # preference as the agents' own systemd-run (agent-priority).
    slice=(--slice=app-t3code-jobs.slice --nice=10 --property=OOMScoreAdjust=1000)
  fi
  systemctl --user reset-failed "$(unit "$name")" 2>/dev/null || true
  @systemdRun@ --user --quiet --collect --unit="$(unit "$name")" \
    --description="agent-job $name: $*" "${slice[@]}" \
    -- "$0" __exec "$name" ||
    die "could not start $(unit "$name")"
  follow "$name" +1
}

case "${1:-}" in
  run)
    shift
    name=${1:?usage: agent-job run NAME -- CMD...}
    valid "$name"
    shift
    [ "${1:-}" != -- ] || shift
    start "$name" "$@"
    ;;
  wrap)
    shift
    name=${1:?usage: agent-job wrap NAME -- CMD...}
    valid "$name"
    shift
    [ "${1:-}" != -- ] || shift
    # In the caller, marked so the wrapped command does not wrap itself
    # again: without AGENT_JOB, `nix-nightly build` and `heavy` outside an
    # agent exec'd themselves in a loop until PATH outgrew the argument
    # limit (2026-10-25, "mkdir: Argument list too long").
    if [ -n "${AGENT_JOB:-}" ] || ! is_agent; then AGENT_JOB=${AGENT_JOB:-off} exec "$@"; fi
    start "$name" "$@"
    ;;
  attach)
    name=${2:?usage: agent-job attach NAME}
    valid "$name"
    [ -e "$state/$name.log" ] || die "no job named $name"
    follow "$name" 40
    ;;
  status)
    if [ -n "${2:-}" ]; then
      valid "$2"
      if running "$2"; then
        echo "$2: running since $(systemctl --user show -p ActiveEnterTimestamp --value "$(unit "$2")")"
      elif [ -s "$state/$2.status" ]; then
        echo "$2: finished with status $(cat "$state/$2.status")"
      else
        echo "$2: not running"
      fi
    else
      systemctl --user list-units --all --no-legend --plain 'agent-job-*.service'
    fi
    ;;
  logs)
    valid "${2:?usage: agent-job logs NAME}"
    exec cat "$state/$2.log"
    ;;
  stop)
    valid "${2:?usage: agent-job stop NAME}"
    exec systemctl --user stop "$(unit "$2")"
    ;;
  __exec)
    name=$2
    exec >>"$state/$name.log" 2>&1 </dev/null
    while IFS= read -r -d '' kv; do
      # shellcheck disable=SC2163 # the variable named by kv
      export "$kv" 2>/dev/null || true
    done <"$state/$name.env"
    rm -f "$state/$name.env"
    mapfile -d '' -t cmd <"$state/$name.cmd"
    export AGENT_JOB=$name
    cd "${cmd[0]}" || exit 1
    status=0
    "${cmd[@]:1}" || status=$?
    echo "$status" >"$state/$name.status.tmp" && mv "$state/$name.status.tmp" "$state/$name.status"
    exit "$status"
    ;;
  daemon)
    ddir=$state/daemons
    mkdir -p "$ddir"
    dunit() { echo "agent-daemon@$1.service"; }
    case "${2:-}" in
      start)
        shift 2
        name=${1:?usage: agent-job daemon start NAME [--notify-thread ID] -- CMD...}
        valid "$name"
        shift
        thread=""
        while [ $# -gt 0 ]; do
          case "$1" in
            --notify-thread) thread=${2:?--notify-thread needs a thread id}; shift 2 ;;
            --) shift; break ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] || die "usage: agent-job daemon start NAME [--notify-thread ID] -- CMD..."
        (umask 077 && env -0 | sed -z 's|^PATH=@binPath@:|PATH=|' >"$ddir/$name.env.tmp")
        printf '%s\0' "$PWD" "$@" >"$ddir/$name.cmd.tmp"
        printf '%s' "$thread" >"$ddir/$name.thread.tmp"
        for f in env cmd thread; do mv "$ddir/$name.$f.tmp" "$ddir/$name.$f"; done
        systemctl --user reset-failed "$(dunit "$name")" 2>/dev/null || true
        systemctl --user restart "$(dunit "$name")" || die "could not start $(dunit "$name")"
        echo "agent-job: $(dunit "$name") started; logs: agent-job daemon logs $name" >&2
        ;;
      stop)
        name=${3:?usage: agent-job daemon stop NAME}
        valid "$name"
        rm -f "$ddir/$name.env" "$ddir/$name.cmd" "$ddir/$name.thread"
        exec systemctl --user stop "$(dunit "$name")"
        ;;
      list)
        for f in "$ddir"/*.cmd; do
          [ -e "$f" ] || continue
          n=$(basename "$f" .cmd)
          printf '%-30s %s\n' "$n" "$(systemctl --user is-active "$(dunit "$n")")"
        done
        ;;
      logs)
        valid "${3:?usage: agent-job daemon logs NAME}"
        exec journalctl --user --no-pager -u "$(dunit "$3")"
        ;;
      restore)
        # agent-daemons.service: bring back every registered daemon that is
        # down, then say which ones were.
        down=()
        for f in "$ddir"/*.cmd; do
          [ -e "$f" ] || continue
          n=$(basename "$f" .cmd)
          systemctl --user is-active --quiet "$(dunit "$n")" && continue
          down+=("$n")
          systemctl --user reset-failed "$(dunit "$n")" 2>/dev/null || true
          systemctl --user start --no-block "$(dunit "$n")"
        done
        [ ${#down[@]} -gt 0 ] || { echo "all registered daemons are running"; exit 0; }
        sleep 15
        report=""
        for n in "${down[@]}"; do
          report+="$n: was down, now $(systemctl --user is-active "$(dunit "$n")")"$'\n'
        done
        echo "$report"
        msg="agent-daemons on $(uname -n) restarted daemons that were down (after a login, a user-manager restart or a T3 Code start):"$'\n'"$report"
        notify-erik -t "Agent daemons restarted" "$msg" || true
        # Each daemon's owner thread hears about its own; the T3 server may
        # still be starting.
        declare -A threads=()
        for n in "${down[@]}"; do
          t=$(cat "$ddir/$n.thread" 2>/dev/null || true)
          [ -n "$t" ] && threads[$t]+="$n: now $(systemctl --user is-active "$(dunit "$n")")"$'\n'
        done
        for t in "${!threads[@]}"; do
          for _ in $(seq 1 24); do
            t3 thread send "$t" "Automated (agent-daemons.service): these agent daemons of yours were down and have been restarted. The user manager or the machine restarted; check their state with \`agent-job daemon list\`."$'\n'"${threads[$t]}" >/dev/null 2>&1 && break
            sleep 5
          done
        done
        ;;
      *) die "usage: agent-job daemon start|stop|list|logs|restore ..." ;;
    esac
    ;;
  __daemon)
    name=$2
    ddir=$state/daemons
    [ -e "$ddir/$name.cmd" ] || { echo "agent-job: daemon $name is not registered (agent-job daemon start)" >&2; exit 0; }
    while IFS= read -r -d '' kv; do
      # shellcheck disable=SC2163 # the variable named by kv
      export "$kv" 2>/dev/null || true
    done <"$ddir/$name.env"
    mapfile -d '' -t cmd <"$ddir/$name.cmd"
    export AGENT_JOB=daemon-$name
    cd "${cmd[0]}" || exit 1
    exec "${cmd[@]:1}" </dev/null
    ;;
  *)
    sed -n '/^#   agent-job/,/^# environment/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
