# agent-max: Erik's "max mode" for agents on the pc (Erik, 2026-11-11: "you
# can build on the entire pc max it out i am not on the pc"). While on, the
# agent slice (app-t3code.slice) gets most of the machine and lag-guard stops
# killing long builds. It turns itself off when Erik touches a physical
# keyboard or mouse (agent-max-watch) or when its time runs out.
#
#   agent-max on [HOURS]   on for HOURS (default @defaultHours@), only when Erik said he is away
#   agent-max off          back to the normal agent caps
#   agent-max status       prints the state; exit 0 when on, 1 when off
#
# Runtime only (systemctl --user set-property --runtime, state under
# $XDG_RUNTIME_DIR): a reboot or logout returns to the normal caps. The slice
# itself is declared in default.nix; nothing restarts.

state_dir=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/agent-max
until_file=$state_dir/until
slice=app-t3code.slice
cg=/sys/fs/cgroup/user.slice/user-$(id -u).slice/user@$(id -u).service/app.slice/$slice

apply() { # cpu memhigh memmax
  systemctl --user set-property --runtime "$slice" "CPUQuota=$1" "MemoryHigh=$2" "MemoryMax=$3"
}

is_on() {
  local until
  until=$(cat "$until_file" 2>/dev/null) || return 1
  [ "${until:-0}" -gt "$(date +%s)" ]
}

status() {
  local cpu high max
  read -r q p <"$cg/cpu.max"
  if [ "$q" = max ]; then cpu=unlimited; else cpu="$((q / p)) CPUs"; fi
  high=$(numfmt --to=iec <"$cg/memory.high" 2>/dev/null || cat "$cg/memory.high")
  max=$(numfmt --to=iec <"$cg/memory.max" 2>/dev/null || cat "$cg/memory.max")
  if is_on; then
    echo "agent-max: ON until $(date -d "@$(cat "$until_file")" '+%F %H:%M') (turns off when Erik uses a keyboard or mouse)"
  else
    echo "agent-max: OFF (normal agent caps; long jobs go to the homelab with heavy)"
  fi
  echo "app-t3code.slice: $cpu, MemoryHigh $high, MemoryMax $max"
  is_on
}

case ${1:-status} in
  on)
    hours=${2:-@defaultHours@}
    case $hours in '' | *[!0-9]*) echo "agent-max: HOURS must be a whole number" >&2; exit 2 ;; esac
    mkdir -p "$state_dir"
    echo $(($(date +%s) + hours * 3600)) >"$until_file"
    apply @maxCpu@ @maxMemoryHigh@ @maxMemoryMax@
    # Restart so the watcher picks up the new deadline.
    systemctl --user restart agent-max-watch.service
    status
    ;;
  off)
    rm -f "$until_file"
    apply @cpu@ @memoryHigh@ @memoryMax@
    # From the watcher itself this stop is its own exit; never wait on it.
    systemctl --user stop --no-block agent-max-watch.service
    [ -n "${2:-}" ] && notify-erik --priority low --title "Agent max mode off" "$2" >/dev/null 2>&1
    status
    true
    ;;
  status) status ;;
  *)
    echo "usage: agent-max on [HOURS] | off | status" >&2
    exit 2
    ;;
esac
