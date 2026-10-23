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
  # The unit starts with the user manager's environment; give it this one.
  (umask 077 && env -0 >"$state/$name.env")
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
    if [ -n "${AGENT_JOB:-}" ] || ! is_agent; then exec "$@"; fi
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
  *)
    sed -n '/^#   agent-job/,/^# environment/p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
