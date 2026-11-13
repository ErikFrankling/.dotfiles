# lag-guard: stops agent work when it actually stalls Erik's desktop. It
# measures the stall, not the work: there is no CPU-time or run-time limit, so
# long builds, test suites and emulators run on the pc for as long as the
# desktop stays smooth (the agent slice caps in default.nix do most of that).
# Runs as root every INTERVAL seconds over every process in the agent slice
# (app-t3code.slice, except Erik's T3 terminals):
#
#   - Pressure: when Erik's own cgroups stall on disk IO or memory (avg10 over
#     IO_FULL / MEM_FULL for SUSTAIN samples in a row), local Nix builds are
#     stopped, and then by the kind of stall:
#       memory (over MEM_FULL): the biggest agent job by RSS is stopped.
#       disk IO: the agents' disk bandwidth on the stalled disk is cut
#         (io.max on the agent slice, one THROTTLE_STEPS step per trigger),
#         and given back a step per RELAX calm samples. Only when the lowest
#         step is on and a disk-only stall goes on for FLOOR_SUSTAIN more
#         triggers is a job stopped: the one doing the most IO on that disk.
#   - Agent thrash: when the agent slice stalls on memory (full avg10 over
#     AGENT_MEM_FULL) while Erik's cgroups stall on disk IO (over
#     AGENT_IO_FULL), its biggest job. A sample over both limits counts up,
#     any other sample counts down, and it acts at AGENT_SUSTAIN. (It used to
#     need AGENT_SUSTAIN samples in a row; on 2026-11-12 the slice thrashed
#     for 3 hours at avg300 25 % / 30 % and never fired, because avg10 dips
#     kept resetting the count.)
#   - Protection breached: Erik's apps have memory.low (default.nix). The
#     kernel reclaims below it only when nothing else is left to reclaim, and
#     counts each time in memory.events "low". When that count rises for
#     SUSTAIN samples in a row the pc is really out of memory: the biggest
#     agent job is stopped.
#
# What counts as a disk stall (2026-11-13): only a stall on a busy device.
# From 08:54 to 10:45 that day lag-guard held the agents at the lowest cap on
# both disks and stopped a process every 30 s (bash, python3, grep at
# 0-2 MB/s) for a "stall" of 34-84 % with nvme0n1 8 % busy. Two causes:
#   - The stalled cgroup was not Erik's: supply-r3f-scope.scope, a wasm-box
#     build an agent job had started with `systemd-run --user --scope`, sat in
#     app.slice (the wrapper's bug, fixed in default.nix) and was read as one
#     of his apps. A cgroup whose first process carries T3CODE_THREAD_ID is
#     agent work, wherever it runs, and is not measured.
#   - PSI "io" counts every wait for a page from disk, also a swap-in of
#     Erik's swapped-out apps, and an agent waiting on the cap itself. Neither
#     gets better when agents write less. So before it caps or stops anything
#     for a disk stall, lag-guard reads how busy the device was (io_ticks);
#     under DEV_BUSY % nothing is capped or stopped, and caps already on are
#     given back as if the desktop were calm.
#
# Why IO stalls throttle first (2026-11-13): until then every stall stopped
# the biggest process by RSS. From 2026-11-12 18:00 to 02:12 that was 194
# kills, nearly all on IO stalls (24-74 % full, memory mostly under 20 %),
# nearly all a rustc of 0.6-2 GB, one every ~15 s while a stall lasted. A
# compiler's RSS says nothing about the disk: the stalled disk was the NVMe
# (write latency 19 ms against 0.1 ms for reads, Erik's swapped-out apps
# waiting on it), written by agent scratch files in /tmp at the slice's cap,
# while the rustc that died wrote to /mnt/data. Each kill threw away minutes
# of compile and its rebuild added IO; wasm-box's shared build of main was
# killed three times in a row and never finished. A bandwidth cap is enforced
# by the kernel whatever the number of writers, and loses no work.
#
# Jobs many sessions wait on: a process with AGENT_JOB_PRIO=1 in its
# environment (WBOX_BUILD_PRIO=1 is read as the same) is passed over as a
# victim while any other candidate exists. It is still throttled, and still
# stopped when it is the only candidate.
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
# AGENT_IO_FULL, AGENT_SUSTAIN, THROTTLE_STEPS, RELAX, FLOOR_SUSTAIN, DEV_BUSY,
# NOTIFY_EVERY, ERIK_UID, STATE, AGENTS_CGROUP (tests), DRY_RUN=1 (stops and
# throttles nothing).

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
# Agent slice caps on the stalled disk, "read:write" bytes/s, from first to
# last step. The slice's own cap on the system disk is 150M:60M (default.nix).
THROTTLE_STEPS=${THROTTLE_STEPS:-"80000000:30000000 40000000:12000000 20000000:5000000"}
RELAX=${RELAX:-30}
FLOOR_SUSTAIN=${FLOOR_SUSTAIN:-2}
# A disk stall counts only when the stalled device was at least this busy (%).
DEV_BUSY=${DEV_BUSY:-50}
# Caps in force and what to put back, so a restart of lag-guard undoes them.
STATE=${STATE:-/run/lag-guard}

agents=${AGENTS_CGROUP:-/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice/app-t3code.slice}
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

# Agents themselves and their MCP servers are never stopped: killing one
# breaks a session.
spared() { # pid
  [[ $(cat "/proc/$1/comm" 2>/dev/null) =~ $providers ]] && return 0
  { tr '\0' ' ' <"/proc/$1/cmdline"; } 2>/dev/null | grep -Eq 'mcp|channel'
}

# A job many sessions wait on (see the header).
prio() { # pid
  { tr '\0' '\n' <"/proc/$1/environ"; } 2>/dev/null | grep -Eqx '(AGENT_JOB_PRIO|WBOX_BUILD_PRIO)=1'
}

# The biggest agent process by RSS that is not an agent itself (over 0.5 GB).
stop_biggest() { # reason
  local pid rss best=0 best_pid="" pbest=0 pbest_pid=""
  for pid in $(agent_pids); do
    spared "$pid" && continue
    rss=$(rss_of "$pid")
    [ "${rss:-0}" -gt 500000 ] || continue
    if prio "$pid"; then
      [ "$rss" -gt "$pbest" ] && pbest=$rss pbest_pid=$pid
    elif [ "$rss" -gt "$best" ]; then
      best=$rss best_pid=$pid
    fi
  done
  if [ -n "$best_pid" ]; then
    stop "$best_pid" "$1"
  elif [ -n "$pbest_pid" ]; then
    stop "$pbest_pid" "$1 (priority job, but nothing else over 0.5 GB was left)"
  fi
  return 0
}

# Erik's side only: his session (Hyprland, browsers) and his own apps, not
# the agent slice, whose throttled IO would otherwise read as a pc stall, and
# not agent work that runs outside the agent slice (see the header). Filled
# once per round, in the main shell so that the verdicts are remembered.
erik=()
declare -A origin=() # cgroup -> "first pid:1" (agent work) or "first pid:0"
refresh_erik() {
  local f pid
  erik=()
  for f in "/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice"/session-*.scope "/sys/fs/cgroup/user.slice/user-$ERIK_UID.slice/user@$ERIK_UID.service/app.slice"/*; do
    case $f in */app-t3code.slice) continue ;; esac
    [ -d "$f" ] || continue
    pid=""
    read -r pid 2>/dev/null <"$f/cgroup.procs"
    if [ -n "$pid" ] && [ "${origin[$f]:-}" != "$pid:0" ] && [ "${origin[$f]:-}" != "$pid:1" ]; then
      if { tr '\0' '\n' <"/proc/$pid/environ"; } 2>/dev/null | grep -q '^T3CODE_THREAD_ID='; then
        origin[$f]="$pid:1"
        echo "${f##*/} is agent work outside the agent slice (pid $pid has T3CODE_THREAD_ID): not measured as Erik's desktop"
      else
        origin[$f]="$pid:0"
      fi
    fi
    [ -n "$pid" ] && [ "${origin[$f]:-}" = "$pid:1" ] && continue
    erik+=("$f")
  done
}

full() { # io|memory -> highest "full" avg10 across Erik's cgroups
  local f
  for f in "${erik[@]}"; do
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

dev_name() { basename "$(readlink -f "/sys/dev/block/$1" 2>/dev/null)" 2>/dev/null; }

# The disk Erik's cgroups are waiting on, as "MAJ:MIN BUSY": the real disk
# (not zram or a loop device) they did the most requests on over a second;
# when they did none, the busiest disk. BUSY is the share of that second the
# device had requests in flight (io_ticks), in percent.
stalled_dev() {
  local files a b b2 dev="" name busy
  [ ${#erik[@]} -gt 0 ] || return 1
  files=("${erik[@]/%//io.stat}")
  a=$(cat "${files[@]}" 2>/dev/null)
  b=$(awk '{ print $3, $13 }' /proc/diskstats)
  sleep 1
  b2=$(awk '{ print $3, $13 }' /proc/diskstats)
  dev=$({
    echo "$a"
    echo --
    cat "${files[@]}" 2>/dev/null
  } | awk '
    /^--$/ { second = 1; next }
    { n = 0
      for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "rios" || kv[1] == "wios") n += kv[2] }
      if (second) d[$1] += n; else d[$1] -= n }
    END { for (k in d) if (d[k] > 0) print d[k], k }' | sort -rn | while read -r _ dev; do
    case $(dev_name "$dev") in zram* | loop* | "") continue ;; esac
    echo "$dev"
    break
  done)
  if [ -z "$dev" ]; then
    dev=$({
      echo "$b"
      echo --
      echo "$b2"
    } | awk '/^--$/ { second = 1; next } { if (second) d[$1] += $2; else d[$1] -= $2 } END { for (k in d) print d[k], k }' |
      sort -rn | while read -r _ name; do
      case $name in zram* | loop*) continue ;; esac
      [ -e "/sys/block/$name/dev" ] || continue
      cat "/sys/block/$name/dev"
      break
    done)
  fi
  [ -n "$dev" ] || return 1
  name=$(dev_name "$dev")
  busy=$({
    echo "$b"
    echo --
    echo "$b2"
  } | awk -v n="$name" '/^--$/ { second = 1; next } $1 == n { if (second) t += $2; else t -= $2 } END { printf "%d", t / 10 }')
  echo "$dev ${busy:-0}"
}

# The agent slice's io.max on one disk. Written again every round while a cap
# is on, because systemd puts its own value back on a daemon-reload.
declare -A level=() base=()
read -r -a steps <<<"$THROTTLE_STEPS"
apply_cap() { # dev
  local dev=$1 line
  if [ "${level[$dev]:-0}" -gt 0 ]; then
    line=${steps[$((level[$dev] - 1))]}
    line="rbps=${line%%:*} wbps=${line##*:}"
  else
    line=${base[$dev]}
  fi
  [ "$DRY_RUN" = 1 ] && return 0
  echo "$dev $line" >"$agents/io.max" 2>/dev/null
}
set_level() { # dev level [reason]
  local dev=$1 new=$2
  if [ -z "${base[$dev]:-}" ]; then
    base[$dev]=$(awk -v d="$dev" '$1 == d { for (i = 2; i <= NF; i++) if ($i ~ /^[rw]bps=/) printf "%s ", $i }' "$agents/io.max" 2>/dev/null)
    [ -n "${base[$dev]}" ] || base[$dev]="rbps=max wbps=max"
    [ "$DRY_RUN" = 1 ] || { mkdir -p "$STATE" && echo "${base[$dev]}" >"$STATE/base-$dev"; }
  fi
  level[$dev]=$new
  apply_cap "$dev"
  if [ "$new" = 0 ]; then
    echo "agents' disk cap on $(dev_name "$dev") lifted (back to ${base[$dev]% })"
    unset "base[$dev]" "level[$dev]"
    [ "$DRY_RUN" = 1 ] || rm -f "$STATE/base-$dev"
  else
    echo "agents capped on $(dev_name "$dev") at step $new of ${#steps[@]} (read:write ${steps[$((new - 1))]} bytes/s)${3:+: $3}"
  fi
}
# Caps a previous lag-guard left behind.
restore_caps() {
  local f dev
  for f in "$STATE"/base-*; do
    [ -e "$f" ] || continue
    dev=${f##*/base-}
    echo "$dev $(cat "$f")" >"$agents/io.max" 2>/dev/null
    echo "agents' disk cap on $(dev_name "$dev") from an earlier run lifted"
    rm -f "$f"
  done
}

io_bytes() { # pid -> read_bytes + write_bytes
  local k v s=0
  while read -r k v; do
    case $k in read_bytes: | write_bytes:) s=$((s + v)) ;; esac
  done 2>/dev/null <"/proc/$1/io"
  echo "$s"
}
cg_bytes() { # dev io.stat -> rbytes + wbytes on that disk
  awk -v d="$1" '$1 == d { for (i = 2; i <= NF; i++) { split($i, kv, "="); if (kv[1] == "rbytes" || kv[1] == "wbytes") n += kv[2] } } END { printf "%d\n", n }' "$2" 2>/dev/null
}

# The agent process doing the most IO in the cgroup doing the most IO on the
# stalled disk, over a second. Per-disk numbers exist per cgroup only
# (io.stat), so the cgroup is chosen by disk and the process inside it by its
# own IO. Falls back to the biggest by RSS when nothing did any.
stop_io_top() { # dev reason
  local dev=$1 reason=$2 f d pid pids n cg best=0 best_pid="" pbest=0 pbest_pid=""
  local -A cg0=() p0=()
  while read -r f; do
    d=${f%/io.stat}
    [ -n "$(head -c 1 "$d/cgroup.procs" 2>/dev/null)" ] || continue
    cg0[$d]=$(cg_bytes "$dev" "$f")
    mapfile -t pids 2>/dev/null <"$d/cgroup.procs"
    for pid in "${pids[@]}"; do p0[$pid]=$(io_bytes "$pid"); done
  done < <(find "$agents" -name io.stat -not -path '*/t3code-terminal-*' 2>/dev/null)
  sleep 1
  while read -r n cg; do
    [ "${n:-0}" -gt 0 ] || break
    mapfile -t pids 2>/dev/null <"$cg/cgroup.procs"
    for pid in "${pids[@]}"; do
      [ -n "${p0[$pid]:-}" ] || continue
      spared "$pid" && continue
      n=$(($(io_bytes "$pid") - p0[$pid]))
      [ "$n" -gt 0 ] || continue
      if prio "$pid"; then
        [ "$n" -gt "$pbest" ] && pbest=$n pbest_pid=$pid
      elif [ "$n" -gt "$best" ]; then
        best=$n best_pid=$pid
      fi
    done
    [ -n "$best_pid" ] && break
  done < <(for d in "${!cg0[@]}"; do echo "$(($(cg_bytes "$dev" "$d/io.stat") - cg0[$d])) $d"; done | sort -rn | head -n 5)
  if [ -n "$best_pid" ]; then
    stop "$best_pid" "$reason; it did the most disk IO on $(dev_name "$dev") ($((best / 1048576)) MB/s)"
  elif [ -n "$pbest_pid" ]; then
    stop "$pbest_pid" "$reason; it did the most disk IO on $(dev_name "$dev") ($((pbest / 1048576)) MB/s; priority job, but nothing else was using that disk)"
  else
    stop_biggest "$reason"
  fi
}

# Caps go back a step per RELAX samples without a real disk stall: calm ones,
# and stalls with an idle device (SUSTAIN samples each), which a cap cannot
# help. A stalled sample does not count; a stall on a busy device starts over.
relax() { # samples
  local dev
  calm=$((calm + $1))
  [ "$calm" -ge "$RELAX" ] || return 0
  calm=0 floor_hits=0
  for dev in "${!level[@]}"; do set_level "$dev" $((level[$dev] - 1)); done
}

streak=0 calm=0 floor_hits=0 erik_io=0 idle_logged=-100000
check_pressure() {
  local io mem pid uid reason dev busy
  io=$(full io)
  mem=$(full memory)
  erik_io=${io:-0}
  for dev in "${!level[@]}"; do apply_cap "$dev"; done
  if [ "${io:-0}" -gt "$IO_FULL" ] || [ "${mem:-0}" -gt "$MEM_FULL" ]; then
    streak=$((streak + 1))
  else
    streak=0
    relax 1
  fi
  [ "$streak" -ge "$SUSTAIN" ] || return 0
  streak=0
  reason="the pc was stalling (disk IO ${io}% / memory ${mem}% full)"
  # A stall on a disk nobody loads (swap-ins of Erik's own apps, or a wait
  # that is not this disk's): no cap and no kill makes it shorter. A memory
  # stall still stops the biggest job below.
  dev="" busy=0
  if [ "${io:-0}" -gt "$IO_FULL" ]; then
    read -r dev busy <<<"$(stalled_dev)"
    if [ -n "$dev" ] && [ "${busy:-0}" -lt "$DEV_BUSY" ]; then
      if [ $((SECONDS - idle_logged)) -ge 300 ]; then
        idle_logged=$SECONDS
        echo "disk IO stall ${io}% with $(dev_name "$dev") only ${busy}% busy: not the agents' disk load, nothing capped or stopped for it"
      fi
      relax "$SUSTAIN"
      [ "${mem:-0}" -gt "$MEM_FULL" ] || return 0
      io=0
    else
      calm=0
    fi
  fi
  # Local Nix builds (build users are not root).
  local nixpids
  mapfile -t nixpids < <(find "$nixd" -name cgroup.procs -exec cat {} + 2>/dev/null)
  for pid in "${nixpids[@]}"; do
    uid=$(awk '/^Uid:/ { print $2 }' "/proc/$pid/status" 2>/dev/null)
    [ "${uid:-0}" != 0 ] && stop "$pid" "$reason"
  done
  # A memory stall: RSS is what counts.
  if [ "${mem:-0}" -gt "$MEM_FULL" ]; then
    stop_biggest "$reason"
    [ "${io:-0}" -gt "$IO_FULL" ] || return 0
  fi
  # A disk stall: cap the agents on that disk; stop a job only at the floor.
  if [ -z "$dev" ]; then
    [ "${mem:-0}" -gt "$MEM_FULL" ] || stop_biggest "$reason"
    return 0
  fi
  if [ "${level[$dev]:-0}" -lt ${#steps[@]} ]; then
    floor_hits=0
    set_level "$dev" $((${level[$dev]:-0} + 1)) "$reason"
    return 0
  fi
  # At the floor. The memory rule above already stopped a job this round.
  [ "${mem:-0}" -gt "$MEM_FULL" ] && return 0
  floor_hits=$((floor_hits + 1))
  [ "$floor_hits" -ge "$FLOOR_SUSTAIN" ] || return 0
  floor_hits=0
  stop_io_top "$dev" "$reason with the agents' disk cap at its lowest"
}

# The agents themselves thrashing: their slice stalls on memory AND Erik's
# cgroups stall on disk (the agents page program code and file cache through
# the disk he shares). A slice stalled only on its memory cap while swapping
# into zram is harmless (measured: 20-28 % memory stall, 0 % IO), so that
# alone is left alone. Erik's own IO pressure, not /proc/pressure/io
# (2026-11-13): the system-wide figure counts the agents' waits on their own
# io.max cap, 83 % "full" with both disks under 10 % busy.
agent_streak=0
check_agent_thrash() {
  local mem io=$erik_io
  mem=$(awk '/^full/ { for (i = 1; i <= NF; i++) if ($i ~ /^avg10=/) { sub("avg10=", "", $i); printf "%d", $i } }' "$agents/memory.pressure" 2>/dev/null)
  if [ "${mem:-0}" -gt "$AGENT_MEM_FULL" ] && [ "${io:-0}" -gt "$AGENT_IO_FULL" ]; then
    agent_streak=$((agent_streak + 1))
  elif [ "$agent_streak" -gt 0 ]; then
    agent_streak=$((agent_streak - 1))
  fi
  [ "$agent_streak" -ge "$AGENT_SUSTAIN" ] || return 0
  agent_streak=0
  stop_biggest "the agents were thrashing the disk (agents' memory ${mem}% / Erik's disk IO ${io}% full-stalled); too big for the agent memory budget"
}

# Erik's memory.low protection breached (see the header): the sum of the
# "low" counts of his cgroups, rising SUSTAIN samples in a row.
low_prev="" low_streak=0
check_low() {
  local f k v total=0
  for f in "${erik[@]}"; do
    while read -r k v; do
      [ "$k" = low ] && total=$((total + v))
    done 2>/dev/null <"$f/memory.events"
  done
  if [ -n "$low_prev" ] && [ "$total" -gt "$low_prev" ]; then
    low_streak=$((low_streak + 1))
  else
    low_streak=0
  fi
  low_prev=$total
  [ "$low_streak" -ge "$SUSTAIN" ] || return 0
  low_streak=0
  stop_biggest "the pc was out of memory (the kernel was reclaiming the memory reserved for Erik's apps)"
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

restore_caps
echo "lag-guard: agents=$agents io>$IO_FULL% mem>$MEM_FULL% for $((SUSTAIN * INTERVAL))s (disk: only when the device is over $DEV_BUSY% busy; cap steps $THROTTLE_STEPS, back a step per $((RELAX * INTERVAL))s calm), agent thrash mem>$AGENT_MEM_FULL% io>$AGENT_IO_FULL% for $((AGENT_SUSTAIN * INTERVAL))s, memory.low breached for $((SUSTAIN * INTERVAL))s"
while true; do
  refresh_erik
  check_pressure
  check_agent_thrash
  check_low
  flush_notify
  sleep "$INTERVAL"
done
