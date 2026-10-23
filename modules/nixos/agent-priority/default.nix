# The pc is Erik's; agents get what he leaves over. Short builds and tests run
# here (fast CPU); long jobs (~10+ minutes) go to the homelab with `heavy`
# (Erik, 2026-10-21: "of course you can compile things locally ... just if this
# takes 10 min, consider offloading"). Twice that
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
# - `nix` from an agent serializes whole-system evaluations under one lock;
#   `rebuild` (nixos-remote-switch) adds deploy guards, evaluates here and
#   activates (`--remote`: on the builder). The nix daemon builds at idle
#   priority with disk caps, and anything not cached is built on the homelab.
# - Docker containers get per-container caps.
# - No disk swap: only zram, so a runaway is killed instead of thrashing.
# - lag-guard kills agent jobs that stay at the CPU budget for 5+ minutes,
#   emulators over 15 minutes, and the biggest job when Erik's desktop
#   stalls, telling the agent to re-run it with `heavy`.
# - Long jobs go to the homelab worker with `heavy` (../../home-manager/heavy).
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
      pkgs.util-linux
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
      config.nix.package # the real nix, ahead of the agent wrapper
      pkgs.git
      nixRemote
      pkgs.nvd
      pkgs.coreutils
      pkgs.util-linux # flock
    ];
    runtimeEnv.HOST = config.networking.hostName;
    text = builtins.readFile ./nixos-remote-switch.sh;
  };

  # Agents' nix, nh and nixos-rebuild (shadow the real ones on PATH): from the
  # agent slice, evaluation and builds run on the homelab builder.
  agentNix = lib.hiPrio (
    pkgs.writeShellScriptBin "nix" (
      builtins.replaceStrings [ "@realNix@" "@flock@" ] [ realNix "${pkgs.util-linux}/bin/flock" ] (
        builtins.readFile ./agent-nix.sh
      )
    )
  );
  agentRebuild =
    name: real:
    lib.hiPrio (
      pkgs.writeShellScriptBin name (
        builtins.replaceStrings [ "@real@" "@name@" ] [ real name ] (builtins.readFile ./agent-rebuild.sh)
      )
    );

  lagGuard = pkgs.writeShellApplication {
    name = "lag-guard";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
      pkgs.gawk
      pkgs.procps
      pkgs.util-linux
      pkgs.gnugrep
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
          (agentRebuild "nh" (lib.getExe config.programs.nh.package))
          (agentRebuild "nixos-rebuild" "${config.system.build.nixos-rebuild}/bin/nixos-rebuild")
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
            # And never more than 4 of the 16 threads, whatever is idle.
            CPUQuota = "400%";
            MemoryHigh = cfg.memoryHigh;
            MemoryMax = cfg.memoryMax;
            # Room to swap idle memory into zram (the first swap tier, in RAM).
            # With 2 GB the slice sat at MemoryHigh with its swap full and the
            # kernel evicted the agents' program code instead, which they
            # re-read from disk (2026-10-23: tsc, rustc, nix major-faulting,
            # system IO 35-75 % for 20 minutes). lag-guard kills the biggest job
            # when the slice still stalls on memory.
            MemorySwapMax = "8G";
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
          CPUQuota = "400%";
        }
        // ioCaps "200M" "100M";

        # Every Docker container (agents' test stacks, the vLLM TTS that
        # llama-swap starts) is a docker-<id>.scope; a prefix drop-in caps
        # each one without restarting dockerd.
        # (environment.etc cannot add to etc/systemd/system, a store symlink.)
        systemd.packages = [
          (pkgs.writeTextDir "etc/systemd/system/docker-.scope.d/50-agent-priority.conf" ''
            [Scope]
            CPUWeight=20
            IOWeight=10
            IOReadBandwidthMax=${systemDisk} 150M
            IOWriteBandwidthMax=${systemDisk} 60M
            MemoryHigh=8G
            MemoryMax=10G
            MemorySwapMax=1G
          '')
        ];

        # Swap tiers: zram first (priority 5, ../default.nix), then the 64 GB disk
        # partition as overflow (priority 1). Zram alone (2026-10-21 to 10-23)
        # froze the desktop when it filled: no OOM kill, just thrashing
        # (2026-10-23 01:35). Slow disk swap beats a frozen desktop; earlyoom
        # (../default.nix) and the agent caps keep it from getting that far.
        # Agents can use at most 8 GB of swap, which zram takes first.
        swapDevices = lib.mkForce [
          {
            device = "/dev/disk/by-uuid/ee5834a1-13be-4ef6-997d-9fb38216e4c9";
            priority = 1;
          }
        ];
        # The partition has the Linux-swap GPT type; with systemd-gpt-auto-
        # generator it was also activated a second time under another name.
        # NixOS mounts everything from fstab, so the generator stays off.
        boot.kernelParams = [ "systemd.gpt_auto=0" ];

        systemd.oomd.enable = true;

        systemd.services.lag-guard = {
          description = "Stop agents' heavy jobs when the pc keeps stalling";
          wantedBy = [ "multi-user.target" ];
          environment.HOME = "/root"; # notify-erik needs it
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
