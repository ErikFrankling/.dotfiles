# lag-guard: agents do not run heavy work on the pc. Runs as root every
# INTERVAL seconds over every process in the agent slice (app-t3code.slice,
# except Erik's own T3 terminals):
#
#   - Denied outright, killed on sight: Android emulators (qemu), Gradle and
#     Kotlin daemons, compilers (rustc, cc1, clang), llama-server, a `nix`
#     evaluation over NIX_RSS, and node/python/tsgo processes over BIG_RSS.
#   - CPU: when the agents together averaged over CPU_CORES cores for the
#     last CPU_WINDOW seconds, every non-provider process that used over half
#     a core in that window is killed.
#   - Pressure: when the whole pc stalls on disk IO or memory (avg10 over
#     IO_FULL / MEM_FULL for SUSTAIN samples), it stops local Nix builds and
#     the biggest agent process.
#
# Each stopped process first gets the reason on its stderr, which is the
# owning agent's tool output, so the agent learns why. Erik gets one
# notification per NOTIFY_EVERY seconds listing what was stopped.
#
# Environment: INTERVAL, CPU_CORES, CPU_WINDOW, IO_FULL, MEM_FULL, SUSTAIN,
# BIG_RSS, NIX_RSS (KiB), NOTIFY_EVERY, ERIK_UID, DRY_RUN=1.

# A watchdog must not die on a failed test or a vanished pid.
set +o errexit +o pipefail

INTERVAL=${INTERVAL:-2}
CPU_CORES=${CPU_CORES:-3}
CPU_WINDOW=${CPU_WINDOW:-60}
IO_FULL=${IO_FULL:-20}
MEM_FULL=${MEM_FULL:-10}
SUSTAIN=${SUSTAIN:-5}
BIG_RSS=${BIG_RSS:-2000000}
NIX_RSS=${NIX_RSS:-700000}
NOTIFY_EVERY=${NOTIFY_EVERY:-900}
ERIK_UID=${ERIK_UID:-1000}
DRY_RUN=${DRY_RUN:-0}
IDLE_FLAG=${IDLE_FLAG:-/run/user/$ERIK_UID/erik-idle}
BUSY_MEM_HIGH=${BUSY_MEM_HIGH:-9G}
BUSY_MEM_MAX=${BUSY_MEM_MAX:-11G}
IDLE_MEM_HIGH=${IDLE_MEM_HIGH:-18G}
IDLE_MEM_MAX=${IDLE_MEM_MAX:-20G}
BUSY_CPU=${BUSY_CPU:-400000 100000}
IDLE_CPU=${IDLE_CPU:-1200000 100000}

agents=/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice/app-t3code.slice
nixd=/sys/fs/cgroup/system.slice/nix-daemon.service
hz=$(getconf CLK_TCK)
providers='^(\.?claude(-wrapped)?|\.?codex.*|\.?opencode.*|\.?cursor-agent.*|\.?grok.*)$'
denied_comm='^(qemu-system.*|emulator|emulator64.*|llama-server|rustc|cc1|cc1plus|cc1obj|clang|clang\+\+|clang-[0-9]+|ld\.lld)$'
denied_java='GradleDaemon|GradleWrapperMain|org\.gradle\.|KotlinCompileDaemon'
homelab_hint="Heavy work runs on the homelab, not on Erik's pc: heavy -- <cmd> (builds, tests, emulator: heavy emulator start), rebuild, nix-remote build|eval."

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

check_denied() {
  local pid comm rss
  for pid in $(agent_pids); do
    [ -n "${paused[$pid]:-}" ] && continue
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    [[ $comm =~ $providers ]] && continue
    if [[ $comm =~ $denied_comm ]]; then
      stop "$pid" "$comm does not run on the pc"
      continue
    fi
    case $comm in
      java)
        if tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -Eq "$denied_java"; then
          stop "$pid" "Gradle/Kotlin builds do not run on the pc"
        fi
        ;;
      nix)
        rss=$(rss_of "$pid")
        [ "${rss:-0}" -gt "$NIX_RSS" ] && stop "$pid" "a local Nix evaluation"
        ;;
      node | MainThread | python* | tsgo | tsc | bun | deno)
        rss=$(rss_of "$pid")
        [ "${rss:-0}" -gt "$BIG_RSS" ] && stop "$pid" "over $((BIG_RSS / 1000000)) GB of memory"
        ;;
    esac
  done
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
        [ -n "${paused[$pid]:-}" ] && continue
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
        stop "$pid" "agents averaged $cores cores for a minute"
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
    tr '\0' ' ' <"/proc/$pid/cmdline" 2>/dev/null | grep -Eq 'mcp|channel' && continue
    rss=$(rss_of "$pid")
    if [ "${rss:-0}" -gt "$best" ]; then
      best=$rss
      best_pid=$pid
    fi
  done
  [ -n "$best_pid" ] && [ "$best" -gt 500000 ] && stop "$best_pid" "$reason"
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

# Idle windows: while Erik has been away from keyboard and mouse for 10
# minutes (erik-idle.service keeps $IDLE_FLAG), agents may run heavy jobs on
# the pc, one emulator at most, with more CPU and memory. When he is back,
# those jobs are paused (SIGSTOP) within a second, and resumed at the next
# idle window. If pausing leaves Erik short of memory, the biggest paused
# jobs are killed instead.
declare -A paused=() idle_ticks=()
cg_write() { [ "$DRY_RUN" = 1 ] || echo "$2" >"$agents/$1" 2>/dev/null; }

tell() { # pid message
  # shellcheck disable=SC2016
  timeout 1 sh -c 'printf "\n[lag-guard] %s\n" "$2" > "/proc/$1/fd/2"' _ "$1" "$2" 2>/dev/null
}

enter_idle() {
  local pid t
  echo "Erik is idle: heavy agent jobs allowed"
  cg_write cpu.max "$IDLE_CPU"
  cg_write memory.max "$IDLE_MEM_MAX"
  cg_write memory.high "$IDLE_MEM_HIGH"
  for pid in "${!paused[@]}"; do
    [ "$DRY_RUN" = 1 ] || kill -CONT "$pid" 2>/dev/null
    tell "$pid" "Resumed: Erik is idle again."
  done
  paused=()
  idle_ticks=()
  for pid in $(agent_pids); do
    t=$(ticks_of "$pid")
    [ -n "$t" ] && idle_ticks[$pid]=$t
  done
}

idle_tick() {
  local pid comm emus=() mem
  for pid in $(agent_pids); do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    [[ $comm == qemu-system* ]] && emus+=("$pid")
  done
  # One emulator at a time: the oldest keeps running.
  if [ ${#emus[@]} -gt 1 ]; then
    mapfile -t emus < <(ps -o pid= --sort=start_time -p "$(
      IFS=,
      echo "${emus[*]}"
    )")
    for pid in "${emus[@]:1}"; do stop "${pid// /}" "only one emulator runs on the pc, even while Erik is away"; done
  fi
  mem=$(full memory)
  [ "${mem:-0}" -gt 40 ] && MEM_FULL=40 check_pressure
  return 0
}

leave_idle() {
  local pid comm t base avail cur max rss best best_pid
  echo "Erik is back: pausing heavy agent jobs"
  for pid in $(agent_pids); do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    [[ $comm =~ $providers ]] && continue
    t=$(ticks_of "$pid") || continue
    base=${idle_ticks[$pid]:-0}
    # Anything that used over 10 s of CPU during the window, or is denied.
    if [ $((${t:-0} - base)) -gt $((10 * hz)) ] || [[ $comm =~ $denied_comm ]]; then
      [ "$DRY_RUN" = 1 ] || kill -STOP "$pid" 2>/dev/null
      paused[$pid]=1
      echo "paused $pid $comm"
      tell "$pid" "Paused $comm (pid $pid): Erik is back at the pc. It resumes at his next idle window (pc-idle)."
    fi
  done
  cg_write cpu.max "$BUSY_CPU"
  cg_write memory.high "$BUSY_MEM_HIGH"
  # Never set memory.max below what is in use (that would OOM-kill).
  cur=$(cat "$agents/memory.current" 2>/dev/null)
  max=$(numfmt --from=iec "$BUSY_MEM_MAX")
  [ "${cur:-0}" -gt "$max" ] && max=$((cur + 512 * 1024 * 1024))
  cg_write memory.max "$max"
  # Keep at least 4 GB available for Erik: kill the biggest paused jobs.
  while :; do
    avail=$(awk '/^MemAvailable/ { print $2 }' /proc/meminfo)
    [ "${avail:-0}" -lt 4000000 ] || break
    best=0 best_pid=""
    for pid in "${!paused[@]}"; do
      rss=$(rss_of "$pid")
      if [ "${rss:-0}" -gt "$best" ]; then
        best=$rss
        best_pid=$pid
      fi
    done
    [ -n "$best_pid" ] || break
    [ "$DRY_RUN" = 1 ] || kill -CONT "$best_pid" 2>/dev/null
    unset "paused[$best_pid]"
    stop "$best_pid" "Erik is back and needs the memory"
    [ "$DRY_RUN" = 1 ] && break
    sleep 1
  done
}

busy_tick() {
  local pid cur max
  for pid in "${!paused[@]}"; do
    [ -d "/proc/$pid" ] || unset "paused[$pid]"
  done
  # memory.max back to normal once usage allows it.
  max=$(numfmt --from=iec "$BUSY_MEM_MAX")
  cur=$(cat "$agents/memory.current" 2>/dev/null)
  if [ "$(cat "$agents/memory.max" 2>/dev/null)" != "$max" ] && [ "${cur:-0}" -lt "$max" ]; then
    cg_write memory.max "$max"
  fi
}

echo "lag-guard: agents=$agents cpu>=$CPU_CORES cores/${CPU_WINDOW}s io>$IO_FULL% mem>$MEM_FULL% idle-flag=$IDLE_FLAG"
idle=0
while true; do
  if [ -e "$IDLE_FLAG" ]; then
    [ "$idle" = 1 ] || enter_idle
    idle=1
    idle_tick
    sleep 1
    continue
  fi
  if [ "$idle" = 1 ]; then
    leave_idle
    idle=0
    usage_then=""
  fi
  busy_tick
  check_denied
  check_cpu
  check_pressure
  flush_notify
  sleep "$INTERVAL"
done
