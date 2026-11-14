# nix, as agents see it (shadows the real one on PATH). Everything runs here
# on the pc: small builds and evals are quick on this CPU. Evaluating a whole
# NixOS or Home Manager configuration takes 3-4 GB and about two minutes, so
# those wait for each other under one lock (several at once is what froze the
# pc on 2026-10-21). For a job that will take ~10+ minutes, use nix-remote or
# heavy instead. Outside the agent slice, and in Erik's T3 terminals, it is
# the real nix with no lock.
real=@realNix@
lock=${XDG_RUNTIME_DIR:-/tmp}/nixos-eval.lock

case "$(cat /proc/self/cgroup 2>/dev/null)" in
  */t3code-terminal-*) exec "$real" "$@" ;;
  */app-t3code.slice/*) ;;
  *) exec "$real" "$@" ;;
esac

case " $* " in
  *nixosConfigurations* | *homeConfigurations*) ;;
  *) exec "$real" "$@" ;;
esac
case " $* " in
  *" --store "* | *" --store="*) exec "$real" "$@" ;;
esac

exec 9>"$lock"
if ! @flock@ -n 9; then
  echo "nix (agent guard): another system evaluation is running on this pc; waiting for it (one at a time)" >&2
  @flock@ 9
fi

# And only with room for it. On 2026-11-14 17:53 an evaluation reached 2.9 GB
# with 3.5 GB available while a Gradle daemon and a cargo build of other
# projects grew, and the kernel OOM killer fired machine-wide. Under 5 GB
# available it waits (holding the lock, so the next one queues behind it);
# after 20 minutes it gives up and says to evaluate on the homelab.
avail() {
  local k v _
  while read -r k v _; do
    if [ "$k" = MemAvailable: ]; then
      echo $((v / 1024))
      return
    fi
  done </proc/meminfo
}
need=${AGENT_NIX_MIN_AVAIL_MB:-5120} waited=0
while [ "$(avail)" -lt "$need" ]; do
  if [ "$waited" = 0 ]; then
    echo "nix (agent guard): only $(avail) MB of memory available, a system evaluation needs about 4 GB; waiting for $need MB (up to 20 minutes)" >&2
  fi
  if [ "$waited" -ge 1200 ]; then
    echo "nix (agent guard): the pc stayed short of memory for 20 minutes; evaluate on the homelab instead: nix-remote build ... or rebuild --remote" >&2
    exit 75
  fi
  sleep 10
  waited=$((waited + 10))
done
exec "$real" "$@"
