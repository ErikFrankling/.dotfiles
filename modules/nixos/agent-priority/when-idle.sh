# when-idle <cmd...>: wait until Erik has been away from the pc for 10
# minutes, then run cmd on the pc. If he comes back while it runs, lag-guard
# pauses it (SIGSTOP) and resumes it at his next idle window, so expect
# gaps. Prefer the homelab (heavy) for anything that can run there.
if [ $# -eq 0 ]; then
  echo "usage: when-idle <cmd...>" >&2
  exit 2
fi
if ! pc-idle >/dev/null; then
  echo "when-idle: waiting until Erik is away from the pc (check: pc-idle)" >&2
  until pc-idle >/dev/null; do sleep 15; done
fi
# lag-guard pauses (never kills) every process carrying this when Erik is back.
export WHEN_IDLE_JOB=1
echo "when-idle: Erik is idle, starting: $*" >&2
exec "$@"
