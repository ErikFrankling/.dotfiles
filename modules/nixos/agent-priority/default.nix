# The pc is Erik's; agents get what he leaves over, and heavy agent work
# runs on the homelab (Erik, 2026-10-21: "use the home lab for long running cpu
# heavy stuff, i need my pc not to lag, idc if it takes long"). Twice that
# night the desktop froze: first load 69 and 45 GB in swap (an APK build with
# ~18 clang++, a local nix build, two emulators), then at 05:20, with CPU
# already idle-weighted, IO 50% "full" from swap and a local evaluation of the
# pc system. The disk is a DRAM-less Kingston NV3 that stalls under writes.
#
# - T3 Code starts every provider session (claude, codex, opencode, grok,
#   cursor) in a scope under app-t3code-agents.slice (fork,
#   apps/server/src/process/agentScope.ts). It sets loose memory limits on that
#   slice at runtime, so the real limits go on its parent, app-t3code.slice,
#   which T3 never touches: idle CPU, small memory and swap caps, hard disk
#   bandwidth caps, and systemd-oomd.
# - `systemd-run --user` from an agent stays in the agent slice (wrapper).
# - `nix` from an agent sends NixOS/Home Manager evaluations to the homelab
#   builder (nix-remote), and `rebuild` on this host evaluates and builds
#   there too (nixos-remote-switch). The nix daemon builds at idle priority
#   with disk caps, and anything not cached is built on the homelab.
# - Docker containers get per-container caps.
# - No disk swap: only zram, so a runaway is killed instead of thrashing.
# - lag-guard stops agent heavy jobs, emulators first, when the pc keeps
#   stalling, and notifies Erik.
# - Heavy jobs go to the homelab worker with `heavy` (../../home-manager/heavy).
#
# Rules for agents: modules/home-manager/machines/skill/machines/SKILL.md.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  cfg = config.agentPriority;
  realSystemdRun = "${config.systemd.package}/bin/systemd-run";

  # Shadows systemd-run on PATH. Outside the agent slice it is the real one.
  agentSystemdRun = lib.hiPrio (
    pkgs.writeShellScriptBin "systemd-run" ''
      case "$(cat /proc/self/cgroup 2>/dev/null)" in
        */app-t3code.slice/*) ;;
        *) exec ${realSystemdRun} "$@" ;;
      esac
      user=0 chosen=0 scope=0
      for arg in "$@"; do
        case "$arg" in
          --) break ;;
          --user) user=1 ;;
          --slice | --slice=* | --slice-inherit) chosen=1 ;;
          --scope) scope=1 ;;
        esac
      done
      if [ "$user" = 0 ] || [ "$chosen" = 1 ]; then
        exec ${realSystemdRun} "$@"
      fi
      # A scope runs this process; a service is forked by the user manager.
      { echo 1000 >/proc/self/oom_score_adj; } 2>/dev/null
      if [ "$scope" = 1 ]; then
        exec ${realSystemdRun} --slice-inherit --nice=10 "$@"
      fi
      exec ${realSystemdRun} --slice-inherit --nice=10 --property=OOMScoreAdjust=1000 "$@"
    ''
  );

  realNix = "${config.nix.package}/bin/nix";

  nixRemote = pkgs.writeShellApplication {
    name = "nix-remote";
    runtimeInputs = [
      config.nix.package
      pkgs.jq
      pkgs.openssh
      pkgs.coreutils
    ];
    text = builtins.readFile ./nix-remote.sh;
  };

  nixosRemoteSwitch = pkgs.writeShellApplication {
    name = "nixos-remote-switch";
    runtimeInputs = [
      nixRemote
      pkgs.nvd
      pkgs.coreutils
    ];
    runtimeEnv.HOST = config.networking.hostName;
    text = builtins.readFile ./nixos-remote-switch.sh;
  };

  # Shadows nix on PATH. From inside the agent slice, evaluating a NixOS or
  # Home Manager configuration (3-4 GB, minutes of disk IO) goes to the
  # homelab builder instead.
  agentNix = lib.hiPrio (
    pkgs.writeShellScriptBin "nix" ''
      case "$(cat /proc/self/cgroup 2>/dev/null)" in
        */app-t3code.slice/*) ;;
        *) exec ${realNix} "$@" ;;
      esac
      [ -n "''${NIX_LOCAL_EVAL:-}" ] && exec ${realNix} "$@"
      case " $* " in
        *" --store "* | *" --eval-store "*) exec ${realNix} "$@" ;;
        *nixosConfigurations* | *homeConfigurations*) ;;
        *) exec ${realNix} "$@" ;;
      esac
      sub=
      for arg in "$@"; do
        case "$arg" in -*) ;; *) sub=$arg; break ;; esac
      done
      case "$sub" in
        build | eval | path-info | derivation | why-depends | log)
          echo "nix: NixOS evaluations do not run on the pc; running this on the homelab builder (nix-remote)." >&2
          exec ${lib.getExe nixRemote} "$@"
          ;;
        *)
          echo "nix: '$sub' on a NixOS configuration would evaluate it on the pc. Use nix-remote build/eval, or rebuild." >&2
          exit 1
          ;;
      esac
    ''
  );

  lagGuard = pkgs.writeShellApplication {
    name = "lag-guard";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.procps
      pkgs.util-linux
      "/run/current-system/sw" # notify-erik
    ];
    text = builtins.readFile ./lag-guard.sh;
  };

  # The system disk. io.max needs the whole device, not a partition.
  systemDisk = "/dev/disk/by-id/nvme-KINGSTON_SNV3S2000G_50026B7384466B3F";
  ioCaps = read: write: {
    IOReadBandwidthMax = "${systemDisk} ${read}";
    IOWriteBandwidthMax = "${systemDisk} ${write}";
  };
in
{
  options.agentPriority = {
    enable = lib.mkEnableOption "keeping agent work and Nix builds behind the desktop";
    memoryHigh = lib.mkOption {
      type = lib.types.str;
      default = "9G";
      description = "All agents together are throttled above this. Heavy work goes to the homelab.";
    };
    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "11G";
      description = "All agents together never use more RAM than this; the kernel kills one first.";
    };
    remoteBuilder.sshKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Private key the nix daemon (root) uses to reach the homelab builder.
        It must be in the homelab repo's config/nix-builder/authorized_keys.
        Null keeps building local.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      {
        environment.systemPackages = [
          agentSystemdRun
          agentNix
          nixRemote
          nixosRemoteSwitch
        ];

        # The user manager gets the io controller too, so the agent slice's
        # disk caps apply (the default delegates only cpu, memory and pids).
        systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";

        systemd.user.slices.app-t3code = {
          description = "T3 Code agents, behind Erik's own apps";
          sliceConfig = {
            # cpu.idle: agents get the CPU Erik's apps leave unused, and his
            # input always preempts them.
            CPUWeight = "idle";
            MemoryHigh = cfg.memoryHigh;
            MemoryMax = cfg.memoryMax;
            # Hardly any swap: past their RAM, agents get killed instead of
            # thrashing the disk the desktop needs.
            MemorySwapMax = "2G";
            # Sustained thrashing inside the agents (30 s above the limit)
            # kills the agent scope that reclaims the most.
            ManagedOOMMemoryPressure = "kill";
            ManagedOOMMemoryPressureLimit = "50%";
            # Hard disk caps: the NV3 stalls every reader once something
            # writes flat out. IOWeight only matters under BFQ/iocost.
            IOWeight = 10;
          }
          // ioCaps "150M" "60M";
        };

        # Builds wait for idle CPU and disk, and stay small. `cores` is per job.
        nix.daemonCPUSchedPolicy = "idle";
        nix.daemonIOSchedClass = "idle";
        nix.settings = {
          max-jobs = 4;
          cores = 4;
        };
        systemd.services.nix-daemon.serviceConfig = {
          MemoryHigh = "8G";
          MemoryMax = "12G";
          MemorySwapMax = "2G";
          OOMScoreAdjust = 500;
          IOWeight = 10;
        }
        // ioCaps "200M" "100M";

        # Every Docker container (agents' test stacks, the vLLM TTS that
        # llama-swap starts) is a docker-<id>.scope; a prefix drop-in caps
        # each one without restarting dockerd.
        environment.etc."systemd/system/docker-.scope.d/50-agent-priority.conf".text = ''
          [Scope]
          CPUWeight=20
          IOWeight=10
          IOReadBandwidthMax=${systemDisk} 150M
          IOWriteBandwidthMax=${systemDisk} 60M
          MemoryHigh=8G
          MemoryMax=10G
          MemorySwapMax=1G
        '';

        # zram only (zramSwap in ../default.nix, half the RAM). The 64 GB disk
        # partition let runaways thrash for minutes instead of being killed.
        # Disabled until the running system can swapoff the partition (9.5 GB
        # were on it at the first switch); enabled in the next step.
        # swapDevices = lib.mkForce [ ];

        systemd.oomd.enable = true;

        systemd.services.lag-guard = {
          description = "Stop agents' heavy jobs when the pc keeps stalling";
          wantedBy = [ "multi-user.target" ];
          serviceConfig = {
            ExecStart = lib.getExe lagGuard;
            Restart = "always";
            RestartSec = 5;
            # It has to run when everything else is starved.
            Nice = -5;
            CPUWeight = 1000;
            IOWeight = 1000;
            MemoryMin = "32M";
            OOMScoreAdjust = -900;
          };
        };
      }

      (lib.mkIf (cfg.remoteBuilder.sshKey != null) {
        # Whatever no cache has is built on the homelab (slower, but not on
        # the desktop). Derivations marked preferLocalBuild (config files,
        # wrappers) still build here. If the builder does not answer, Nix
        # falls back to building locally.
        nix.distributedBuilds = true;
        nix.buildMachines = [
          {
            # `Host nix-builder` in /etc/ssh/ssh_config (auto-update.nix).
            hostName = "nix-builder";
            protocol = "ssh-ng";
            sshUser = "root";
            inherit (cfg.remoteBuilder) sshKey;
            system = "x86_64-linux";
            # More slots than the builder runs at once (its max-jobs is 4): extra
            # jobs queue there instead of falling back to a local build.
            maxJobs = 8;
            speedFactor = 2;
            supportedFeatures = [
              "nixos-test"
              "benchmark"
              "big-parallel"
            ];
          }
        ];
        # The builder fetches dependencies from the caches itself instead of
        # receiving them from this machine.
        nix.settings.builders-use-substitutes = true;
      })
    ]
  );
}
