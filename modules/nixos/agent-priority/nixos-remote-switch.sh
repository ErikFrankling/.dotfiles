# nixos-remote-switch [switch|boot|test|build|dry-build] [flake-dir]
#
# What `rebuild` does on the pc: evaluate and build this host's system, show
# what changed, then activate it. The evaluation runs here by default (about
# 2 minutes on this CPU, one at a time under a lock); anything not in a cache
# is built on the homelab builder anyway (nix.buildMachines).
# NIXOS_SWITCH_REMOTE=1 (`rebuild --remote`) evaluates and builds on the
# builder instead (nix-remote) and fetches the result from the binary cache.
# HOST is set by the Nix wrapper.

action=${1:-switch}
dir=${2:-$HOME/.dotfiles}
attr="nixosConfigurations.$HOST.config.system.build.toplevel"
remote=${NIXOS_SWITCH_REMOTE:-0}
evallock=${XDG_RUNTIME_DIR:-/tmp}/nixos-eval.lock

# One system evaluation at a time on this machine (3-4 GB each).
build_system() {
  if [ "$remote" = 1 ]; then
    nix-remote build "$@"
  else
    flock "$evallock" nix build "$@"
  fi
}

case $action in
  switch | boot | test | build | dry-build) ;;
  *)
    echo "nixos-remote-switch: unsupported action '$action' (switch, boot, test, build, dry-build)" >&2
    exit 2
    ;;
esac

cd "$dir" || exit 1

# Deploy guard. Several sessions deploy this machine from different
# checkouts; on 2026-10-21 a switch to bb020d39 was replaced ten seconds later
# by a switch from an older checkout, which silently removed a service. So the
# checkout must contain origin/main, and must contain the commit this machine
# last deployed through here (that one may not be pushed yet). It is checked
# before the build and again under a lock right before the activation, so two
# switches never interleave. Agents are refused; Erik (outside the agent slice
# or in his own T3 terminals) gets a warning. NIXOS_REMOTE_SWITCH_FORCE=1
# overrides.
state=${XDG_STATE_HOME:-$HOME/.local/state}/nixos-remote-switch
deployed=$state/deployed-$HOST

is_agent() {
  case "$(cat /proc/self/cgroup)" in
    */t3code-terminal-*) return 1 ;;
    */app-t3code.slice/*) return 0 ;;
    *) return 1 ;;
  esac
}

refuse() {
  if [ "${NIXOS_REMOTE_SWITCH_FORCE:-0}" = 1 ] || ! is_agent; then
    echo "warning: $1" >&2
    return 0
  fi
  echo "nixos-remote-switch: refused. $1" >&2
  echo "Update the checkout first (git pull --rebase --autostash), or deploy a clean clone of origin/main: nixos-remote-switch $action <dir>. NIXOS_REMOTE_SWITCH_FORCE=1 overrides." >&2
  exit 1
}

guard() {
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    refuse "$dir is not a git checkout, so nothing shows whether it reverts other deploys."
    return 0
  fi
  git fetch -q origin 2>/dev/null || echo "warning: git fetch failed; checking against the last fetched origin/main" >&2
  if git rev-parse -q --verify origin/main >/dev/null; then
    local behind
    behind=$(git rev-list --count HEAD..origin/main)
    if [ "$behind" -gt 0 ]; then
      refuse "$dir is $behind commit(s) behind origin/main; deploying it would revert them on this machine."
    fi
  fi
  # The last deploy through here, while it is still the running system.
  if [ -f "$deployed" ]; then
    local rev="" out="" from=""
    read -r rev out from _ <"$deployed" || true
    if [ -n "$rev" ] && [ "$rev" != - ] && [ "$(readlink -f /run/current-system)" = "$out" ] &&
      ! git merge-base --is-ancestor "$rev" HEAD 2>/dev/null; then
      refuse "this machine runs ${rev:0:8} (deployed from $from), which $dir does not contain; deploying it would revert that."
    fi
  fi
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "warning: $dir has uncommitted changes. They get deployed, but the next deploy from any other checkout drops them; commit and push." >&2
  fi
}

case $action in
  switch | boot | test) guard ;;
esac

if [ "$action" = dry-build ]; then
  build_system --dry-run ".#$attr"
  exit $?
fi

if [ "$remote" = 1 ]; then
  echo "== evaluating and building $HOST on the homelab builder"
else
  echo "== evaluating $HOST here (uncached builds go to the homelab builder)"
fi
out=$(build_system --no-link --print-out-paths ".#$attr") || exit 1
out=$(tail -n 1 <<<"$out")
if [[ ! $out =~ ^/nix/store/[a-z0-9]{32}-nixos-system-$HOST- ]]; then
  echo "nixos-remote-switch: the build returned no system path ('$out')" >&2
  exit 1
fi

nvd diff /run/current-system "$out" || true
if [ "$action" = build ]; then
  echo "$out"
  exit 0
fi

# One activation at a time, re-checked under the lock: another session may
# have deployed something newer while this one was building.
mkdir -p "$state"
exec 8>"$state/lock"
if ! flock -n 8; then
  echo "nixos-remote-switch: waiting for another switch on this machine to finish" >&2
  flock 8
fi
guard

if [ "$action" = switch ] || [ "$action" = boot ]; then
  sudo nix-env --profile /nix/var/nix/profiles/system --set "$out"
fi
# Its own system unit, like nixos-rebuild: the switch reloads the user
# manager, and a child of it would be killed halfway.
status=0
sudo systemd-run --unit="nixos-remote-switch-$(date +%s)" --collect --quiet \
  --wait --pipe --service-type=exec \
  --description="Switch to the new system (rebuild)" \
  "$out/bin/switch-to-configuration" "$action" || status=$?

if [ "$action" != boot ] && [ "$(readlink -f /run/current-system)" = "$out" ]; then
  echo "$(git rev-parse HEAD 2>/dev/null || echo -) $out $dir $(date -Iseconds)" >"$deployed"
fi
exit "$status"
