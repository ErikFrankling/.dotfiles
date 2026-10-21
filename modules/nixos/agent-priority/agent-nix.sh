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
exec "$real" "$@"
