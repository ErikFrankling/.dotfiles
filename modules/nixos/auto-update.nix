# Daily system updates that never compile on this machine.
#
# The homelab builds both hosts' system closures every night and serves them
# as a binary cache (homelab repo: docs/nix-builder.md). The nightly job only
# pushes to main once both closures are built, so main is the state: whatever
# is on main is in the cache. Once a day this module pulls main and rebuilds
# with building forbidden (--max-jobs 0). Anything that would have to compile
# makes the run stop with a notification instead.
#
# Local work in ~/.dotfiles, committed or not, is handed to a headless Claude
# session first, which commits it, merges main and pushes (the dotfiles-sync
# skill). That checkout is then ahead of what the homelab built, so the
# rebuild is skipped for the day and tomorrow's build picks the changes up.
#
# It never reboots. When the new system has a different kernel it leaves a
# desktop notification saying so.
#
# The nightly job that updates flake.lock and drives the build is PC-only and
# lives in ../home-manager/auto-update.
{
  config,
  pkgs,
  lib,
  hostName,
  username,
  ...
}:
let
  cfg = config.autoUpdate;
  cacheUrl = "https://nix-cache.erikfrankling.duckdns.org";
  cacheKey = "nix-cache.erikfrankling.duckdns.org-1:i1VytpUS/NiHyPJq8tWmvhrhfBL7L3+ZOcVYq2BXWdA=";
  home = "/home/${username}";
  dotfiles = "${home}/.dotfiles";

  updateScript = pkgs.writeShellApplication {
    name = "auto-update";
    runtimeInputs = [
      config.nix.package
      config.programs.nh.package
      pkgs.curl
      pkgs.iproute2
      pkgs.networkmanager
      pkgs.git
      pkgs.openssh
      pkgs.libnotify
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      # sudo is a setuid wrapper, and claude lives in the user profile.
      export PATH="/run/wrappers/bin:$PATH:${home}/.nix-profile/bin:/etc/profiles/per-user/${username}/bin:/run/current-system/sw/bin"
      export GIT_SSH_COMMAND="ssh -o BatchMode=yes"

      log="''${XDG_STATE_HOME:-${home}/.local/state}/auto-update"
      mkdir -p "$log"

      notify() {
        echo "$2"
        notify-send --app-name "System update" --urgency "$1" "System update" "$2" || true
      }

      ${lib.optionalString cfg.homeNetworkOnly ''
        # Only on the home LAN itself. Through the tailnet the cache is still
        # reachable, but then the download is paid for by whatever network
        # the laptop happens to be on.
        if ! ip -4 -o addr show scope global | grep -v tailscale | grep -q ' ${lib.escapeRegex cfg.homeNetworkPrefix}'; then
          echo "not on the home network; skipping"
          exit 0
        fi
        if nmcli -t -f GENERAL.METERED device show 2> /dev/null | grep -q ':yes'; then
          echo "connection is metered; skipping"
          exit 0
        fi
      ''}
      if ! curl -fsS --max-time 15 -o /dev/null "${cacheUrl}/nix-cache-info"; then
        echo "cache unreachable; skipping"
        exit 0
      fi

      cd ${dotfiles}
      before=$(git rev-parse HEAD)

      in_sync() {
        git fetch --quiet origin main \
          && [ -z "$(git status --porcelain)" ] \
          && [ "$(git branch --show-current)" = main ] \
          && [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
      }

      if ! git fetch --quiet origin main; then
        notify normal "Could not reach GitHub to pull the dotfiles. Nothing was changed."
        exit 1
      fi
      pushed_local_work=false
      if [ -z "$(git status --porcelain)" ] && [ "$(git branch --show-current)" = main ] \
        && git merge-base --is-ancestor HEAD origin/main; then
        git merge --quiet --ff-only origin/main
      else
        # Uncommitted work, or commits main does not have.
        echo "local dotfiles work found; starting a Claude session to commit, merge and push it"
        timeout 30m claude --print --dangerously-skip-permissions \
          "Load the dotfiles-sync skill and follow it. This is the daily automatic run on host ${hostName}; nobody is watching, so do not ask questions." \
          > "$log/sync.log" 2>&1 || true
        if ! in_sync; then
          notify critical "Your local dotfiles changes could not be committed and pushed automatically, so the system was not updated. Details: $log/sync.log"
          exit 1
        fi
        pushed_local_work=true
      fi

      if [ "$(git rev-parse HEAD)" = "$before" ]; then
        echo "nothing new on main"
        exit 0
      fi

      # --max-jobs 0: fetch, never build. Main only moves once the homelab has
      # built it, so this fails only for work the homelab has not seen yet.
      if ! nh os switch ${dotfiles} --hostname ${hostName} --no-nom --max-jobs 0 > "$log/rebuild.log" 2>&1; then
        if $pushed_local_work; then
          notify low "Local dotfiles changes were committed and pushed. They are not built yet, so the system update waits for tonight's build."
          exit 0
        fi
        notify critical "The update was pulled but not applied: part of it is missing from the cache, or it failed to activate. Details: $log/rebuild.log"
        exit 1
      fi

      if [ "$(readlink -f /run/booted-system/kernel)" != "$(readlink -f /run/current-system/kernel)" ] \
        || [ "$(readlink -f /run/booted-system/initrd)" != "$(readlink -f /run/current-system/initrd)" ]; then
        notify critical "Updated. Restart when convenient: the new kernel is not running yet."
      else
        notify low "Updated."
      fi
    '';
  };
in
{
  options.autoUpdate = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Pull the dotfiles and switch to the system the homelab built, once a day.";
    };
    homeNetworkOnly = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Skip the run unless this machine has an address on the home LAN and the connection is not metered.";
    };
    homeNetworkPrefix = lib.mkOption {
      type = lib.types.str;
      default = "192.168.50.";
      description = "IPv4 prefix that identifies the home LAN.";
    };
    time = lib.mkOption {
      type = lib.types.str;
      default = "06:00";
      description = "When to run. The nightly build starts at 03:00.";
    };
  };

  config = lib.mkMerge [
    {
      # Trusted on every host that imports this, enabled or not, so a manual
      # `rebuild` also pulls from the LAN. Harmonia advertises priority 20,
      # ahead of cache.nixos.org's 40.
      nix.settings = {
        substituters = [ cacheUrl ];
        trusted-public-keys = [ cacheKey ];
        # Away from home with the VPN down the cache does not answer; give up
        # on it quickly instead of stalling every Nix command.
        connect-timeout = 5;
      };

      # The build server itself, for `--store ssh-ng://nix-builder`. Only the
      # PC's key is authorized there (homelab repo:
      # kubernetes/homelab/config/nix-builder/authorized_keys).
      programs.ssh.extraConfig = ''
        Host nix-builder
          Hostname 192.168.50.100
          Port 2222
          User root
      '';
      programs.ssh.knownHosts.nix-builder = {
        hostNames = [ "[192.168.50.100]:2222" ];
        publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICZXiwXcb7cE0HJ5xwjWf6SqL3WFRvnItFstj2rKFmIv";
      };
    }

    (lib.mkIf cfg.enable {
      environment.systemPackages = [ updateScript ];

      # A user unit, not a system one: it works in the user's checkout with
      # the user's SSH key and Claude login, and it can reach the desktop to
      # notify. nh elevates through passwordless sudo for the activation.
      # NixOS does not restart user units on a switch, so the job survives
      # its own update.
      systemd.user.services.auto-update = {
        description = "Pull the dotfiles and switch to the system built by the homelab";
        unitConfig = {
          # Never on battery. A desktop has none and always passes.
          ConditionACPower = true;
          ConditionUser = username;
        };
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe updateScript;
        };
      };

      systemd.user.timers.auto-update = {
        wantedBy = [ "timers.target" ];
        unitConfig.ConditionUser = username;
        timerConfig = {
          OnCalendar = cfg.time;
          # Asleep or off at that hour: run once after the next wake-up.
          Persistent = true;
          RandomizedDelaySec = "5m";
        };
      };
    })
  ];
}
