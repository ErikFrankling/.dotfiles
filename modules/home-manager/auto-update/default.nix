# The agent side of the daily update (the machine side is
# ../../nixos/auto-update.nix).
#
# Both hosts get the two skills. The PC additionally runs the nightly job: a
# timer starts a T3 Code session that updates flake.lock, builds both hosts'
# closures on the homelab and pushes to main once they are built. The session
# follows the nix-update-doctor skill and repairs what the update broke.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.autoUpdateNightly;
  home = config.home.homeDirectory;
  stateDir = "${home}/.local/state/nix-nightly";
  clone = "${stateDir}/dotfiles";
  # SSH alias from modules/nixos/default.nix.
  builder = "ssh-ng://nix-builder";
  hosts = [
    "pc"
    "framework"
  ];
  keepPerHost = 5;

  nixNightly = pkgs.writeShellApplication {
    name = "nix-nightly";
    runtimeInputs = [
      config.nix.package
      pkgs.git
      pkgs.openssh
      pkgs.libnotify
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
    ];
    text = ''
      attr() { echo ".#nixosConfigurations.$1.config.system.build.toplevel"; }
      mkdir -p ${stateDir}

      case "''${1:-}" in
        plan)
          # What the homelab would have to build, per host. Substitutions are
          # not listed; only real builds matter.
          for host in ${lib.concatStringsSep " " hosts}; do
            echo "== $host"
            nix build --dry-run --eval-store auto --store ${builder} "$(attr "$host")" 2>&1 \
              | sed -n '/will be built:/,/will be fetched/p' \
              | sed 's|^  /nix/store/[a-z0-9]*-|  |' \
              | grep -v 'will be fetched' || true
          done
          ;;

        build)
          if [ -n "$(git status --porcelain)" ]; then
            echo "working tree is dirty; commit first, the build has to match a commit" >&2
            exit 2
          fi
          rev=$(git rev-parse HEAD)
          stamp=$(date +%Y%m%d-%H%M%S)
          paths=()
          for host in ${lib.concatStringsSep " " hosts}; do
            log=${stateDir}/build-$host.log
            echo "== building $host on the homelab (log: $log)"
            # The exit status alone is not trusted: a build that failed on the
            # remote store has been seen to return 0 with no output path.
            out=$(nix build --no-link --print-out-paths --eval-store auto \
              --store ${builder} "$(attr "$host")" 2> "$log") || out=""
            if [[ ! $out =~ ^/nix/store/[a-z0-9]{32}-nixos-system-$host- ]]; then
              echo "== $host FAILED. Last lines:" >&2
              tail -n 60 "$log" >&2
              exit 1
            fi
            echo "$host $out"
            paths+=("$host=$out")
          done

          # Root the results so the builder's garbage collector keeps them, and
          # keep only the newest few per host. Then collect if the node's disk
          # is getting low; nix.conf on the builder does the same mid-build.
          for entry in "''${paths[@]}"; do
            host=''${entry%%=*}
            out=''${entry#*=}
            # Deliberately expanded here: the remote shell gets literal values.
            # shellcheck disable=SC2029
            ssh nix-builder "
              set -e
              export PATH=/nix/var/builder/bin:\$PATH
              roots=/nix/var/nix/gcroots/auto-update
              mkdir -p \$roots
              ln -sfn $out \$roots/$host-$stamp
              ls -1 \$roots | grep '^$host-' | sort -r | tail -n +${toString (keepPerHost + 1)} \
                | while read -r old; do rm -f \$roots/\$old; done
            "
          done
          ssh nix-builder '
            export PATH=/nix/var/builder/bin:$PATH
            free=$(df --output=avail -BG /nix | tail -n 1 | tr -dc 0-9)
            if [ "$free" -lt 80 ]; then nix-collect-garbage > /dev/null 2>&1; fi
          ' || true
          echo "OK: both hosts built at $rev"
          ;;

        notify)
          shift
          notify-send --app-name "Nightly update" --urgency critical \
            "Nightly update needs you" "$*"
          ;;

        *)
          echo "usage: nix-nightly plan | build | notify <message>" >&2
          exit 2
          ;;
      esac
    '';
  };

  # Starts the session through the T3 Code server's HTTP API, the same
  # commands the web UI sends. The server runs on this machine without auth
  # (hosts/pc/home.nix).
  startNightly = pkgs.writeShellApplication {
    name = "nix-nightly-start";
    runtimeInputs = [
      pkgs.git
      pkgs.openssh
      pkgs.curl
      pkgs.jq
      pkgs.util-linux
      pkgs.procps
      pkgs.coreutils
      pkgs.libnotify
    ];
    text = ''
      t3=http://127.0.0.1:3773
      export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

      fail() {
        echo "$1" >&2
        notify-send --app-name "Nightly update" --urgency critical \
          "Nightly update did not start" "$1" || true
        exit 1
      }

      # A previous session that is still building owns the clone; resetting it
      # underneath would wreck that run.
      if pgrep -u "$(id -u)" -f 'nix build .*--store ${builder}' > /dev/null; then
        fail "Last night's update is still building on the homelab, so tonight's was not started."
      fi

      # A clone of its own: the session resets and commits freely, and the
      # real checkout may be mid-edit.
      mkdir -p ${stateDir}
      if [ ! -d ${clone}/.git ]; then
        git clone --quiet git@github.com:ErikFrankling/.dotfiles.git ${clone} \
          || fail "Could not clone the dotfiles."
      fi
      cd ${clone}
      git fetch --quiet origin main || fail "Could not fetch the dotfiles from GitHub."
      git checkout --quiet -B main origin/main
      git reset --quiet --hard origin/main
      git clean --quiet -fd

      dispatch() {
        curl -fsS --max-time 30 -X POST "$t3/api/orchestration/dispatch" \
          -H 'Content-Type: application/json' -d "$1" > /dev/null
      }
      now=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)

      project=$(curl -fsS --max-time 30 "$t3/api/orchestration/shell" \
        | jq -r --arg root ${clone} 'first(.projects[] | select(.workspaceRoot == $root) | .id) // empty') \
        || fail "The T3 Code server is not answering."
      if [ -z "$project" ]; then
        project=$(uuidgen)
        dispatch "$(jq -n --arg id "$project" --arg cmd "$(uuidgen)" --arg now "$now" \
          '{type: "project.create", commandId: $cmd, projectId: $id,
            title: "nightly update", workspaceRoot: "${clone}", createdAt: $now}')" \
          || fail "Could not create the T3 Code project."
      fi

      thread=$(uuidgen)
      model='${builtins.toJSON cfg.modelSelection}'
      dispatch "$(jq -n --arg id "$thread" --arg project "$project" --arg cmd "$(uuidgen)" \
        --arg now "$now" --arg title "Nightly update $(date +%F)" --argjson model "$model" \
        '{type: "thread.create", commandId: $cmd, threadId: $id, projectId: $project,
          title: $title, modelSelection: $model, runtimeMode: "full-access",
          interactionMode: "default", branch: null, worktreePath: null, createdAt: $now}')" \
        || fail "Could not create the T3 Code thread."

      dispatch "$(jq -n --arg id "$thread" --arg cmd "$(uuidgen)" --arg msg "$(uuidgen)" \
        --arg now "$now" --argjson model "$model" --arg text ${lib.escapeShellArg cfg.prompt} \
        '{type: "thread.turn.start", commandId: $cmd, threadId: $id,
          message: {messageId: $msg, role: "user", text: $text, attachments: []},
          modelSelection: $model, runtimeMode: "full-access",
          interactionMode: "default", createdAt: $now}')" \
        || fail "Could not start the nightly session."
      echo "started T3 Code thread $thread"
    '';
  };
in
{
  options.autoUpdateNightly = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Run the nightly flake update and homelab build from this machine.";
    };
    time = lib.mkOption {
      type = lib.types.str;
      default = "03:00";
      description = "When the nightly session starts. The machines apply at 06:00.";
    };
    modelSelection = lib.mkOption {
      type = lib.types.attrs;
      default = {
        instanceId = "claudeAgent";
        model = "claude-opus-5-5";
        options = [
          {
            id = "fastMode";
            value = false;
          }
        ];
      };
      description = "T3 Code model selection for the nightly session.";
    };
    prompt = lib.mkOption {
      type = lib.types.str;
      default = "Load the nix-update-doctor skill and run tonight's update exactly as it describes. This is the scheduled nightly run; nobody is watching, so do not ask questions.";
      description = "First message of the nightly session.";
    };
  };

  config = lib.mkMerge [
    {
      home.file = lib.mergeAttrsList (
        lib.mapCartesianProduct ({ dir, skill }: { "${dir}/${skill}".source = ./skill + "/${skill}"; }) {
          dir = [
            ".agents/skills"
            ".claude/skills"
            ".codex/skills"
          ];
          skill = [
            "nix-update-doctor"
            "dotfiles-sync"
          ];
        }
      );
    }

    (lib.mkIf cfg.enable {
      home.packages = [
        nixNightly
        startNightly
      ];

      systemd.user.services.nix-nightly = {
        Unit.Description = "Start the nightly NixOS update session in T3 Code";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe startNightly;
        };
      };

      systemd.user.timers.nix-nightly = {
        Unit.Description = "Nightly NixOS update";
        Timer = {
          OnCalendar = cfg.time;
          # Not Persistent: a run that was missed overnight should not start
          # in the middle of the day and push while the machines are in use.
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ];
}
