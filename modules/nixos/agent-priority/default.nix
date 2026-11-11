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
# - `xdg-open` from an agent opens the agent's Chromium (wrapper).
# - `systemctl` from an agent cannot stop or restart t3code.service (wrapper).
# - `nix` from an agent serializes whole-system evaluations under one lock;
#   `rebuild` (nixos-remote-switch) adds deploy guards, evaluates here and
#   activates (`--remote`: on the builder). The nix daemon builds at idle
#   priority with disk caps, and anything not cached is built on the homelab.
# - Docker containers get per-container caps.
# - Swap: zram first, then a disk partition as overflow (see swapDevices).
# - `agent-max on` (max mode, only while Erik is away) raises the agent caps
#   to 14 CPUs and 22/25 GB, lifts lag-guard's CPU and emulator limits and
#   leaves its stall checks only for a real hang (memory 50% / IO 80% full
#   for a minute; swap-in from the idle desktop is not one); it
#   turns off when Erik touches a keyboard or mouse, or after 12 hours.
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
      # Services go to app-t3code-jobs.slice, not the agent's own slice: T3
      # Code stops that one when its server restarts, which killed the
      # nightly's build on 2026-10-23. Same caps (app-t3code.slice).
      exec ${realSystemdRun} --slice=app-t3code-jobs.slice --nice=10 --property=OOMScoreAdjust=1000 "$@"
    ''
  );

  # Shadows systemctl: agents may not stop or restart the T3 Code server. A
  # restart kills every running agent of every thread, background subagents
  # included (2026-11-09: three hand restarts after fork deploys in two hours
  # killed 10-15 multi-hour subagents each time). The server goes onto a new
  # build through t3code-restart-when-idle (hosts/pc/home.nix). Matches the
  # agent and job slices, so `systemd-run ... systemctl` and `t3 service
  # restart`/`t3 doctor` from an agent are caught too; Erik's T3 terminals and
  # everything outside app-t3code.slice get the real systemctl.
  agentSystemctl = lib.hiPrio (
    pkgs.writeShellScriptBin "systemctl" ''
      real=${config.systemd.package}/bin/systemctl
      case "$(cat /proc/self/cgroup 2>/dev/null)" in
        */t3code-terminal-*) exec "$real" "$@" ;;
        */app-t3code.slice/*) ;;
        *) exec "$real" "$@" ;;
      esac
      verb="" t3=0
      for arg in "$@"; do
        case "$arg" in
          stop | restart | try-restart | reload-or-restart | try-reload-or-restart | kill | freeze | disable | mask | isolate) verb=$arg ;;
          t3code | t3code.service) t3=1 ;;
        esac
      done
      if [ -n "$verb" ] && [ "$t3" = 1 ]; then
        echo "systemctl (agent guard): agents may not $verb t3code.service: it kills every running agent, background subagents of other threads included (Erik, 2026-11-09)." >&2
        echo "A rebuild that changes the server queues t3code-restart-when-idle.service, which restarts it once no agent is working; your own turn counts, so it happens after you finish. Queue it by hand: systemctl --user start --no-block t3code-restart-when-idle.service. Why it waits: journalctl --user -u t3code-restart-when-idle." >&2
        exit 1
      fi
      exec "$real" "$@"
    ''
  );

  # Shadows xdg-open too: from an agent session it opens the agent's Chromium, not
  # whatever Erik's default handler is (his running Firefox, on his monitor).
  agentXdgOpen = lib.hiPrio (
    pkgs.writeShellScriptBin "xdg-open" ''
      case "$(cat /proc/self/cgroup 2>/dev/null)" in
        */app-t3code-agents.slice/* | */app-t3code-jobs.slice/*)
          # Only the PC has an agent seat.
          if [ -x "$HOME/.nix-profile/bin/agent-open" ]; then
            exec "$HOME/.nix-profile/bin/agent-open" "$@"
          fi
          ;;
      esac
      exec ${pkgs.xdg-utils}/bin/xdg-open "$@"
    ''
  );

  agentJob = pkgs.writeShellApplication {
    name = "agent-job";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnused
      config.systemd.package
    ];
    text = builtins.replaceStrings [ "@systemdRun@" ] [ realSystemdRun ] (
      builtins.readFile ./agent-job.sh
    );
  };

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

  # Max mode (agent-max.sh): Erik away, agents may use most of the pc.
  agentMax = pkgs.writeShellApplication {
    name = "agent-max";
    runtimeInputs = [
      pkgs.coreutils
      config.systemd.package
      "/run/current-system/sw" # notify-erik
    ];
    text =
      builtins.replaceStrings
        [
          "@defaultHours@"
          "@maxCpu@"
          "@maxMemoryHigh@"
          "@maxMemoryMax@"
          "@cpu@"
          "@memoryHigh@"
          "@memoryMax@"
        ]
        [
          (toString cfg.maxMode.hours)
          cfg.maxMode.cpuQuota
          cfg.maxMode.memoryHigh
          cfg.maxMode.memoryMax
          cfg.cpuQuota
          cfg.memoryHigh
          cfg.memoryMax
        ]
        (builtins.readFile ./agent-max.sh);
  };
  agentMaxWatch = pkgs.writers.writePython3 "agent-max-watch" {
    libraries = [ pkgs.python3Packages.evdev ];
    flakeIgnore = [ "E501" ];
  } (builtins.readFile ./agent-max-watch.py);

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
    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "400%";
      description = "All agents together never use more CPU than this (400% = 4 of the 16 threads).";
    };
    maxMode = {
      cpuQuota = lib.mkOption {
        type = lib.types.str;
        default = "1400%";
        description = "Agent CPU cap in max mode (`agent-max on`): 14 of 16 threads, 2 left for the desktop and T3 Code.";
      };
      memoryHigh = lib.mkOption {
        type = lib.types.str;
        default = "22G";
        description = "Agent MemoryHigh in max mode.";
      };
      memoryMax = lib.mkOption {
        type = lib.types.str;
        default = "25G";
        description = "Agent MemoryMax in max mode.";
      };
      hours = lib.mkOption {
        type = lib.types.ints.positive;
        default = 12;
        description = "Max mode turns itself off after this many hours.";
      };
    };
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
          agentSystemctl
          agentXdgOpen
          agentNix
          (agentRebuild "nh" (lib.getExe config.programs.nh.package))
          (agentRebuild "nixos-rebuild" "${config.system.build.nixos-rebuild}/bin/nixos-rebuild")
          nixRemote
          nixosRemoteSwitch
          agentJob
          agentMax
        ];

        # Turns max mode off when Erik is back (physical keyboard or mouse) or
        # its time is up. Started by `agent-max on`, not at login.
        systemd.user.services.agent-max-watch = {
          description = "Turn agent max mode off when Erik is back at the pc";
          path = [ agentMax ];
          serviceConfig = {
            ExecStart = agentMaxWatch;
            Restart = "on-failure";
            RestartSec = 5;
          };
        };

        # The user manager gets the io controller too, so the agent slice's
        # disk caps apply (the default delegates only cpu, memory and pids).
        systemd.services."user@".serviceConfig.Delegate = "cpu cpuset io memory pids";

        # Agent scratch ages out instead of filling the disk (2026-11-07: free
        # space fell from 297G to 118G overnight). /tmp is on disk here and
        # agents leave GBs in it (Claude scratchpads, sandboxes, test runs);
        # systemd's own tmp.conf keeps it 10 days. 00-nixos.conf sorts first,
        # so this line wins over that one.
        # 2026-11-10: 3d was still too slow (agents wrote 100G in hours, / fell
        # to 5% free), and the cleaner only ran daily. Idle for 1d goes, and the
        # cleaner runs hourly (system and user); active files stay (age counts
        # from last use).
        systemd.tmpfiles.rules = [ "q /tmp 1777 root root 1d" ];
        systemd.timers.systemd-tmpfiles-clean.timerConfig.OnUnitActiveSec = lib.mkForce "1h";
        systemd.user.timers.systemd-tmpfiles-clean.timerConfig.OnUnitActiveSec = lib.mkForce "1h";
        # Every agent worktree builds its own cargo target/ (4-7G each) and
        # nothing removes it once the run is done: 18 Claude workflow
        # worktrees in wasm-box held 88G. Build output idle for 2 days goes.
        systemd.user.tmpfiles.rules = [
          # Disabled 2026-11-11: wasm-box lanes now make `target` a symlink to
          # /mnt/data/wbox-target/<lane>, and systemd-tmpfiles aborts with
          # "unsafe path transition ... -> /" (exit 73) on such a symlink, which
          # failed systemd-tmpfiles-setup and nixos-activation (user) at boot.
          # The data is covered by the /mnt/data rules below, and Erik wants
          # build caches kept anyway.
          # "e %h/projects/*/.claude/worktrees/*/target - - - 6h"
          # "e %h/.t3/worktrees/*/*/target - - - 6h"
          # wasm-box builds now write to /mnt/data/wbox-target/<worktree>
          # (2026-11-10, to keep / free); idle for 3 days goes, active builds
          # keep their files fresh. DiskAlmostFull/DiskFillingUp cover /mnt/data.
          # 3d -> 1d (2026-11-11): the dir grew 21G -> 53G in 15 h while only
          # idle for less than 3d, so 3d bounded nothing; cargo output is
          # rebuildable and sccache-backed (sccache is off since 2026-11-11,
          # modules/home-manager/rust.nix; these dirs are the only cache now).
          # 1d -> 14d (2026-11-11), Erik: "do not get rid of any caching of
          # build artifacts to appease the disk limits; it is fine that we go
          # closer to 97%; if you need space use it all". The cargo/Go caches
          # stay warm; only worktrees abandoned for two weeks go. The /mnt/data
          # alerts now fire at 95% used / a 97% exhaustion forecast (homelab
          # prometheus rules), not 80%.
          "e /mnt/data/wbox-target - - - 14d"
          # 2026-11-11 14:00: after the 12:16 cleanup /mnt/data lost 70G in 2 h,
          # 26G of it Go build caches under wbox-src/T6/cache (regrown by the
          # lanes). Not gomodcache: Go makes it read-only, tmpfiles (user)
          # cannot unlink inside it; the owner sets GOFLAGS=-modcacherw and one
          # shared modcache. 2d -> 14d the same day, per Erik above.
          "e /mnt/data/wbox-src/*/cache/gocache - - - 14d"
          "e /mnt/data/wbox-src/*/gocache - - - 14d"
        ];

        systemd.user.slices.app-t3code = {
          description = "T3 Code agents, behind Erik's own apps";
          sliceConfig = {
            # cpu.idle: agents get the CPU Erik's apps leave unused, and his
            # input always preempts them.
            CPUWeight = "idle";
            # And never more than 4 of the 16 threads, whatever is idle.
            # `agent-max on` raises this, MemoryHigh and MemoryMax at runtime
            # while Erik is away (systemctl --user set-property --runtime).
            CPUQuota = cfg.cpuQuota;
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

        # Long builds, `heavy` runs and agents' `systemd-run --user` services
        # (agent-job.sh): under app-t3code.slice's caps, but not in the agent
        # slices T3 Code stops when its server restarts.
        systemd.user.slices.app-t3code-jobs.description = "Agent jobs that outlive their session";

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
