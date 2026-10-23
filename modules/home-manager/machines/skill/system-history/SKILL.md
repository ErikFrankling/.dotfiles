---
name: system-history
description: What ran on Erik's pc or framework laptop at a past time, and how much RAM, CPU, swap and disk each program, unit and T3 agent thread used. A task manager you can scroll back. Load whenever Erik reports lag, a freeze, a spike, high RAM or a hard reboot ("who was spiking", "what filled memory", "why was it slow at 01:20"), or asks what a thread, build or test run cost. Do not answer from `top` now; look at the time it happened.
---

# System history: top, but for the past

Two recorders run on the pc and the framework (dotfiles
`modules/nixos/observability`). Both are always on; nothing decides when to
record.

| | below (local) | Process metrics (homelab Prometheus) |
|---|---|---|
| Resolution | 5 s, every process and every cgroup | 30 s, per (program, unit) |
| Kept | ~1 week (12 GiB cap), `/var/log/below` | 400 days (Prometheus 25 GB cap) |
| Has | pid, cmdline, RSS, swap, CPU, IO, cgroup memory and PSI | PSS, RSS, swap, CPU, disk IO, process count |
| Use for | exact commands and pids, a cgroup tree, the minutes before a freeze | long ranges, trends, the Grafana dashboard, the laptop from the pc |

Both survive a hard reboot (below writes to disk every 5 s; Alloy queues on
disk). Data starts 2026-10-23 02:10 on the pc; before that only host totals
exist (`node_memory_*`).

## 1. Look first: the dashboard

Grafana **Processes (history)**:
`https://grafana.erikfrankling.duckdns.org/d/processes` (LAN/tailnet, no login).
Pick host, zoom into the spike; "Top in the selected time range" ranks peak RAM,
average CPU and disk traffic per program and unit for exactly that window.
Filters: cgroup regex (e.g. `.*/app-t3code\.slice/.*` = agents only) and
program regex.

## 2. Prometheus queries (any machine, no auth)

```bash
P=https://prometheus.erikfrankling.duckdns.org/api/v1/query
q() { curl -s "$P" --data-urlencode "query=$1" --data-urlencode "time=${2:-$(date +%s)}" \
  | jq -r '.data.result[] | "\(.value[1]|tonumber*100|round/100)\t\(.metric.groupname)\t\(.metric.unit)"'; }
END=$(date -d '2026-10-23 01:35' +%s)   # end of the window, local time

# Peak RAM (PSS, GB) per program+unit in the 10 minutes before END
q 'topk(15, max_over_time(sum by (groupname, unit) (namedprocess_namegroup_memory_bytes{host_name="pc",memtype="proportionalResident"})[10m:30s]) / 1e9)' $END
# Average CPU (cores) over those 10 minutes
q 'topk(15, sum by (groupname, unit) (increase(namedprocess_namegroup_cpu_seconds_total{host_name="pc"}[10m])) / 600)' $END
# Disk read+write (GB) over those 10 minutes
q 'topk(10, sum by (groupname, unit) (increase(namedprocess_namegroup_read_bytes_total{host_name="pc"}[10m]) + increase(namedprocess_namegroup_write_bytes_total{host_name="pc"}[10m])) / 1e9)' $END
# Swap (GB) per program at END
q 'topk(10, sum by (groupname, unit) (namedprocess_namegroup_memory_bytes{host_name="pc",memtype="swapped"}) / 1e9)' $END
# Peak RAM per T3 agent thread scope (sum of its processes)
q 'topk(10, max_over_time(sum by (unit) (namedprocess_namegroup_memory_bytes{host_name="pc",memtype="proportionalResident",cgroup=~".*/app-t3code\\.slice/.*"})[10m:30s]) / 1e9)' $END
```

- Labels: `host_name` (pc, framework), `groupname` (the process' comm, 15
  chars: `.zen-beta-wrapp`, `cc1plus`, `node-MainThread`, `tsc`), `unit`
  (last cgroup component: `t3code-claude-85ad4cc5.scope`, `erikshell.service`,
  `session-2.scope`), `cgroup` (full path). `memtype`: `proportionalResident`
  (PSS: shared pages split fairly, use this for RAM), `resident`, `swapped`.
- Host context: `node_memory_MemAvailable_bytes`, `node_memory_SwapFree_bytes`,
  `node_memory_AnonPages_bytes`, `node_memory_Shmem_bytes` (tmpfs),
  `rate(node_vmstat_pswpout[2m])`, `rate(node_pressure_memory_waiting_seconds_total[2m])`
  (60 s resolution, `host_name="pc"`).
- Over a range for a graph: `query_range` with `start`, `end`, `step=60`.

## 3. below (on the machine itself, 5 s, exact processes)

Times are local and accept "10 min ago", "01:20", "2026-10-23 01:20:00".

```bash
# Top 10 processes by RSS at each 5 s sample from 01:25 to 01:26
below dump process -b "2026-10-23 01:25" -e "2026-10-23 01:26" \
  -s mem.rss_bytes --rsort --top 10 \
  -f datetime pid comm mem.rss_bytes mem.swap cpu.usage_pct cgroup cmdline -O csv
# Top by CPU instead: -s cpu.usage_pct ; by disk: -s io.rwbytes_per_sec
# Only one program: -s comm -F 'cc1plus|clang.*'
# Cgroups (slices, services, T3 thread scopes) with memory, swap and pressure
below dump cgroup -b "01:25" -e "01:25:05" -s full_path -F '.*t3code-.*' \
  -f datetime full_path mem.total mem.swap cpu.usage_pct pressure.memory_full_pct -O csv
# Machine totals: below dump system -b ... -e ... -O csv
# JSON for scripts: -O json
```

Interactive scroll-back for Erik (or a screenshot): `below replay -t "01:20"`
(`t`/`T` step forward/back in time, `c`/`p` cgroup/process view, `s`/`S` sort,
`/` filter, `q` quit). Live view: `below live`. The laptop: `ssh framework
below dump ...`.

## 4. Which T3 thread was that scope?

T3 Code starts every agent session in `t3code-<provider>-<8 hex>.scope` and
logs one line per scope (fork, apps/server/src/process/agentScope.ts):
`Agent scope started: t3code-claude-85ad4cc5.scope thread=mcp:cb249734-...`.

```bash
journalctl --user -u t3code -o cat -g 't3code-claude-85ad4cc5.scope'          # this boot
journalctl --user -u t3code -b -1 -o cat -g 'Agent scope started'              # last boot
# From anywhere, Loki through Grafana:
curl -s -G https://grafana.erikfrankling.duckdns.org/api/datasources/proxy/uid/loki/loki/api/v1/query_range \
  --data-urlencode 'query={service_name="t3code",host_name="pc"} |= "t3code-claude-85ad4cc5.scope"' \
  --data-urlencode "start=$(date -d '-2 days' +%s)000000000" | jq -r '.data.result[].values[][1]'
```

Then the title: `t3_thread_read` with that thread id, or read-only from the
DB: `sqlite3 "file:$HOME/.t3/userdata/statev2.sqlite?mode=ro" "select title from
orchestration_v2_projection_threads where thread_id='mcp:cb249734-...'"`
(sqlite3 is not on PATH: `ls -d /nix/store/*-sqlite-*-bin/bin/sqlite3`).
Scopes older than the log line (before 2026-10-23 ~04:00), or to double
check: the claude `--session-id`/`--resume` uuid in the scope's command line
(below keeps it) maps to the thread:

```bash
U=t3code-claude-4f687ef0 T="2026-10-23 02:45"
SID=$(below dump process -b "$T" -e "$T:05" -f cgroup cmdline -O csv | grep "$U" \
  | grep -oE -- '--(session-id|resume)[= ][0-9a-f-]{36}' | grep -oE '[0-9a-f-]{36}' | head -1)
[ -n "$SID" ] && sqlite3 "file:$HOME/.t3/userdata/statev2.sqlite?mode=ro" \
  "select p.thread_id, t.title from orchestration_v2_projection_provider_threads p
   left join orchestration_v2_projection_threads t using(thread_id)
   where p.payload_json like '%$SID%' limit 1"
```

Never run the lookup with an empty `$SID` (`like '%%'` matches any thread). Codex runs one
shared app-server scope for several threads; the line names the thread that
started it.

## 5. How to answer "what was spiking"

1. Get the time from Erik or the evidence (journal `lag-guard:` lines, the
   last journal line of `journalctl -b -1`, a PSI or swap jump in Prometheus).
2. Rank the window around it (Prometheus peak RAM/CPU, then below for exact
   pids and command lines). Compare with an hour earlier: what grew?
3. Attribute: program, unit, T3 thread (section 4), and what that thread was
   doing then (its messages around that time).
4. Say whether it is optimizable (a test suite at full parallelism, a 4 GB
   `tsc`, a duplicate dev server, a forgotten emulator) and what to change.
   Builds on the pc are expected; long ones belong on `heavy` (machines skill).

Pitfalls: `systemctl ... "Consumed ... memory peak"` journal lines give a
unit's peak only when it ends. RSS double counts shared browser memory: use
PSS. Kernel threads are not in the process metrics (host totals cover them).
`below dump` errors "No samples found" outside the retention window.
