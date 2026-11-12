# lag-guard: stops agent work when it actually stalls Erik's desktop. It
# measures the stall, not the work: there is no CPU-time or run-time limit, so
# long builds, test suites and emulators run on the pc for as long as the
# desktop stays smooth (the agent slice caps in default.nix do most of that).
# Runs as root every INTERVAL seconds over every process in the agent slice
# (app-t3code.slice, except Erik's T3 terminals):
#
#   - Pressure: when Erik's own cgroups stall on disk IO or memory (avg10 over
#     IO_FULL / MEM_FULL for SUSTAIN samples in a row), local Nix builds and
#     the biggest agent job are stopped.
#   - Agent thrash: when the agent slice stalls on memory (full avg10 over
#     AGENT_MEM_FULL) while the disk stalls (over AGENT_IO_FULL), its biggest
#     job. A sample over both limits counts up, any other sample counts down,
#     and it acts at AGENT_SUSTAIN. (It used to need AGENT_SUSTAIN samples in
#     a row; on 2026-11-12 the slice thrashed for 3 hours at avg300 25 % /
#     30 % and never fired, because avg10 dips kept resetting the count.)
#
# Until 2026-11-12 it also killed whatever kept the agents at 3+ cores for 5
# minutes and any emulator older than 15 minutes, with a "max mode"
# (`agent-max on`, only while Erik was away) that lifted those and the 4-core
# cap. Erik had it removed: "now it's really in the way when I need agents to
# do large scale workloads". One set of caps now, the same whether he is at
# the pc or not.
#
# A killed process gets the reason on its stderr (the agent's tool output),
# telling the agent to re-run it on the homelab with `heavy`. Erik gets one
# notification per NOTIFY_EVERY seconds.
#
# Environment: INTERVAL, IO_FULL, MEM_FULL, SUSTAIN, AGENT_MEM_FULL,
# AGENT_IO_FULL, AGENT_SUSTAIN, NOTIFY_EVERY, ERIK_UID, DRY_RUN=1.

# A watchdog must not die on a failed test or a vanished pid.
set +o errexit +o pipefail

INTERVAL=${INTERVAL:-2}
IO_FULL=${IO_FULL:-20}
MEM_FULL=${MEM_FULL:-10}
AGENT_MEM_FULL=${AGENT_MEM_FULL:-20}
AGENT_SUSTAIN=${AGENT_SUSTAIN:-15}
AGENT_IO_FULL=${AGENT_IO_FULL:-10}
SUSTAIN=${SUSTAIN:-5}
NOTIFY_EVERY=${NOTIFY_EVERY:-900}
ERIK_UID=${ERIK_UID:-1000}
DRY_RUN=${DRY_RUN:-0}

agents=/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice/app-t3code.slice
nixd=/sys/fs/cgroup/system.slice/nix-daemon.service
providers='^(\.?claude(-wrapped)?|\.?codex.*|\.?opencode.*|\.?cursor-agent.*|\.?grok.*)$'
homelab_hint="It was too much for Erik's pc right now: re-run it on the homelab with heavy -- <cmd> (emulator: heavy emulator start; Nix: nix-remote or rebuild --remote), or with fewer parallel jobs."

# All agent pids, minus Erik's T3 terminals.
agent_pids() {
  find "$agents" -name cgroup.procs -not -path '*/t3code-terminal-*' -exec cat {} + 2>/dev/null
}

rss_of() { awk '/^VmRSS/ { print $2; exit }' "/proc/$1/status" 2>/dev/null; }

pending=()
stop() { # pid reason
  local pid=$1 reason=$2 comm rss
  comm=$(cat "/proc/$pid/comm" 2>/dev/null) || return 0
  rss=$(rss_of "$pid")
  rss=$(awk -v k="${rss:-0}" 'BEGIN { printf "%.1fG", k / 1048576 }')
  echo "stopping $pid $comm ($rss): $reason"
  pending+=("$comm ($reason)")
  [ "$DRY_RUN" = 1 ] && return 0
  # Tell the agent through the process's own stderr; never block on it.
  # shellcheck disable=SC2016
  timeout 1 sh -c 'printf "\n[lag-guard] Killed %s (pid %s): %s. %s\n" "$1" "$2" "$3" "$4" > "/proc/$2/fd/2"' \
    _ "$comm" "$pid" "$reason" "$homelab_hint" 2>/dev/null
  kill -TERM "$pid" 2>/dev/null
  (
    sleep 5
    kill -KILL "$pid" 2>/dev/null
  ) &
}

# The biggest agent process that is not an agent itself (over 0.5 GB).
stop_biggest() { # reason
  local pid rss best=0 best_pid=""
  for pid in $(agent_pids); do
    [[ $(cat "/proc/$pid/comm" 2>/dev/null) =~ $providers ]] && continue
    # MCP servers are the agents' tools; killing one breaks a session.
    { tr '\0' ' ' <"/proc/$pid/cmdline"; } 2>/dev/null | grep -Eq 'mcp|channel' && continue
    rss=$(rss_of "$pid")
    if [ "${rss:-0}" -gt "$best" ]; then
      best=$rss
      best_pid=$pid
    fi
  done
  [ -n "$best_pid" ] && [ "$best" -gt 500000 ] && stop "$best_pid" "$1"
  return 0
}

# Erik's side only: his session (Hyprland, browsers) and his own apps, not
# the agent slice, whose throttled IO would otherwise read as a pc stall.
full() { # io|memory -> highest "full" avg10 across Erik's cgroups
  local f
  for f in "/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice"/session-*.scope "/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice"/*; do
    case $f in */app-t3code.slice) continue ;; esac
    # A background service with its own memory cap (search-sync, x-graph)
    # stalls against that cap by design; that is not Erik's desktop. On
    # 2026-11-03 the hourly search-sync run (MemoryMax=3G, 20-38 % full at
    # its own limit, every other cgroup 0 %) got three agent jobs killed.
    if [ "$1" = memory ] && { [ "$(cat "$f/memory.max" 2>/dev/null)" != max ] || [ "$(cat "$f/memory.high" 2>/dev/null)" != max ]; }; then
      continue
    fi
    [ -r "$f/$1.pressure" ] && awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d\n", $i } }' "$f/$1.pressure"
  done | sort -n | tail -n 1
}

streak=0
check_pressure() {
  local io mem pid uid reason
  io=$(full io)
  mem=$(full memory)
  if [ "${io:-0}" -gt "$IO_FULL" ] || [ "${mem:-0}" -gt "$MEM_FULL" ]; then
    streak=$((streak + 1))
  else
    streak=0
  fi
  [ "$streak" -ge "$SUSTAIN" ] || return 0
  streak=0
  reason="the pc was stalling (disk IO ${io}% / memory ${mem}% full)"
  # Local Nix builds (build users are not root).
  local nixpids
  mapfile -t nixpids < <(find "$nixd" -name cgroup.procs -exec cat {} + 2>/dev/null)
  for pid in "${nixpids[@]}"; do
    uid=$(awk '/^Uid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    [ "${uid:-0}" != 0 ] && stop "$pid" "$reason"
  done
  stop_biggest "$reason"
}

# The agents themselves thrashing: their slice stalls on memory AND the disk
# stalls (they page program code and file cache through the disk Erik shares).
# A slice stalled only on its memory cap while swapping into zram is harmless
# (measured: 20-28 % memory stall, 0 % IO), so that alone is left alone.
agent_streak=0
check_agent_thrash() {
  local mem io
  mem=$(awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d", $i } }' "$agents/memory.pressure" 2>/dev/null)
  io=$(awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d", $i } }' /proc/pressure/io)
  if [ "${mem:-0}" -gt "$AGENT_MEM_FULL" ] && [ "${io:-0}" -gt "$AGENT_IO_FULL" ]; then
    agent_streak=$((agent_streak + 1))
  elif [ "$agent_streak" -gt 0 ]; then
    agent_streak=$((agent_streak - 1))
  fi
  [ "$agent_streak" -ge "$AGENT_SUSTAIN" ] || return 0
  agent_streak=0
  stop_biggest "the agents were thrashing the disk (memory ${mem}% / disk IO ${io}% full-stalled); too big for the agent memory budget"
}

last_notify=-100000
flush_notify() {
  [ ${#pending[@]} -gt 0 ] || return 0
  [ $((SECONDS - last_notify)) -ge "$NOTIFY_EVERY" ] || return 0
  local list
  list=$(printf '%s\n' "${pending[@]}" | sort | uniq -c | awk '{ n = $1; $1 = ""; sub(/^ /, ""); printf "%s%s; ", $0, (n > 1 ? " x" n : "") }' | head -c 600)
  pending=()
  last_notify=$SECONDS
  if [ "$DRY_RUN" = 1 ]; then
    echo "would notify: $list"
    return 0
  fi
  notify-erik --priority normal --title "PC lag guard" --tags warning \
    "Stopped agent work that was stalling the pc: ${list%; }." || true
}

echo "lag-guard: agents=$agents io>$IO_FULL% mem>$MEM_FULL% for $((SUSTAIN * INTERVAL))s, agent thrash mem>$AGENT_MEM_FULL% io>$AGENT_IO_FULL% for $((AGENT_SUSTAIN * INTERVAL))s"
while true; do
  check_pressure
  check_agent_thrash
  flush_notify
  sleep "$INTERVAL"
done
