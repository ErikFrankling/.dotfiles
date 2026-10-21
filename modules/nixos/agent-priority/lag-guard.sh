# lag-guard: when the pc keeps stalling on disk IO or memory, stop agents'
# heavy jobs, emulators first, and tell Erik what was stopped. Runs as root
# (it also stops local Nix builds). Heavy agent work belongs on the homelab
# (`heavy`, `nix-remote`); this catches what slipped through.
#
# Levels, one per trigger, each followed by a cooldown:
#   1. Android emulators (qemu) in the agent slice
#   2. local Nix builds (nix-daemon build users) and big `nix` evaluations
#   3. compilers, Gradle, llama-server, typecheckers and any agent process
#      over BIG_RSS, plus every unit an agent started with systemd-run
#
# Environment: IO_FULL / MEM_FULL (avg10 % thresholds), SUSTAIN (samples),
# INTERVAL (s), COOLDOWN (s), BIG_RSS (KiB), ERIK_UID, DRY_RUN=1.

# A watchdog must not die on a failed test or a vanished pid.
set +o errexit +o pipefail

IO_FULL=${IO_FULL:-20}
MEM_FULL=${MEM_FULL:-10}
SUSTAIN=${SUSTAIN:-3}
INTERVAL=${INTERVAL:-5}
COOLDOWN=${COOLDOWN:-60}
BIG_RSS=${BIG_RSS:-1500000}
ERIK_UID=${ERIK_UID:-1000}
DRY_RUN=${DRY_RUN:-0}

agents=/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice/app-t3code.slice
nixd=/sys/fs/cgroup/system.slice/nix-daemon.service
heavy_comm='^(java|clang.*|cc1.*|c\+\+|g\+\+|gcc|ld|ld\.lld|lld|rustc|cargo|make|ninja|cmake|llama-server|tsgo|tsc|ffmpeg|stress-ng.*|qemu-system.*|emulator.*)$'

full() { awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d", $i } }' "/proc/pressure/$1"; }

pids_under() { find "$1" -name cgroup.procs -exec cat {} + 2>/dev/null; }

describe() { # pid -> "comm (1.2G)"
  local comm rss
  comm=$(cat "/proc/$1/comm" 2>/dev/null) || return 1
  rss=$(awk '/^VmRSS/ { printf "%.1fG", $2 / 1048576 }' "/proc/$1/status" 2>/dev/null)
  echo "$comm (${rss:-?})"
}

stopped=()
stop_pids() { # pids...
  local pid d
  for pid in "$@"; do
    d=$(describe "$pid") || continue
    stopped+=("$d")
    echo "stopping $pid $d"
    [ "$DRY_RUN" = 1 ] || kill -TERM "$pid" 2>/dev/null
  done
  [ "$DRY_RUN" = 1 ] && return
  sleep 5
  for pid in "$@"; do kill -KILL "$pid" 2>/dev/null; done
}

level_emulators() {
  local pid out=()
  for pid in $(pids_under "$agents"); do
    case $(cat "/proc/$pid/comm" 2>/dev/null) in qemu-system* | emulator*) out+=("$pid") ;; esac
  done
  [ ${#out[@]} -gt 0 ] && stop_pids "${out[@]}"
}

level_nix() {
  local pid uid rss out=()
  for pid in $(pids_under "$nixd"); do
    uid=$(awk '/^Uid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null) || continue
    [ "${uid:-0}" != 0 ] && out+=("$pid")
  done
  for pid in $(pids_under "$agents"); do
    [ "$(cat "/proc/$pid/comm" 2>/dev/null)" = nix ] || continue
    rss=$(awk '/^VmRSS/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    [ "${rss:-0}" -gt 1000000 ] && out+=("$pid")
  done
  [ ${#out[@]} -gt 0 ] && stop_pids "${out[@]}"
}

level_heavy() {
  local pid comm rss out=() unit
  for pid in $(pids_under "$agents"); do
    comm=$(cat "/proc/$pid/comm" 2>/dev/null) || continue
    case $comm in claude | codex | opencode | cursor-agent | grok) continue ;; esac
    rss=$(awk '/^VmRSS/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    if [[ $comm =~ $heavy_comm ]] || [ "${rss:-0}" -gt "$BIG_RSS" ]; then out+=("$pid"); fi
  done
  # Units agents started with systemd-run (the wrapper keeps them here).
  for unit in "$agents"/app-t3code-agents.slice/*/*.s*; do
    [ -d "$unit" ] || continue
    case ${unit##*/} in t3code-*) continue ;; esac
    for pid in $(pids_under "$unit"); do out+=("$pid"); done
  done
  [ ${#out[@]} -gt 0 ] || return 0
  mapfile -t out < <(printf "%s\n" "${out[@]}" | sort -un)
  stop_pids "${out[@]}"
}

notify() {
  [ "$DRY_RUN" = 1 ] && { echo "would notify: $1"; return; }
  notify-erik --priority normal --title "PC lag guard" --tags warning "$1" || true
}

streak=0
level=1
echo "lag-guard: io full > $IO_FULL% or memory full > $MEM_FULL% for $SUSTAIN samples of ${INTERVAL}s"
while true; do
  io=$(full io)
  mem=$(full memory)
  if [ "${io:-0}" -gt "$IO_FULL" ] || [ "${mem:-0}" -gt "$MEM_FULL" ]; then
    streak=$((streak + 1))
  else
    streak=0
    level=1
  fi

  if [ "$streak" -ge "$SUSTAIN" ]; then
    stopped=()
    while [ "$level" -le 3 ] && [ ${#stopped[@]} -eq 0 ]; do
      case $level in
        1) level_emulators ;;
        2) level_nix ;;
        3) level_heavy ;;
      esac
      level=$((level + 1))
    done
    if [ ${#stopped[@]} -gt 0 ]; then
      list=$(printf '%s, ' "${stopped[@]}")
      notify "The PC was stalling (disk IO ${io}%, memory ${mem}% full). Stopped agent work: ${list%, }. Heavy jobs belong on the homelab (heavy, nix-remote)."
    else
      level=1
      echo "pressure high (io $io%, mem $mem%) but no agent heavy jobs left to stop"
    fi
    streak=0
    sleep "$COOLDOWN"
    continue
  fi
  sleep "$INTERVAL"
done
