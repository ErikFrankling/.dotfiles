# nix-remote <nix arguments...>
#
# Runs a nix command on the homelab builder instead of this machine. Local
# flake references (`.#attr`, `/path#attr`, `~/x#attr`) are copied there first
# with `nix flake archive` and rewritten to the copied store path, so the
# evaluation (several GB for a NixOS system) and the build both happen on the
# homelab. `nix-remote build` then fetches the results from the binary cache,
# which serves the builder's store.
#
#   nix-remote build --dry-run .#nixosConfigurations.pc.config.system.build.toplevel
#   nix-remote eval .#nixosConfigurations.pc.config.networking.hostName
#   nix-remote build --print-out-paths .#nixosConfigurations.pc.config.system.build.toplevel
#
# It never falls back to running locally. Set NIX_REMOTE_FETCH=0 to leave
# build results on the builder.

builder_store=ssh-ng://nix-builder

if [ $# -eq 0 ]; then
  echo "usage: nix-remote <nix arguments>, e.g. nix-remote build --dry-run .#nixosConfigurations.pc.config.system.build.toplevel" >&2
  exit 2
fi

declare -A archived=()
args=()
sub=""
dry=0 print=0 json=0 nolink=0
for a in "$@"; do
  if [ -z "$sub" ] && [[ $a != -* ]]; then sub=$a; fi
  case $a in
    --dry-run) dry=1 ;;
    --print-out-paths) print=1 ;;
    --json) json=1 ;;
    --no-link) nolink=1 ;;
  esac
  if [[ $a == *#* && $a != /nix/store/* && ($a == .* || $a == /* || $a == "~"* || $a == "#"*) ]]; then
    ref=${a%%#*}
    attr=${a#*#}
    ref=${ref:-.}
    ref=${ref/#\~/$HOME}
    if [ -z "${archived[$ref]:-}" ]; then
      echo "nix-remote: copying $ref to the homelab builder" >&2
      path=$(nix flake archive --json --to "$builder_store" "$ref" | jq -r .path) || {
        echo "nix-remote: could not copy $ref to the builder (is the homelab up? ssh nix-builder)" >&2
        exit 1
      }
      archived[$ref]=$path
    fi
    args+=("${archived[$ref]}#$attr")
  else
    args+=("$a")
  fi
done

fetch=0
if [ "$sub" = build ] && [ "$dry" = 0 ]; then
  # Results stay out of the builder's root home, and come back as paths.
  [ "$nolink" = 1 ] || args+=(--no-link)
  [ "$print" = 1 ] || [ "$json" = 1 ] || args+=(--print-out-paths)
  [ "${NIX_REMOTE_FETCH:-1}" = 1 ] && fetch=1
fi

remote="export PATH=/nix/var/builder/bin:\$PATH; exec nix --extra-experimental-features 'nix-command flakes' $(printf '%q ' "${args[@]}")"
tty=()
[ -t 0 ] && [ -t 1 ] && [ "$fetch" = 0 ] && tty=(-tt)

if [ "$fetch" = 0 ]; then
  exec ssh "${tty[@]}" nix-builder -- "$remote"
fi

out=$(ssh nix-builder -- "$remote") || exit $?
if [ "$json" = 1 ]; then
  paths=$(jq -r '.[].outputs[]' <<<"$out")
else
  paths=$out
fi
if [ -n "$paths" ]; then
  echo "nix-remote: fetching the results from the binary cache" >&2
  # shellcheck disable=SC2086
  nix build --no-link $paths || exit $?
fi
if [ "$print" = 1 ] || [ "$json" = 1 ]; then
  printf '%s\n' "$out"
fi
if [ "$nolink" = 0 ]; then
  echo "nix-remote: no ./result link is made; use --print-out-paths" >&2
fi
