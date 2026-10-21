        # A git worktree's .git is a file pointing into the main checkout,
        # which the worker does not have: give it a repository of its own
        # instead, so git and `nix develop` (tracked files only) still work.
        worktree=0
        if [ -f "$local_root/.git" ]; then worktree=1; filters+=(--exclude=/.git); fi
        if [ "$worktree" = 1 ]; then
          remote "cd '$ws' && { [ -d .git ] || git init -q; } && git add -A" \
            || die "could not set up git in the worker's copy"
        fi
# `heavy`: run an agent's long-running or CPU/IO-heavy work on the homelab
# instead of this PC (policy since 2026-10-21: the PC is for Erik plus light
# agent work). It rsyncs the current repository one way to the agent-worker pod
# and runs the command there over SSH; it never falls back to running locally.
# The pod: homelab repo, kubernetes/homelab/apps/agent-worker.yaml and
# docs/agent-worker.md (worker-side scripts in config/agent-worker/). Rules
# for agents: the machines skill.
{ pkgs, ... }:
let
  host = "192.168.50.100";
  port = 2223;
  # The pod's host key lives on its volume, so it survives restarts.
  knownHosts = pkgs.writeText "agent-worker-known-hosts" ''
    [${host}]:${toString port} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJG2aZ34LJSz1NpgjZ92v0H1Qje3NRfKgfdXxWSurEqm
  '';

  heavy = pkgs.writeShellApplication {
    name = "heavy";
    # Remote commands are built here on purpose (workspace paths).
    excludeShellChecks = [ "SC2029" ];
    runtimeInputs = with pkgs; [
      openssh
      rsync
      coreutils
      gitMinimal
      android-tools
      systemd
      procps
    ];
    text = ''
      # -F /dev/null: the PC's ssh_config has GSSAPI options this openssh rejects.
      ssh_opts=(-F /dev/null -p ${toString port} -o UserKnownHostsFile=${knownHosts}
        -o StrictHostKeyChecking=yes -o BatchMode=yes -o ConnectTimeout=10
        -o ServerAliveInterval=30 -o ServerAliveCountMax=6 -o LogLevel=ERROR)
      target=root@${host}
      adb_port=15037

      usage() {
        cat <<'USAGE'
      heavy: run heavy agent work on the homelab worker, never on this PC.

        heavy [OPTIONS] [--] CMD...
            Sync this git repository (or the current directory) one way to the
            worker, then run CMD in the same subdirectory there. Output streams
            back and the exit code is CMD's. Ctrl-C or killing heavy kills the
            remote job. Nothing comes back unless you `heavy pull` it.
            --shell NAME   run inside the flake's devShell NAME (`android` or
                           `.#android`); default: the default devShell when
                           flake.nix has one
            --no-develop   do not enter a devShell
            -e VAR[=VAL]   pass an environment variable (repeatable); VAR alone
                           takes its value from here
            --no-sync      skip the sync (rerun on what is already there)
        heavy bg NAME [OPTIONS] [--] CMD...
                                start CMD as a background job that outlives
                                this command (a server next to the emulator)
        heavy stop NAME         stop that background job
        heavy logs NAME         its last 100 log lines
        heavy jobs              background jobs on the worker
        heavy forward PORT [LOCAL]
                                tunnel worker port PORT to 127.0.0.1:LOCAL here
                                (default LOCAL = PORT) until `heavy forward
                                stop PORT`
        heavy pull PATH...      copy PATHs (relative to here) back from the worker
        heavy shell             interactive shell in the workspace
        heavy status            worker load, memory, jobs, emulator, disk
        heavy emulator start    boot the one shared emulator on the worker
                                (pixel_7, API 36 google_apis x86_64). `adb` in
                                heavy commands sees it as the only device; it
                                reaches their servers at 10.0.2.2
        heavy emulator stop|status
        heavy adb ARGS...       adb on this PC against the worker's emulator
                                (or export ADB_SERVER_SOCKET=tcp:127.0.0.1:15037
                                after `heavy emulator start`)
      USAGE
      }

      die() { echo "heavy: $*" >&2; exit 2; }

      # Workspace: repository root (or cwd) -> /work/<name>-<hash of its path>.
      local_root=$(git rev-parse --show-toplevel 2> /dev/null || pwd -P)
      rel=$(realpath --relative-to="$local_root" "$(pwd -P)")
      ws="/work/$(basename "$local_root")-$(printf '%s' "$local_root" | sha256sum | cut -c1-8)"

      remote() { ssh "''${ssh_opts[@]}" "$target" "$@"; }
      q() { printf '%q ' "$@"; }

      sync_up() {
        remote "mkdir -p '$ws'" || die "cannot reach the worker (${host}:${toString port}); nothing was run locally"
        # Ignored and excluded paths are never deleted on the worker, so its
        # node_modules, build outputs and caches survive between runs.
        filters=(--filter=':- .gitignore' --exclude=node_modules/ --exclude=.direnv/
          --exclude=/result --exclude='result-*' --exclude=.venv/ --exclude=.turbo/
          --exclude=.gradle/ --exclude=.cxx/ --exclude=.expo/ --exclude=/.heavy/)
        # A git worktree's .git is a file pointing into the main checkout,
        # which the worker does not have: give the copy a repository of its
        # own, so git and `nix develop` (tracked files only) still work.
        worktree=0
        if [ -f "$local_root/.git" ]; then worktree=1; filters+=(--exclude=/.git); fi
        rsync -az --no-owner --no-group --delete "''${filters[@]}" -e "ssh ''${ssh_opts[*]}" \
          "$local_root/" "$target:$ws/" || die "sync to the worker failed; nothing was run locally"
        if [ "$worktree" = 1 ]; then
          remote "cd '$ws' && { [ -d .git ] || git init -q; } && git add -A" \
            || die "could not set up git in the worker's copy"
        fi
      }

      # Shared by `heavy CMD` and `heavy bg`: options, then the command,
      # prefixed with `env` for -e variables.
      parse_run() {
        sync=1 develop=auto envs=()
        while [ $# -gt 0 ]; do
          case "$1" in
            --no-sync) sync=0; shift ;;
            --no-develop) develop=no; shift ;;
            --shell) [ $# -ge 2 ] || die "--shell needs a name"; develop=''${2#.#}; shift 2 ;;
            -e)
              [ $# -ge 2 ] || die "-e needs VAR or VAR=VALUE"
              if [[ $2 == *=* ]]; then envs+=("$2"); else envs+=("$2=''${!2-}"); fi
              shift 2 ;;
            --) shift; break ;;
            -*) die "unknown option $1 (see heavy --help)" ;;
            *) break ;;
          esac
        done
        [ $# -gt 0 ] || { usage; exit 2; }
        cmd=("$@")
        [ ''${#envs[@]} -eq 0 ] || cmd=(env "''${envs[@]}" "$@")
      }

      tunnel() { # tunnel UNIT LOCAL REMOTE
        systemctl --user stop "$1" 2> /dev/null || true
        systemd-run --user --quiet --collect --unit="$1" \
          ssh "''${ssh_opts[@]}" -N -o ExitOnForwardFailure=yes \
          -L "127.0.0.1:$2:127.0.0.1:$3" "$target"
        sleep 2
        systemctl --user is-active --quiet "$1" || die "tunnel $2 -> worker:$3 failed (port in use?)"
      }

      emulator() {
        case "''${1:-status}" in
          start)
            remote bash /config/heavy-emulator.sh start || exit 1
            tunnel heavy-adb-tunnel "$adb_port" 5037
            echo "PC adb: heavy adb devices, or export ADB_SERVER_SOCKET=tcp:127.0.0.1:$adb_port"
            ;;
          stop)
            systemctl --user stop heavy-adb-tunnel 2> /dev/null || true
            remote bash /config/heavy-emulator.sh stop
            ;;
          status) remote bash /config/heavy-emulator.sh status ;;
          *) usage; exit 2 ;;
        esac
      }

      case "''${1:-}" in
        "" | -h | --help) usage; exit 0 ;;
        status) exec ssh "''${ssh_opts[@]}" "$target" bash /config/heavy-status.sh ;;
        emulator) shift; emulator "$@"; exit $? ;;
        adb)
          shift
          systemctl --user is-active --quiet heavy-adb-tunnel || tunnel heavy-adb-tunnel "$adb_port" 5037
          ADB_SERVER_SOCKET="tcp:127.0.0.1:$adb_port" exec adb "$@"
          ;;
        forward)
          shift
          [ $# -ge 1 ] || die "usage: heavy forward PORT [LOCAL] | heavy forward stop PORT"
          if [ "$1" = stop ]; then systemctl --user stop "heavy-forward-''${2:?port}"; exit $?; fi
          tunnel "heavy-forward-$1" "''${2:-$1}" "$1"
          echo "worker:$1 -> 127.0.0.1:''${2:-$1} (stop: heavy forward stop $1)"
          exit 0
          ;;
        shell) sync_up; exec ssh -t "''${ssh_opts[@]}" "$target" "cd $(q "$ws/$rel") && exec bash -l" ;;
        jobs) exec ssh "''${ssh_opts[@]}" "$target" bash /config/heavy-bg.sh list ;;
        stop) exec ssh "''${ssh_opts[@]}" "$target" "$(q bash /config/heavy-bg.sh stop "$ws" "''${2:?name}")" ;;
        logs) exec ssh "''${ssh_opts[@]}" "$target" "$(q bash /config/heavy-bg.sh logs "$ws" "''${2:?name}")" ;;
        bg)
          name=''${2:?usage: heavy bg NAME [OPTIONS] -- CMD...}
          shift 2
          parse_run "$@"
          [ "$sync" = 0 ] || sync_up
          exec ssh "''${ssh_opts[@]}" "$target" "$(q bash /config/heavy-bg.sh start "$ws" "$rel" "$develop" "$name" "''${cmd[@]}")"
          ;;
        pull)
          shift
          [ $# -gt 0 ] || die "usage: heavy pull PATH..."
          for path in "$@"; do
            src="$rel/$path"
            mkdir -p "$(dirname "$local_root/$src")"
            rsync -az --no-owner --no-group -e "ssh ''${ssh_opts[*]}" \
              "$target:$ws/$src" "$(dirname "$local_root/$src")/" || exit 1
          done
          exit 0
          ;;
      esac

      parse_run "$@"
      [ "$sync" = 0 ] || sync_up

      # The remote job lives as long as this SSH channel's stdin stays open:
      # feed it from a process that never writes, and close it to kill the job.
      ssh "''${ssh_opts[@]}" "$target" "$(q bash /config/heavy-run.sh "$ws" "$rel" "$develop" "''${cmd[@]}")" \
        < <(exec sleep 2147483647) &
      ssh_pid=$!
      keep=$(pgrep -P $$ -x sleep | head -1 || true)
      trap 'kill "$ssh_pid" $keep 2> /dev/null; wait "$ssh_pid"; exit 130' INT TERM HUP
      rc=0
      wait "$ssh_pid" || rc=$?
      [ -z "$keep" ] || kill "$keep" 2> /dev/null || true
      exit "$rc"
    '';
  };
in
{
  home.packages = [ heavy ];
}
