# nh / nixos-rebuild, as agents see them (shadow the real ones on PATH).
# From inside the agent slice a system rebuild means nixos-remote-switch:
# evaluate and build on the homelab builder, activate here. Anything else
# that would evaluate or build locally is refused. Outside the agent slice,
# and in Erik's T3 terminals, it is the real command.
real=@real@
name=@name@

case "$(cat /proc/self/cgroup 2>/dev/null)" in
  */t3code-terminal-*) exec "$real" "$@" ;;
  */app-t3code.slice/*) ;;
  *) exec "$real" "$@" ;;
esac

words=()
for a in "$@"; do
  case "$a" in -*) ;; *) words+=("$a") ;; esac
done

action=""
case "$name" in
  nh)
    case "${words[0]:-}" in
      search) exec "$real" "$@" ;;
      os) action=${words[1]:-} ;;
    esac
    ;;
  nixos-rebuild) action=${words[0]:-} ;;
esac

case "$action" in
  switch | boot | test | build | dry-build)
    echo "$name (agent guard): evaluating and building on the homelab builder, then activating here (nixos-remote-switch $action)" >&2
    exec nixos-remote-switch "$action"
    ;;
esac
echo "$name (agent guard): '$*' would evaluate or build on the pc. Agents use: rebuild [switch|boot|test|build|dry-build], nix-remote ..., or heavy -- <cmd>." >&2
exit 1
