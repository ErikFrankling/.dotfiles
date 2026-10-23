# lag-guard: a safety net against LONG heavy agent work on the pc. Short
# compiles, builds, typechecks and tests are fine here (fast CPU, and the
# agent slice caps keep the desktop smooth); what Erik minds is something
# hogging the pc for minutes. Runs as root every INTERVAL seconds over every
# process in the agent slice (app-t3code.slice, except Erik's T3 terminals):
#
#   - Sustained CPU: when the agents together averaged CPU_CORES+ cores (the
#     slice quota is 4) over the last CPU_WINDOW seconds, the biggest
#     consumers are killed until what is left is under CPU_CORES - 1.
#   - Long emulators: an Android emulator running longer than EMU_MAX.
#   - Pressure: when Erik's own cgroups stall on disk IO or memory (avg10 over
#     IO_FULL / MEM_FULL for SUSTAIN samples), local Nix builds and the
#     biggest agent job are stopped.
#   - Agent thrash: when the agent slice stalls on memory (full avg10 over
#     AGENT_MEM_FULL) while the disk stalls (over AGENT_IO_FULL) for
#     AGENT_SUSTAIN samples, its biggest job.
#
# A killed process gets the reason on its stderr (the agent's tool output),
# telling the agent to re-run it on the homelab with `heavy`. Erik gets one
# notification per NOTIFY_EVERY seconds.
#
# Environment: INTERVAL, CPU_CORES, CPU_WINDOW, EMU_MAX, IO_FULL, MEM_FULL,
# SUSTAIN, NOTIFY_EVERY, ERIK_UID, DRY_RUN=1.

# A watchdog must not die on a failed test or a vanished pid.
set +o errexit +o pipefail

INTERVAL=${INTERVAL:-2}
CPU_CORES=${CPU_CORES:-3}
CPU_WINDOW=${CPU_WINDOW:-300}
EMU_MAX=${EMU_MAX:-900}
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
hz=$(getconf CLK_TCK)
providers='^(\.?claude(-wrapped)?|\.?codex.*|\.?opencode.*|\.?cursor-agent.*|\.?grok.*)$'
homelab_hint="That was a long job for Erik's pc: re-run it on the homelab with heavy -- <cmd> (emulator: heavy emulator start; Nix: nix-remote or rebuild --remote). Short builds and tests are fine on the pc."

# All agent pids, minus Erik's T3 terminals.
agent_pids() {
  find "$agents" -name cgroup.procs -not -path '*/t3code-terminal-*' -exec cat {} + 2>/dev/null
}

rss_of() { awk '/^VmRSS/ { print $2; exit }' "/proc/$1/status" 2>/dev/null; }
ticks_of() { awk '{ sub(/^.*\) /, ""); print $12 + $13 }' "/proc/$1/stat" 2>/dev/null; }

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

check_emulators() {
  local pid age
  for pid in $(agent_pids); do
    case $(cat "/proc/$pid/comm" 2>/dev/null) in qemu-system* | emulator*) ;; *) continue ;; esac
    age=$(ps -o etimes= -p "$pid" 2>/dev/null)
    [ "${age:-0}" -gt "$EMU_MAX" ] && stop "$pid" "an emulator ran over $((EMU_MAX / 60)) minutes on the pc"
  done
  return 0
}

declare -A ticks_then=()
usage_then=""
window_start=$SECONDS
check_cpu() {
  local usage pid comm t cores span
  usage=$(awk '/^usage_usec/ { print $2 }' "$agents/cpu.stat" 2>/dev/null)
  span=$((SECONDS - window_start))
  if [ -n "$usage_then" ] && [ "$span" -ge "$CPU_WINDOW" ]; then
    cores=$(awk -v u=$((usage - usage_then)) -v s="$span" 'BEGIN { printf "%.1f", u / s / 1000000 }')
    if awk -v c="$cores" -v l="$CPU_CORES" 'BEGIN { exit !(c >= l) }'; then
      echo "agents used $cores cores over ${span}s"
      # Kill the biggest consumers until what is left is under CPU_CORES - 1
      # cores. Many small workers (make -j16, stress) count together.
      local list=() total=0 left keep
      for pid in $(agent_pids); do
            comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
        [[ $comm =~ $providers ]] && continue
        t=$(ticks_of "$pid")
        [ -n "$t" ] || continue
        t=$((t - ${ticks_then[$pid]:-0}))
        [ "$t" -gt 0 ] || continue
        list+=("$t $pid")
        total=$((total + t))
      done
      left=$total
      keep=$(((CPU_CORES - 1) * span * hz))
      while read -r t pid; do
        [ "$left" -gt "$keep" ] || break
        stop "$pid" "agents averaged $cores cores for $((span / 60)) minutes"
        left=$((left - t))
      done < <(printf "%s\n" "${list[@]}" | sort -rn)
    fi
    usage_then=""
  fi
  if [ -z "$usage_then" ]; then
    usage_then=$usage
    window_start=$SECONDS
    ticks_then=()
    for pid in $(agent_pids); do
      t=$(ticks_of "$pid")
      [ -n "$t" ] && ticks_then[$pid]=$t
    done
  fi
}

# Erik's side only: his session (Hyprland, browsers) and his own apps, not
# the agent slice, whose throttled IO would otherwise read as a pc stall.
full() { # io|memory -> highest "full" avg10 across Erik's cgroups
  local f
  for f in "/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice"/session-*.scope "/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice"/*; do
    case $f in */app-t3code.slice) continue ;; esac
    [ -r "$f/$1.pressure" ] && awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d\n", $i } }' "$f/$1.pressure"
  done | sort -n | tail -n 1
}

streak=0
check_pressure() {
  local io mem pid uid rss best=0 best_pid="" reason
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
  # The biggest agent process that is not an agent itself.
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
  [ -n "$best_pid" ] && [ "$best" -gt 500000 ] && stop "$best_pid" "$reason"
  return 0
}

# The agents themselves thrashing: their slice stalls on memory AND the disk
# stalls (they page program code and file cache through the disk Erik shares).
# A slice stalled only on its memory cap while swapping into zram is harmless
# (measured: 20-28 % memory stall, 0 % IO), so that alone is left alone.
agent_streak=0
check_agent_thrash() {
  local mem io pid rss best=0 best_pid=""
  mem=$(awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d", $i } }' "$agents/memory.pressure" 2>/dev/null)
  io=$(awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d", $i } }' /proc/pressure/io)
  if [ "${mem:-0}" -gt "$AGENT_MEM_FULL" ] && [ "${io:-0}" -gt "$AGENT_IO_FULL" ]; then
    agent_streak=$((agent_streak + 1))
  else
    agent_streak=0
  fi
  [ "$agent_streak" -ge "$AGENT_SUSTAIN" ] || return 0
  agent_streak=0
  for pid in $(agent_pids); do
    [[ $(cat "/proc/$pid/comm" 2>/dev/null) =~ $providers ]] && continue
    { tr '\0' ' ' <"/proc/$pid/cmdline"; } 2>/dev/null | grep -Eq 'mcp|channel' && continue
    rss=$(rss_of "$pid")
    if [ "${rss:-0}" -gt "$best" ]; then
      best=$rss
      best_pid=$pid
    fi
  done
  [ -n "$best_pid" ] && [ "$best" -gt 500000 ] && stop "$best_pid" "the agents were thrashing the disk (memory ${mem}% / disk IO ${io}% full-stalled); too big for the agent memory budget"
  return 0
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
    "Stopped agent work on the pc: ${list%; }. It belongs on the homelab." || true
}

echo "lag-guard: agents=$agents cpu>=$CPU_CORES cores/${CPU_WINDOW}s io>$IO_FULL% mem>$MEM_FULL%"
while true; do
  check_emulators
  check_cpu
  check_pressure
  check_agent_thrash
  flush_notify
  sleep "$INTERVAL"
done
