#!/usr/bin/env bash
# No live processes or gate state: df, process traversal and kill are fixtures.
set -euo pipefail
cd "$(dirname "$0")"
fixture=$(mktemp -d .disk-gate-test.XXXXXX)
trap 'rm -rf "$fixture"' EXIT
export ROOT_GATE_STOPPED="$fixture/root.stopped"
export DATA_GATE_STOPPED="$fixture/data.stopped"
touch "$ROOT_GATE_STOPPED" "$DATA_GATE_STOPPED"
BUILD_SCHED_SOURCE_ONLY=1 source ./wbox-build-sched.sh
mock_root=330 mock_data=40
df() {
  printf 'Avail\n'
  case "${*: -1}" in
    /) printf '%sG\n' "$mock_root" ;;
    /mnt/data) printf '%sG\n' "$mock_data" ;;
    *) return 1 ;;
  esac
}
tree() { echo 12345; }
kill() { printf '%s\n' "$*" >> "$fixture/signals"; }
roots() { echo '0 1 12345'; }
say() { :; }

! disk_low
mock_root=299; disk_low
mock_root=310
echo '12345 1' > "$ROOT_GATE_STOPPED"; disk_low
sig CONT 12345
test ! -e "$fixture/signals"
# Even above HIGH the scheduler waits for the gate to clear its own ledger.
mock_root=330; disk_low
sig CONT 12345
test ! -e "$fixture/signals"
# Shutdown cleanup must not thaw a gate-owned hold either.
( RESTART_FLAG="$fixture/no-restart"; cleanup )
test ! -e "$fixture/signals"
: > "$ROOT_GATE_STOPPED"
! disk_low
sig CONT 12345
test "$(cat "$fixture/signals")" = '-CONT 12345'
mock_data=25; disk_low
mock_data=30
echo '12345 1' > "$DATA_GATE_STOPPED"; disk_low
mock_data=40; disk_low
: > "$DATA_GATE_STOPPED"
! disk_low
mock_root=unavailable; disk_low
echo 'PASS: root/data low watermarks, both held ledgers, natural release, fail-closed measurement, continuation and cleanup guards'
