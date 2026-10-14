# The agent side of the daily update (the machine side is
# ../../nixos/auto-update.nix).
#
# Both hosts get the two skills. The PC additionally runs the nightly job: a
# timer starts a T3 Code session that updates flake.lock, builds both hosts'
# closures on the homelab and pushes to main once they are built. The session
# follows the nix-update-doctor skill and repairs what the update broke. At
# 07:00 a second session (systems-check skill) checks that the pc, the
# framework and the homelab all ended up in working order, repairs what did
# not, and sends Erik one summary notification.
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
  # The morning check keeps its own clones, apart from the nightly one.
  checkDir = "${home}/.local/state/systems-check";
  cacheUrl = "https://nix-cache.erikfrankling.duckdns.org";
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
          # not listed; only real builds matter. A dry run against a remote
          # store only knows derivations that are already there, so the .drv
          # closure is copied over first; without that the builder answers
          # "don't know how to build" and this printed nothing.
          for host in ${lib.concatStringsSep " " hosts}; do
            echo "== $host"
            drv=$(nix eval --raw "$(attr "$host").drvPath")
            nix copy --to ${builder} "$drv"
            nix build --dry-run --store ${builder} "$drv^*" 2>&1 \
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
          echo "$rev $(date -Iseconds)" > ${stateDir}/last-build
          echo "OK: both hosts built at $rev"
          ;;

        notify)
          shift
          echo "$(date -Iseconds) $*" > ${stateDir}/last-notify
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

  # Starts a session through the T3 Code server's HTTP API, the same commands
  # the web UI sends. The server runs on this machine without auth
  # (hosts/pc/home.nix). The session works in a dotfiles clone of its own: it
  # resets and commits freely, and the real checkout may be mid-edit.
  mkSessionStarter =
    {
      name,
      label,
      clone,
      prompt,
      # Extra repositories cloned and reset next to the dotfiles: { dir = url; }.
      extraClones ? { },
      # Shell run before anything else; call `fail "<why>"` to not start.
      preflight ? "",
    }:
    pkgs.writeShellApplication {
      inherit name;
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
          notify-send --app-name ${lib.escapeShellArg label} --urgency critical \
            ${lib.escapeShellArg "${label} did not start"} "$1" || true
          exit 1
        }

        ${preflight}

        fresh() {
          if [ ! -d "$2/.git" ]; then
            git clone --quiet "$1" "$2" || fail "Could not clone $1."
          fi
          git -C "$2" fetch --quiet origin main || fail "Could not fetch $1."
          git -C "$2" checkout --quiet -B main origin/main
          git -C "$2" reset --quiet --hard origin/main
          git -C "$2" clean --quiet -fd
        }
        mkdir -p "$(dirname ${clone})"
        fresh git@github.com:ErikFrankling/.dotfiles.git ${clone}
        ${lib.concatStringsSep "\n" (
          lib.mapAttrsToList (dir: url: "fresh ${lib.escapeShellArg url} ${dir}") extraClones
        )}
        cd ${clone}

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
            --arg title ${lib.escapeShellArg (lib.toLower label)} \
            '{type: "project.create", commandId: $cmd, projectId: $id,
              title: $title, workspaceRoot: "${clone}", createdAt: $now}')" \
            || fail "Could not create the T3 Code project."
        fi

        thread=$(uuidgen)
        model='${builtins.toJSON cfg.modelSelection}'
        dispatch "$(jq -n --arg id "$thread" --arg project "$project" --arg cmd "$(uuidgen)" \
          --arg now "$now" --arg title "${label} $(date +%F)" --argjson model "$model" \
          '{type: "thread.create", commandId: $cmd, threadId: $id, projectId: $project,
            title: $title, modelSelection: $model, runtimeMode: "full-access",
            interactionMode: "default", branch: null, worktreePath: null, createdAt: $now}')" \
          || fail "Could not create the T3 Code thread."

        dispatch "$(jq -n --arg id "$thread" --arg cmd "$(uuidgen)" --arg msg "$(uuidgen)" \
          --arg now "$now" --argjson model "$model" --arg text ${lib.escapeShellArg prompt} \
          '{type: "thread.turn.start", commandId: $cmd, threadId: $id,
            message: {messageId: $msg, role: "user", text: $text, attachments: []},
            modelSelection: $model, runtimeMode: "full-access",
            interactionMode: "default", createdAt: $now}')" \
          || fail "Could not start the session."
        echo "started T3 Code thread $thread"
      '';
    };

  startNightly = mkSessionStarter {
    name = "nix-nightly-start";
    label = "Nightly update";
    inherit clone;
    inherit (cfg) prompt;
    # A previous session that is still building owns the clone; resetting it
    # underneath would wreck that run.
    preflight = ''
      if pgrep -u "$(id -u)" -f 'nix build .*--store ${builder}' > /dev/null; then
        fail "Last night's update is still building on the homelab, so tonight's was not started."
      fi
    '';
  };

  startCheck = mkSessionStarter {
    name = "systems-check-start";
    label = "Morning check";
    clone = "${checkDir}/dotfiles";
    extraClones."${checkDir}/homelab" = "git@github.com:ErikFrankling/homelab.git";
    prompt = cfg.check.prompt;
  };

  # Facts about one NixOS machine. Run locally for the pc and over SSH for the
  # framework, so it is plain bash with nothing from the store.
  hostFacts = pkgs.writeText "host-facts" ''
    export XDG_RUNTIME_DIR=/run/user/$(id -u)
    echo "running system: $(readlink /run/current-system)"
    if [ "$(readlink -f /run/booted-system/kernel)" != "$(readlink -f /run/current-system/kernel)" ] \
      || [ "$(readlink -f /run/booted-system/initrd)" != "$(readlink -f /run/current-system/initrd)" ]; then
      echo "kernel: NEW KERNEL INSTALLED, needs a restart"
    else
      echo "kernel: running the installed one"
    fi
    echo "up: $(( $(cut -d. -f1 /proc/uptime) / 3600 )) hours"
    echo "disk /: $(df -h --output=avail,pcent / | tail -n 1 | xargs) (avail, used)"
    echo "failed system units: $(systemctl --failed --no-legend --plain | awk '{print $1}' | xargs)"
    echo "failed user units: $(systemctl --user --failed --no-legend --plain | awk '{print $1}' | xargs)"
    echo "auto-update, last 24h:"
    journalctl --user -u auto-update --since -24h -o short-iso --no-pager 2> /dev/null \
      | grep -v -i -e gssapi -e '^-- ' | tail -n 12 | sed 's/^/  /'
    echo "switch units, last 24h:"
    journalctl -u 'auto-update-switch-*' --since -24h -o short-iso --no-pager 2> /dev/null \
      | grep -v '^-- ' | tail -n 6 | sed 's/^/  /'
  '';

  # Collects the state of every machine for the morning check. Facts only;
  # the session decides what is wrong. Each probe has a timeout so one dead
  # machine cannot hang the report.
  systemsCheck = pkgs.writeShellApplication {
    name = "systems-check";
    runtimeInputs = [
      config.nix.package
      pkgs.git
      pkgs.openssh
      pkgs.curl
      pkgs.openssl
      pkgs.libnotify
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.gnused
      pkgs.gawk
      pkgs.findutils
      pkgs.procps
      pkgs.systemd
    ];
    text = ''
      export GIT_SSH_COMMAND="ssh -o BatchMode=yes"
      mkdir -p ${checkDir}
      quiet() { grep -v -i gssapi || true; }
      section() { printf '\n== %s\n' "$1"; }

      case "''${1:-}" in
        status)
          dot=${checkDir}/dotfiles
          [ -d $dot/.git ] || git clone --quiet git@github.com:ErikFrankling/.dotfiles.git $dot
          git -C $dot fetch --quiet origin main 2>&1 | quiet
          main=$(git -C $dot rev-parse origin/main)

          section "dotfiles main"
          git -C $dot log -1 --format='%h %ci %s' origin/main
          echo "last 'Update flake inputs': $(git -C $dot log -1 --format='%h %ci' --grep='^Update flake inputs' origin/main)"
          if [ -f ${stateDir}/last-build ]; then
            read -r built when < ${stateDir}/last-build
            echo "last nightly build: ''${built:0:8} at $when"
            if [ "$built" = "$main" ]; then echo "main is built: yes"
            else echo "main is built: NO (main has commits the nightly build did not cover)"; fi
          else
            echo "last nightly build: none recorded"
          fi
          [ -f ${stateDir}/last-notify ] && echo "last nightly alert: $(cat ${stateDir}/last-notify)"
          pgrep -u "$(id -u)" -f 'nix build .*--store ${builder}' > /dev/null \
            && echo "a nightly build is STILL RUNNING"
          echo "nightly clone: $(git -C ${clone} log -1 --format='%h %s' 2>/dev/null), $(git -C ${clone} status --porcelain 2>/dev/null | wc -l) uncommitted files"

          for host in ${lib.concatStringsSep " " hosts}; do
            section "$host"
            expected=$(timeout 300 nix eval --raw \
              "git+file://$dot?rev=$main#nixosConfigurations.$host.config.system.build.toplevel.outPath" \
              2> ${checkDir}/eval-$host.log) \
              || expected="EVAL FAILED: $(grep -m 1 -A 3 '^error' ${checkDir}/eval-$host.log | xargs)"
            echo "main's system: $expected"
            if [[ $expected == /nix/store/* ]]; then
              if nix path-info --store ${cacheUrl} "$expected" > /dev/null 2>&1; then
                echo "in the cache: yes"
              else
                echo "in the cache: NO"
              fi
            fi
            if [ "$host" = "$(cat /proc/sys/kernel/hostname)" ]; then
              facts=$(bash ${hostFacts} 2>&1)
            elif ! facts=$(timeout 90 ssh -o BatchMode=yes "$host" bash -s < ${hostFacts} 2>&1 | quiet); then
              facts="UNREACHABLE over SSH: $(echo "$facts" | tail -n 2 | xargs)"
              facts+=$'\n'"tailnet: $(timeout 30 ssh -o BatchMode=yes proxmox tailscale status 2>&1 | quiet | grep -w "$host" | xargs)"
            fi
            [ -z "$facts" ] && facts="UNREACHABLE over SSH (no output)"
            echo "$facts"
            if [[ $facts == *"running system: $expected"* ]]; then
              echo "=> runs main: yes"
            else
              echo "=> runs main: NO"
            fi
          done

          section "homelab"
          hl=$(git ls-remote https://github.com/ErikFrankling/homelab.git main | cut -c1-40)
          echo "homelab main: ''${hl:0:8}"
          # Deliberately expanded remotely.
          # shellcheck disable=SC2016
          timeout 120 ssh -o BatchMode=yes naiaclaw '
            k() { sudo kubectl "$@"; }
            echo "flux: suspended=$(k -n homelab get kustomization homelab -o jsonpath="{.spec.suspend}")" \
              "applied=$(k -n homelab get kustomization homelab -o jsonpath="{.status.lastAppliedRevision}")" \
              "ready=$(k -n homelab get kustomization homelab -o jsonpath="{.status.conditions[?(@.type==\"Ready\")].message}")"
            echo "nodes: $(k get nodes --no-headers | awk "{print \$1, \$2}" | xargs)"
            echo "deployments not fully ready:"
            k get deploy -A --no-headers | awk "{split(\$3,a,\"/\"); if (a[1]!=a[2]) print \"  \" \$1 \"/\" \$2 \" \" \$3}"
            echo "pods not running (by namespace):"
            k get pods -A --no-headers | grep -vE " (Running|Completed) " | awk "{print \"  \" \$1, \$2, \$4}"
            echo "naiaclaw disk /: $(df -h --output=avail,pcent / | tail -n 1 | xargs); memory available: $(free -h | awk "/Mem:/ {print \$7}")"
          ' 2>&1 | quiet || echo "naiaclaw: UNREACHABLE"
          # shellcheck disable=SC2016
          timeout 60 ssh -o BatchMode=yes proxmox '
            echo "proxmox: up $(uptime -p | sed "s/up //"), memory available $(free -h | awk "/Mem:/ {print \$7}")"
            qm list | awk "NR>1 {print \"  vm\", \$1, \$2, \$3}"
          ' 2>&1 | quiet || echo "proxmox: UNREACHABLE"
          echo "homelab main applied: $(timeout 60 ssh -o BatchMode=yes naiaclaw 'sudo kubectl -n homelab get kustomization homelab -o jsonpath={.status.lastAppliedRevision}' 2>/dev/null | grep -q "$hl" && echo yes || echo NO)"
          if curl -fsS --max-time 15 -o /dev/null ${cacheUrl}/nix-cache-info; then
            echo "nix cache: answering"
          else
            echo "nix cache: NOT ANSWERING"
          fi
          end=$(echo | timeout 15 openssl s_client -connect 192.168.50.100:443 \
            -servername vault.erikfrankling.duckdns.org 2> /dev/null | openssl x509 -noout -enddate 2> /dev/null)
          echo "wildcard certificate: ''${end:-UNREACHABLE}"
          echo "duckdns: $(getent ahostsv4 vault.erikfrankling.duckdns.org | head -n 1 | awk '{print $1}') (should be 192.168.50.100)"
          ;;

        report)
          # report <ok|attention> <message>: the one notification of the morning.
          urgency=normal
          title="Morning check: all good"
          if [ "$2" != ok ]; then
            urgency=critical
            title="Morning check: something needs you"
          fi
          notify-send --app-name "Morning check" --urgency "$urgency" "$title" "$3"
          printf '%s %s\n%s\n' "$(date -Iseconds)" "$2" "$3" > "${checkDir}/report-$(date +%F)"
          find ${checkDir} -maxdepth 1 -name 'report-*' -mtime +30 -delete
          ;;

        watchdog)
          if [ ! -f "${checkDir}/report-$(date +%F)" ]; then
            notify-send --app-name "Morning check" --urgency critical "Morning check did not report" \
              "Today's systems check never sent its summary. Its thread in T3 Code (project 'morning check') says why."
          fi
          ;;

        *)
          echo "usage: systems-check status | report <ok|attention> <message> | watchdog" >&2
          exit 2
          ;;
      esac
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
      default = "Load the nix-update-doctor skill and run tonight's update exactly as it describes, including fixing the evaluation warnings whose fix is clear. This is the scheduled nightly run; nobody is watching, so do not ask questions.";
      description = "First message of the nightly session.";
    };
    check = {
      time = lib.mkOption {
        type = lib.types.str;
        default = "07:00";
        description = "When the morning systems check starts, after both machines applied at 06:00.";
      };
      prompt = lib.mkOption {
        type = lib.types.str;
        default = "Load the systems-check skill and run this morning's check exactly as it describes: find out whether the pc, the framework and the homelab are all in working order, repair what is not, and send the one summary notification. This is the scheduled morning run; nobody is watching, so do not ask questions.";
        description = "First message of the morning check session.";
      };
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
            "systems-check"
          ];
        }
      );
    }

    (lib.mkIf cfg.enable {
      home.packages = [
        nixNightly
        startNightly
        systemsCheck
        startCheck
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

      # The morning check: one session that verifies what the night did on
      # every machine, repairs what is broken and sends one summary.
      systemd.user.services.systems-check = {
        Unit.Description = "Start the morning systems check session in T3 Code";
        Service = {
          Type = "oneshot";
          ExecStart = lib.getExe startCheck;
        };
      };

      systemd.user.timers.systems-check = {
        Unit.Description = "Morning systems check";
        Timer = {
          OnCalendar = cfg.check.time;
          # Unlike the nightly run this one only repairs, so a missed morning
          # is worth catching up on.
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };

      # Silence is not "all good": if the check never reported, say so.
      systemd.user.services.systems-check-watchdog = {
        Unit.Description = "Notify when the morning systems check did not report";
        Service = {
          Type = "oneshot";
          ExecStart = "${lib.getExe systemsCheck} watchdog";
        };
      };

      systemd.user.timers.systems-check-watchdog = {
        Unit.Description = "Check that the morning systems check reported";
        Timer = {
          OnCalendar = "10:00";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
    })
  ];
}
