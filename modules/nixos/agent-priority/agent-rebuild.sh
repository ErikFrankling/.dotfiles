# nh / nixos-rebuild, as agents see them (shadow the real ones on PATH).
# From inside the agent slice a system rebuild means nixos-remote-switch
# (the deploy guards, evaluation here, activation). Anything else
# is refused (it would skip the deploy guards). Outside the agent slice,
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
    echo "$name (agent guard): building with the deploy guards, then activating (nixos-remote-switch $action)" >&2
    exec nixos-remote-switch "$action"
    ;;
esac
echo "$name (agent guard): '$*' is not supported for agents. Use: rebuild [switch|boot|test|build|dry-build] [--remote], nix build, nix-remote, or heavy -- <cmd>." >&2
exit 1
