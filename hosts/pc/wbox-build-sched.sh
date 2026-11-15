#!/usr/bin/env bash
# Build scheduler for the wasm-box agents, v28 (BOX lead, 2026-11-15; v26 2026-11-14 20:40).
#
# ONE admission rule (orchestrator 20:35, Erik: "the build rules keep being stupid
# and inexact"):
#
#   a waiting cargo is admitted when
#     MemAvailable - (the not-yet-used part of every admitted build's expected peak)
#       >= that cargo's own expected peak + MARGIN_MIB (1024)
#
#   - expected peak: the max RSS of its process tree on the last run of the same
#     lane and command (cwd + command line), recorded by this scheduler in PEAKS;
#     with no history, NOHIST_CHECK_MIB (2560) for check/clippy/test and
#     NOHIST_BUILD_MIB (4608) for anything else.
#   - the reserve term: an admitted build that has not reached its expected peak yet
#     will still take the difference, which MemAvailable does not show; without it,
#     three builds admitted in one pass at 9 GiB would all fit on paper and not in RAM.
#   - every PERIOD (5 s), in priority order, as many as fit (each admission takes its
#     peak off the budget for the rest of the pass).
#
# and ONE CPU term beside it (v28, orchestrator 2026-11-15 04:2x, after load 70-120 on 16
# threads and two rustc SIGTERMs):
#
#   the sum of the -j values of the running cargos, plus its own, is at most JOBS_MAX
#   (32, twice the threads)
#
#   - a cargo's -j: its -jN / -j N / --jobs N / --jobs=N, else CARGO_BUILD_JOBS in its
#     environment, else the thread count (cargo's own default); above JOBS_MAX it counts
#     as JOBS_MAX, so it runs when nothing else does.
#   - running cargos: the admitted ones, and those run regardless of admission (the world
#     rebuild, a cargo waiting on or holding the package-cache lock).
#
# Nothing else gates admission: no caps, no scope counts, no narrow/normal classes,
# no other -j rules, no freeze of admitted builds, no kill penalty, no BUILD-ONLY, no
# mutation hold. earlyoom (memory first, biggest process first, before the kernel)
# is the safety net; lag-guard runs as it is, on its own.
#
# Kept: the priority order (the shared builder and tests job first, then
# build-sched.prio); the package-cache lock rule (a cargo waiting on the lock is
# never held, and a held cargo holding it while others wait runs until it lets go);
# the world rebuild (R3_RE work trees) is never held; the quiet benchmark window
# (QUIET) and the no-admit flag (NOADMIT); the disk gate's hold (nothing is
# continued while /mnt/data is under 26 GB free, so this never fights disk-gate.sh);
# restart with the holds kept (build-sched-restart.sh, ADMIT_SEED).
# Held cargos are stopped at their compiler children only (hold_compile), never a
# test binary that is already running. An admitted build is never stopped again.
PERIOD=${PERIOD:-5}
MARGIN_MIB=${MARGIN_MIB:-1024}
NOHIST_CHECK_MIB=${NOHIST_CHECK_MIB:-2560}; NOHIST_BUILD_MIB=${NOHIST_BUILD_MIB:-4608}
PEAKS=${PEAKS:-/mnt/data/wbox-archive/build-sched.peaks.tsv}
NTHREADS=${NTHREADS:-$(nproc --all)}; JOBS_MAX=${JOBS_MAX:-$((2 * NTHREADS))}
jobs_of() { # $1 cargo pid: its -j, as cargo resolves it (flag, then CARGO_BUILD_JOBS, then the thread count)
  local a prev="" j="" e
  while IFS= read -r -d '' a; do
    case $a in
      -j[0-9]*) j=${a#-j} ;;
      --jobs=*) j=${a#--jobs=} ;;
      *) [[ $prev == -j || $prev == --jobs ]] && [[ $a =~ ^[0-9]+$ ]] && j=$a ;;
    esac
    prev=$a
  done < "/proc/$1/cmdline" 2>/dev/null
  if ! [[ $j =~ ^[0-9]+$ ]] || [ "$j" -lt 1 ]; then
    e=$({ tr '\0' '\n' < "/proc/$1/environ"; } 2>/dev/null | sed -n 's/^CARGO_BUILD_JOBS=//p' | head -1)
    [[ $e =~ ^[0-9]+$ ]] && [ "$e" -ge 1 ] && j=$e || j=$NTHREADS
  fi
  [ "$j" -gt "$JOBS_MAX" ] && j=$JOBS_MAX
  echo "$j"
}
SLICE=${SLICE:-/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/app.slice/app-t3code.slice}
SCOPE=${SCOPE:-'wasm-box|/mnt/data/wbox-'}
LOG=${LOG:-/mnt/data/wbox-archive/build-sched.log}
say() { echo "$(date +%F\ %T) $*" >> "$LOG"; }
start_of() { local s; s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1; s=${s##*) }; set -- $s; echo "${20}"; }
state_of() { local s; s=$(cat "/proc/$1/stat" 2>/dev/null) || return 1; s=${s##*) }; echo "${s%% *}"; }
ours() { local c; c="$(readlink "/proc/$1/cwd" 2>/dev/null) $({ tr '\0' ' ' < "/proc/$1/cmdline"; } 2>/dev/null | cut -c1-1500)"; [[ $c =~ $SCOPE ]]; }
tree() { local c; echo "$1"; for c in $(pgrep -P "$1" 2>/dev/null); do tree "$c"; done; }
sig() {
  # Every continuation, including shutdown cleanup, obeys both disk gates.
  # Otherwise this scheduler fights their SIGSTOP and invalidates timed tests.
  [ "$1" = CONT ] && disk_low && return 0
  local q; for q in $(tree "$2"); do kill "-$1" "$q" 2>/dev/null; done
}
any_stopped() { # $1 pid: it or any descendant is stopped (T). A held cargo has its compiler children
  # stopped too (hold_compile); if the cargo was continued by anything else, or admitted while only
  # its children were stopped, they stayed stopped for good (CONF-IPC, 2026-11-14: a cargo frozen
  # for over an hour, listed neither running nor waiting)
  # Only the cargo and the compiler children hold_compile stops count: a test binary that stops its
  # own child on purpose (job-control and ptrace tests) is never continued by this.
  local q c; [ "$(state_of "$1")" = T ] && return 0
  for q in $(tree "$1"); do [ "$(state_of "$q")" = T ] || continue; c=$(cat "/proc/$q/comm" 2>/dev/null)
    [[ $c =~ ^(rustc|cc|c\+\+|cc1|cc1plus|clang|clang\+\+|ld|ld\.lld|ld\.bfd|mold|lld|as|build-script-b.*)$ ]] && return 0; done; return 1
}
hold_compile() { # $1 cargo pid: stop the cargo and its compiler children only, never a test binary or
  # other program it has already started (JS-L1, 2026-11-14: a held `cargo test` with nothing to
  # recompile had its running timing tests frozen for 10-30 minutes)
  local q c; kill -STOP "$1" 2>/dev/null
  for q in $(tree "$1"); do [ "$q" = "$1" ] && continue; c=$(cat "/proc/$q/comm" 2>/dev/null)
    [[ $c =~ ^(rustc|cc|c\+\+|cc1|cc1plus|clang|clang\+\+|ld|ld\.lld|ld\.bfd|mold|lld|as|build-script-b.*)$ ]] && kill -STOP "$q" 2>/dev/null; done
}
PRIO_FILE=${PRIO_FILE:-/mnt/data/wbox-archive/build-sched.prio}
# Rank by what a job unblocks (orchestrator 2026-11-14 20:40, v27). PRIO_FILE lines are substrings of a
# cargo's cwd, in rank order; "@builder" is where cargos with AGENT_JOB_PRIO=1 rank; unlisted cargos
# rank LOW_RANK-1 (1000); lines after "@after-landing", and every mutation run, rank LOW_RANK (2000)
# and above, and none of those is admitted while a cargo ranked above them is held for memory.
LOW_RANK=${LOW_RANK:-2000}
is_mutation() { local c; c="$(readlink "/proc/$1/cwd" 2>/dev/null) $(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)"; [[ $c =~ (/w-mut|mutation|mutants|MUT_RUNS) ]]; }
prio_rank() { # $1 pid  $2 1 if it carries AGENT_JOB_PRIO
  local c l i=0 low=0 envp=${2:-0}
  if is_mutation "$1"; then echo "$LOW_RANK"; return; fi
  [ -s "$PRIO_FILE" ] || { [ "$envp" = 1 ] && echo 0 || echo 1000; return; }
  c=$(readlink "/proc/$1/cwd" 2>/dev/null) || { echo 1000; return; }
  while read -r l; do
    [ -n "$l" ] && [[ $l != \#* ]] || continue
    if [ "$l" = "@after-landing" ]; then low=1; i=0; continue; fi
    i=$((i+1))
    if [ "$l" = "@builder" ]; then [ "$envp" = 1 ] && { echo "$i"; return; }; continue; fi
    [[ $c == *"$l"* ]] && { [ "$low" = 1 ] && echo $((LOW_RANK + i)) || echo "$i"; return; }
  done < "$PRIO_FILE"
  [ "$envp" = 1 ] && echo 0 || echo 1000
}
roots() { # "starttime pid" of every in-scope cargo, in rank order, oldest first within a rank
  local p st e
  for p in $(pgrep -x 'cargo|\.cargo-wrapped'); do
    ours "$p" || continue; st=$(start_of "$p") || continue
    e=0; { tr "\0" "\n" < "/proc/$p/environ"; } 2>/dev/null | grep -qxE "(WBOX_BUILD_PRIO|AGENT_JOB_PRIO)=1" && e=1
    echo "$(prio_rank "$p" "$e") $st $p"
  done | sort -n -k1,1 -k2,2
}
# Cargo's package-cache lock (~/.cargo/.package-cache-mutate, flock): every cargo holds it
# SHARED for its whole build, and a download or `cargo update` needs it EXCLUSIVE. A stopped
# reader therefore blocks every writer (2026-11-13, CONF-MM). From /proc/locks (waiters are
# the "->" lines): a cargo blocked on the lock is never held, and while any cargo waits on
# it, no holder is held.
LOCKF=${LOCKF:-$HOME/.cargo/.package-cache-mutate $HOME/.cargo/.package-cache}
lock_scan() { # sets LK_HOLD and LK_WAIT: " pid pid ... "
  local ino="" f; for f in $LOCKF; do [ -e "$f" ] && ino="$ino|$(stat -c %i "$f")"; done
  LK_HOLD=" "; LK_WAIT=" "
  [ -n "$ino" ] || return 0
  while read -r l; do
    if [[ $l == *"->"* ]]; then LK_WAIT="$LK_WAIT$(awk '{print $6}' <<<"$l") "
    else LK_HOLD="$LK_HOLD$(awk '{print $5}' <<<"$l") "; fi
  done < <(grep -E ":(${ino#|}) " /proc/locks 2>/dev/null)
}
gate_holds() {
  local ledger=$1 log=$2 state
  [ -r "$ledger" ] && [ -r "$log" ] || return 0
  [ -s "$ledger" ] && return 0
  # A gate can freeze when there are no matching processes, leaving an empty
  # ledger. Its last transition still owns the hysteresis band. Unknown or
  # partially written state fails closed until the next scheduler pass.
  state=$(tail -n 1 "$log") || return 0
  case "$state" in
    *' RESUME at '* | *'gate started:'*'state run '*) return 1 ;;
    *) return 0 ;;
  esac
}
disk_low() {
  # The ledgers are owned by disk-gate.sh. Only that gate clears them after
  # its HIGH watermark (root 320 GiB, data 32 GiB); never clear or thaw here.
  # Checking LOW alone would admit builds in the hysteresis band, or before
  # the gate has performed its natural resume. Stale entries fail closed.
  local root_free data_free
  gate_holds "${ROOT_GATE_STOPPED:-/mnt/data/wbox-archive/disk-gate-root.stopped}" "${ROOT_GATE_LOG:-/mnt/data/wbox-archive/disk-gate-root.log}" && return 0
  gate_holds "${DATA_GATE_STOPPED:-/mnt/data/wbox-archive/disk-gate.stopped}" "${DATA_GATE_LOG:-/mnt/data/wbox-archive/disk-gate.log}" && return 0
  root_free=$(df --output=avail -BG / 2>/dev/null | tail -1 | tr -dc 0-9)
  data_free=$(df --output=avail -BG /mnt/data 2>/dev/null | tail -1 | tr -dc 0-9)
  # Missing/unreadable filesystem measurements cannot grant admission.
  [[ $root_free =~ ^[0-9]+$ && $data_free =~ ^[0-9]+$ ]] || return 0
  [ "$root_free" -lt 300 ] || [ "$data_free" -lt 26 ]
}
avail_mib() { awk '/^MemAvailable:/ {print int($2 / 1024)}' /proc/meminfo; }
tree_rss_mib() { # $1 pid: RSS of it and its descendants, MiB
  local p=$1 s c r
  r=$(awk '/^VmRSS:/ {print int($2 / 1024)}' "/proc/$p/status" 2>/dev/null); s=${r:-0}
  for c in $(pgrep -P "$p" 2>/dev/null); do s=$((s + $(tree_rss_mib "$c"))); done
  echo "$s"
}
R3_RE=${R3_RE:-'^/mnt/data/wbox-r3/pkgs/work/'}
is_r3() { [[ $(readlink "/proc/$1/cwd" 2>/dev/null) =~ $R3_RE ]]; }
# --- expected peaks --------------------------------------------------------------
# key: the lane (cwd) and the command (cmdline, NULs as spaces, tabs and newlines out)
key_of() { printf '%s|%s' "$(readlink "/proc/$1/cwd" 2>/dev/null)" "$(tr '\0\t\n' '   ' < "/proc/$1/cmdline" 2>/dev/null | sed 's/ *$//')"; }
declare -A PEAK_OF   # key -> MiB, from PEAKS (last run wins)
load_peaks() { [ -s "$PEAKS" ] || return 0; while IFS=$'\t' read -r k m _; do [ -n "$k" ] && [[ $m =~ ^[0-9]+$ ]] && PEAK_OF[$k]=$m; done < "$PEAKS"; }
nohist_mib() { # $1 pid: the default by subcommand
  local c; c=$(tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null)
  if [[ " $c " =~ \ (check|clippy|test|t|c)\  ]]; then echo "$NOHIST_CHECK_MIB"; else echo "$NOHIST_BUILD_MIB"; fi
}
expected_mib() { # $1 pid, $2 key
  local m=${PEAK_OF[$2]:-}; [ -n "$m" ] && { echo "$m"; return; }; nohist_mib "$1"
}
declare -A ADMITTED KEY EXP MAXSEEN   # pid -> 1, key, expected peak at admission, max tree RSS seen
record_peak() { # $1 pid that ended: write its measured peak as the lane+command's history
  local k=${KEY[$1]:-} m=${MAXSEEN[$1]:-0}
  [ -n "$k" ] && [ "$m" -gt 0 ] || return 0
  PEAK_OF[$k]=$m; printf '%s\t%s\t%s\n' "$k" "$m" "$(date +%F\ %T)" >> "$PEAKS"
}
# --- restart with the holds kept -------------------------------------------------
cleanup() {
  if [ -e "${RESTART_FLAG:-/mnt/data/wbox-archive/build-sched.restart}" ]; then
    rm -f "${RESTART_FLAG:-/mnt/data/wbox-archive/build-sched.restart}"
    [ -n "${ADMIT_SEED:-}" ] && printf '%s\n' "${!ADMITTED[@]}" > "$ADMIT_SEED"
    say "scheduler stopped for a restart: held builds stay held"; exit 0
  fi
  roots | while read -r _ st p; do sig CONT "$p"; done; say "scheduler stopped: all builds continued"; exit 0
}
# Isolated fixture tests source the functions without locks, signals or a loop.
[[ ${BUILD_SCHED_SOURCE_ONLY:-0} = 1 ]] && return 0
trap cleanup TERM INT
# One scheduler only: it is a daemon, not a wrapper; a second copy exits at once.
exec 8>>"${LOCKFILE:-/mnt/data/wbox-archive/build-sched.lock}"
flock -n 8 || { echo "build-sched: already running (it is the scheduler daemon, not a command wrapper; cargo runs are scheduled automatically)" >&2; exit 3; }
load_peaks
say "scheduler started (v28, ranked by what a job unblocks; after-landing runs wait while a higher rank is held): admit a waiting cargo when MemAvailable minus the unused part of the admitted builds' expected peaks >= its own expected peak + ${MARGIN_MIB} MiB; expected peak = its lane+command's last measured tree RSS peak (${#PEAK_OF[@]} known), else ${NOHIST_CHECK_MIB} MiB check/clippy/test, ${NOHIST_BUILD_MIB} MiB build; and the running cargos' -j sum plus its own <= ${JOBS_MAX} (twice the ${NTHREADS} threads); every ${PERIOD} s, in priority order, as many as fit; nothing else gates"
if [ -s "${ADMIT_SEED:-}" ]; then while read -r q; do [ -n "$q" ] && [ -d "/proc/$q" ] && ADMITTED[$q]=1; done < "$ADMIT_SEED"
else while read -r _ _ q; do [ -n "$q" ] && [ "$(state_of "$q")" != T ] && ADMITTED[$q]=1; done < <(roots); fi
for q in "${!ADMITTED[@]}"; do KEY[$q]=$(key_of "$q"); EXP[$q]=$(expected_mib "$q" "${KEY[$q]}"); MAXSEEN[$q]=0; done
last=""
while :; do
  # the quiet benchmark window (quiet.sh): admit nothing, continue nothing; quiet.sh thaws
  if [ -f /mnt/data/wbox-archive/QUIET ]; then
    [ "${quiet:-0}" = 1 ] || { say "quiet window: nothing admitted or continued until it ends"; quiet=1; }
    bash /mnt/data/wbox-archive/quiet.sh sweep >/dev/null 2>&1
    sleep "$PERIOD"; continue
  fi
  [ "${quiet:-0}" = 1 ] && { say "quiet window over: scheduling again"; quiet=0; }
  if disk_low; then dl=1; else dl=0; fi
  if [ "$dl" != "${last_dl:-0}" ]; then
    if [ "$dl" = 1 ]; then say "disk gate hold: root/data reserve or stopped ledger; nothing is admitted or continued"
    else say "disk ok again: /mnt/data $(df -BG --output=avail /mnt/data | tail -1 | tr -dc 0-9) GB free"; fi
    last_dl=$dl
  fi
  # no-admit window for a headline run (NOADMIT; clears itself when its run dir has DONE or INVALID)
  NOADMIT_F=${NOADMIT_F:-/mnt/data/wbox-archive/NOADMIT}; noadmit=0
  if [ -f "$NOADMIT_F" ]; then
    nd=$(head -1 "$NOADMIT_F")
    if [ -n "$nd" ] && { [ -e "$nd/DONE" ] || [ -e "$nd/INVALID" ]; }; then rm -f "$NOADMIT_F"; say "no-admit window over: $nd ended"
    else noadmit=1; fi
  fi
  # measure the admitted builds: max tree RSS so far, and the reserve (expected peak not yet used)
  reserve=0
  for q in "${!ADMITTED[@]}"; do
    if [ ! -d "/proc/$q" ]; then record_peak "$q"; unset "ADMITTED[$q]" "KEY[$q]" "EXP[$q]" "MAXSEEN[$q]"; continue; fi
    is_r3 "$q" && continue
    t=$(tree_rss_mib "$q"); [ "$t" -gt "${MAXSEEN[$q]:-0}" ] && MAXSEEN[$q]=$t
    [ "$t" -lt "${EXP[$q]:-0}" ] && reserve=$((reserve + ${EXP[$q]} - t))
  done
  mam=$(avail_mib); budget=$((mam - reserve))
  mapfile -t R < <(roots)
  lock_scan
  run=""; held=""; nrun=0; hi_held=0
  # the CPU term: -j of everything that runs regardless of this pass's admissions
  jsum=0
  for e in "${R[@]}"; do
    p=${e##* }; [ -n "$p" ] || continue
    if [ -n "${ADMITTED[$p]:-}" ] || is_r3 "$p" || [[ $LK_WAIT == *" $p "* ]] || { [ "$LK_WAIT" != " " ] && [[ $LK_HOLD == *" $p "* ]]; }; then
      jsum=$((jsum + $(jobs_of "$p")))
    fi
  done
  for e in "${R[@]}"; do
    p=${e##* }; rk=${e%% *}; [ -n "$p" ] || continue
    if is_r3 "$p"; then [ "$(state_of "$p")" = T ] && ! disk_low && sig CONT "$p"; run="$run $p(r3)"; continue; fi
    if [[ $LK_WAIT == *" $p "* ]]; then [ "$(state_of "$p")" = T ] && ! disk_low && sig CONT "$p"; run="$run $p(lockwait)"; continue; fi
    if [ -n "${ADMITTED[$p]:-}" ]; then any_stopped "$p" && ! disk_low && sig CONT "$p"; run="$run $p"; nrun=$((nrun+1)); continue; fi
    k=$(key_of "$p"); x=$(expected_mib "$p" "$k"); need=$((x + MARGIN_MIB)); jp=$(jobs_of "$p")
    lowblock=0; [ "$rk" -ge "$LOW_RANK" ] && [ "$hi_held" = 1 ] && lowblock=1
    if [ "$noadmit" = 0 ] && [ "$lowblock" = 0 ] && ! disk_low && [ "$budget" -ge "$need" ] && [ $((jsum + jp)) -le "$JOBS_MAX" ]; then
      ADMITTED[$p]=1; KEY[$p]=$k; EXP[$p]=$x; MAXSEEN[$p]=0; budget=$((budget - x)); nrun=$((nrun+1)); jsum=$((jsum + jp))
      say "admitted $p ($(readlink "/proc/$p/cwd" 2>/dev/null)): expected peak $x MiB$([ -n "${PEAK_OF[$k]:-}" ] && echo ' (last run)' || echo ' (no history)'), MemAvailable $mam MiB, reserved for admitted builds $reserve MiB; -j $jp, running -j now $jsum of $JOBS_MAX"
      any_stopped "$p" && sig CONT "$p"
      run="$run $p(new)"
    elif [ "$LK_WAIT" != " " ] && [[ $LK_HOLD == *" $p "* ]]; then
      [ "$(state_of "$p")" = T ] && ! disk_low && sig CONT "$p"; run="$run $p(lockheld)"
    else
      [ "$(state_of "$p")" = T ] || hold_compile "$p"; held="$held $p:$need"; [ "$rk" -lt "$LOW_RANK" ] && hi_held=1; [ "$lowblock" = 1 ] && held="${held% *} $p:L"
      [ "$lowblock" = 0 ] && [ "$budget" -ge "$need" ] && [ $((jsum + jp)) -gt "$JOBS_MAX" ] && held="${held% *} $p:J$jp"
    fi
  done
  # who is held and why, for quiet.sh status and for workers
  { for h in $held; do q=${h%%:*}; n=${h#*:}
      if [ "$noadmit" = 1 ]; then echo "$q held: no-admit window for a headline run (until ${nd:-?} writes DONE or INVALID)"
      elif disk_low; then echo "$q held: root/data disk gate reserve or stopped ledger"
      elif [[ $n == J* ]]; then echo "$q held: its -j ${n#J} would take the running cargos' -j sum ($jsum) over $JOBS_MAX (twice the $NTHREADS threads); admitted in priority order as soon as it fits"
      elif [ "$n" = L ]; then echo "$q held: an after-landing run (mutation, tests job or suite) waits while any landing-gate, wall or builder cargo waits for memory (rank rule, orchestrator 2026-11-14 20:40)"
      else echo "$q held: needs $n MiB (its expected peak + ${MARGIN_MIB}); free for new builds now $budget MiB (MemAvailable $mam minus $reserve reserved for admitted builds); admitted in priority order as soon as it fits"; fi
    done; true; } > /mnt/data/wbox-archive/build-sched.held.new 2>/dev/null && mv /mnt/data/wbox-archive/build-sched.held.new /mnt/data/wbox-archive/build-sched.held
  st="running:$run | waiting:$(for h in $held; do printf ' %s' "${h%%:*}"; done)"
  [ "$st" != "$last" ] && { say "$st (available $mam MiB, reserved $reserve MiB)"; last=$st; }
  # the stale-binary alarm (stale-alarm.sh), every 60 periods (5 min), in the background
  tick=$((${tick:-0} + 1)); [ $((tick % 60)) = 1 ] && { bash /mnt/data/wbox-archive/stale-alarm.sh >/dev/null 2>&1 & }
  sleep "$PERIOD"
done
