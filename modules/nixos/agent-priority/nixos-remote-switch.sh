# nixos-remote-switch [switch|boot|test|build|dry-build] [flake-dir]
#
# What `rebuild` does on the pc: evaluate and build this host's system on the
# homelab builder (nix-remote), fetch it from the binary cache, show what
# changed, then activate it here. Nothing heavy runs on this machine.
# HOST is set by the Nix wrapper.

action=${1:-switch}
dir=${2:-$HOME/.dotfiles}
attr="nixosConfigurations.$HOST.config.system.build.toplevel"

case $action in
  switch | boot | test | build | dry-build) ;;
  *)
    echo "nixos-remote-switch: unsupported action '$action' (switch, boot, test, build, dry-build)" >&2
    exit 2
    ;;
esac

cd "$dir" || exit 1
if [ "$action" = dry-build ]; then
  exec nix-remote build --dry-run ".#$attr"
fi

echo "== evaluating and building $HOST on the homelab builder"
out=$(nix-remote build --no-link --print-out-paths ".#$attr") || exit 1
out=$(tail -n 1 <<<"$out")
if [[ ! $out =~ ^/nix/store/[a-z0-9]{32}-nixos-system-$HOST- ]]; then
  echo "nixos-remote-switch: the builder returned no system path ('$out')" >&2
  exit 1
fi

nvd diff /run/current-system "$out" || true
if [ "$action" = build ]; then
  echo "$out"
  exit 0
fi

if [ "$action" = switch ] || [ "$action" = boot ]; then
  sudo nix-env --profile /nix/var/nix/profiles/system --set "$out"
fi
# Its own system unit, like nixos-rebuild: the switch reloads the user
# manager, and a child of it would be killed halfway.
exec sudo systemd-run --unit="nixos-remote-switch-$(date +%s)" --collect --quiet \
  --wait --pipe --service-type=exec \
  --description="Switch to the system built by the homelab" \
  "$out/bin/switch-to-configuration" "$action"
