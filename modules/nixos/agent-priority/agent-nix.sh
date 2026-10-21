# nix, as agents see it (shadows the real one on PATH). From inside the agent
# slice, everything that evaluates or builds a flake runs on the homelab
# builder through nix-remote, evaluation included. Store paths are still
# realised here (that only downloads), and light commands pass through.
# Outside the agent slice, and in Erik's T3 terminals, it is the real nix.
real=@realNix@
remote=@nixRemote@

case "$(cat /proc/self/cgroup 2>/dev/null)" in
  */t3code-terminal-*) exec "$real" "$@" ;;
  */app-t3code.slice/*) ;;
  *) exec "$real" "$@" ;;
esac

refuse() {
  echo "nix (agent guard): $1" >&2
  echo "Heavy work runs on the homelab: nix-remote build|eval ..., rebuild, or heavy -- <cmd>." >&2
  exit 1
}

# Positional words, without option values that look like words.
sub="" sub2="" args=() file=0 installables=() store_only=1
skip=0
for a in "$@"; do
  if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
  case "$a" in
    # Flags of the form `--flag value` whose value must not count as a word.
    --store | --eval-store | --builders | --max-jobs | -j | --cores | --out-link | -o | \
      --profile | --override-input | --arg | --argstr | --apply | --system | --log-format | \
      --reference-lock-file | --output-lock-file | --inputs-from)
      case "$a" in --override-input | --arg | --argstr) skip=2 ;; *) skip=1 ;; esac
      ;;
    --option) skip=2 ;;
    -f | --file | --expr) file=1; skip=1 ;;
    -*) ;;
    *)
      if [ -z "$sub" ]; then sub=$a
      elif [ -z "$sub2" ] && [ "$sub" = flake ]; then sub2=$a
      else
        installables+=("$a")
        case "$a" in /nix/store/*) ;; *) store_only=0 ;; esac
      fi
      ;;
  esac
done

# Drop --store/--eval-store: `--eval-store auto --store ssh-ng://...` still
# evaluates here, which is the expensive part.
skip=0
for a in "$@"; do
  if [ "$skip" -gt 0 ]; then skip=$((skip - 1)); continue; fi
  case "$a" in
    --store | --eval-store | --builders) skip=1; continue ;;
    --store=* | --eval-store=* | --builders=*) continue ;;
  esac
  args+=("$a")
done

system_config=0
case " $* " in *nixosConfigurations* | *homeConfigurations* | *system.build* | *toplevel*) system_config=1 ;; esac

case "$sub" in
  build)
    if [ "$file" = 1 ]; then
      refuse "nix build -f/--expr cannot be sent to the builder; run it with heavy -- nix build ..."
    fi
    if [ "${#installables[@]}" -gt 0 ] && [ "$store_only" = 1 ]; then
      exec "$real" "$@"
    fi
    echo "nix (agent guard): building on the homelab builder (evaluation included)" >&2
    exec "$remote" "${args[@]}"
    ;;
  eval | derivation | path-info | why-depends)
    if [ "$system_config" = 1 ]; then
      [ "$file" = 1 ] && refuse "evaluating a system configuration from a file; use heavy"
      echo "nix (agent guard): evaluating on the homelab builder" >&2
      exec "$remote" "${args[@]}"
    fi
    ;;
  flake)
    case "$sub2" in
      check)
        echo "nix (agent guard): nix flake check runs on the homelab builder" >&2
        exec "$remote" "${args[@]}"
        ;;
    esac
    ;;
  repl)
    [ "$system_config" = 1 ] && refuse "nix repl on a system configuration"
    ;;
esac
exec "$real" "$@"
