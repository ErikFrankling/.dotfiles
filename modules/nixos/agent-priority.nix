# Agents may use this machine, but always behind Erik. On 2026-10-21 agent
# work (an APK build with ~18 clang++, a local nix build, two emulators, tsgo,
# Playwright) pushed the load to 69 and 45 GB into swap, and the desktop froze.
#
# - T3 Code starts every provider session (claude, codex, opencode, grok,
#   cursor) in a scope under app-t3code-agents.slice (fork,
#   apps/server/src/process/agentScope.ts). It sets loose memory limits on that
#   slice at runtime, so the real limits go on its parent, app-t3code.slice,
#   which T3 never touches: the CPU only when Erik's apps leave it idle, a
#   memory ceiling that leaves him well over half the RAM, and systemd-oomd
#   kills an agent scope that keeps thrashing.
# - Agents used to escape that with `systemd-run --user` (the APK build ran as
#   zt-build-A.service in app.slice, next to Erik's apps). A systemd-run
#   wrapper puts anything started from inside the agent slice back into the
#   caller's slice, niced and first in line for the OOM killer.
# - The nix daemon builds at idle CPU priority in a memory-capped service, and
#   anything not in a cache is built on the homelab builder instead of here.
#
# Rules for agents: modules/home-manager/machines/skill/machines/SKILL.md.
{
  config,
  lib,
  pkgs,
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
in
{
  options.agentPriority = {
    enable = lib.mkEnableOption "keeping agent work and Nix builds behind the desktop";
    memoryHigh = lib.mkOption {
      type = lib.types.str;
      default = "12G";
      description = "All agents together are throttled (reclaimed into swap) above this.";
    };
    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "15G";
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
        environment.systemPackages = [ agentSystemdRun ];

        systemd.user.slices.app-t3code = {
          description = "T3 Code agents, behind Erik's own apps";
          sliceConfig = {
            # cpu.idle: agents get the CPU Erik's apps leave unused, and his
            # input always preempts them.
            CPUWeight = "idle";
            MemoryHigh = cfg.memoryHigh;
            MemoryMax = cfg.memoryMax;
            # Agents may not fill the 79 GB swap; past this they reclaim their
            # own memory or get killed, instead of swapping the desktop out.
            MemorySwapMax = "6G";
            # Sustained thrashing inside the agents (30 s above the limit)
            # kills the agent scope that reclaims the most.
            ManagedOOMMemoryPressure = "kill";
            ManagedOOMMemoryPressureLimit = "50%";
          };
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
          MemorySwapMax = "4G";
          OOMScoreAdjust = 500;
        };

        systemd.oomd.enable = true;
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
