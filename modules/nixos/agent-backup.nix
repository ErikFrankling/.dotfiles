# Nightly off-site backup of every agent's sessions (Claude Code, Codex,
# OpenCode, Grok, omp, T3 Code, ~/agent-traces) to Cloudflare R2 with the
# upstream restic module. Raw files, never a format-specific exporter, so a
# new session format cannot break it. Snapshots are never pruned (Erik,
# 2026-11-12: agent traces are never deleted).
#
# Live SQLite databases (OpenCode, Codex, T3, omp, Grok) are copied with
# SQLite's own .backup first; a plain file copy of a database that is being
# written can be corrupt. The copies land under /var/lib/agent-backup/sqlite
# and the originals are excluded.
#
# Alerts (notify-erik): the backup unit failing, no successful backup for 36
# hours, and (pc) an agent's session store that stopped growing, which is what
# happens when an agent moves its storage (OpenCode moved from JSON files to
# opencode.db once). Restore: `restic-agent-traces snapshots`, `... restore`.
#
# Bucket `agent-traces` in Erik's own Cloudflare account (not Patrik's), one
# repository per host. R2 key and restic password: secrets/agent-backup.yaml.
{
  config,
  lib,
  pkgs,
  username,
  ...
}:

let
  home = "/home/${username}";
  host = config.networking.hostName;
  state = "/var/lib/agent-backup";
  stage = "${state}/sqlite";

  sources = [
    "${home}/.claude/projects"
    "${home}/.claude/history.jsonl"
    "${home}/.claude_2"
    "${home}/.codex"
    "${home}/.codex-t3"
    "${home}/.local/share/opencode"
    "${home}/.grok"
    "${home}/.omp"
    "${home}/.t3/userdata"
    "${home}/agent-traces"
  ];

  # Stores that grow every day the agent is used: name, folder, days of
  # silence before it is reported. Only the pc, where they are all in use.
  watched = lib.optionals (host == "pc") [
    "Claude Code|${home}/.claude/projects|7"
    "Codex|${home}/.codex/sessions|7"
    "OpenCode|${home}/.local/share/opencode|14"
    "Grok|${home}/.grok/sessions|14"
    "T3 Code|${home}/.t3/userdata|3"
  ];

  prepare = pkgs.writeShellApplication {
    name = "agent-backup-prepare";
    runtimeInputs = [
      pkgs.sqlite
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      rm -rf ${stage}
      mkdir -p ${stage}
      for src in "$@"; do
        [ -d "$src" ] || continue
        find "$src" -type f \( -name '*.sqlite' -o -name '*.sqlite3' -o -name '*.db' \) -print0 |
          while IFS= read -r -d "" f; do
            dst="${stage}$f.backup"
            mkdir -p "$(dirname "$dst")"
            if [ "$(head -c 15 "$f")" = "SQLite format 3" ]; then
              sqlite3 "$f" ".timeout 60000" ".backup \"$dst\"" && continue
              echo "WARNING: sqlite .backup failed for $f, copying the raw files" >&2
            fi
            cp "$f" "$dst"
            for side in wal shm journal; do
              [ ! -f "$f-$side" ] || cp "$f-$side" "$dst-$side"
            done
          done
      done
    '';
  };

  existing = pkgs.writeShellScript "agent-backup-paths" ''
    for p in ${lib.escapeShellArgs sources} ${stage}; do
      [ -e "$p" ] && echo "$p"
    done
    exit 0
  '';

  check = pkgs.writeShellApplication {
    name = "agent-backup-check";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.findutils
    ];
    text = ''
      now=$(date +%s)
      problems=()
      if [ -f ${state}/last-success ]; then
        last=$(stat -c %Y ${state}/last-success)
        status="last backup $(date -d @"$last" '+%F %H:%M')"
      else
        last=0
        status="no successful backup yet"
      fi
      # A laptop that was off has had no chance yet; the timer catches up at boot.
      if [ $((now - last)) -gt $((36 * 3600)) ] && [ "$(cut -d. -f1 /proc/uptime)" -gt $((3 * 3600)) ]; then
        problems+=("$status (over 36 h): journalctl -u restic-backups-agent-traces")
      fi
      for entry in ${lib.escapeShellArgs watched}; do
        IFS='|' read -r name dir days <<< "$entry"
        newest=$(find "$dir" -type f -printf '%T@\n' 2>/dev/null | sort -n | tail -n 1 | cut -d. -f1) || true
        if [ -z "$newest" ] || [ $((now - newest)) -gt $((days * 86400)) ]; then
          problems+=("$name: nothing new in $dir for over $days days. If you used $name since, it stores its sessions somewhere else now and that is not backed up.")
        fi
      done
      if [ ''${#problems[@]} -eq 0 ]; then
        echo "ok, $status" > ${state}/status
      else
        printf 'PROBLEM: %s\n' "''${problems[@]}" > ${state}/status
        /run/current-system/sw/bin/notify-erik -p high -t "Agent session backup on ${host}" "$(printf '%s\n' "''${problems[@]}")"
      fi
      cat ${state}/status
    '';
  };

  quiet = {
    Nice = 19;
    IOSchedulingClass = "idle";
    CPUSchedulingPolicy = "idle";
  };
in
{
  sops.secrets.agent-backup-restic-password = {
    sopsFile = ../../secrets/agent-backup.yaml;
    owner = username;
  };
  # AWS_ACCESS_KEY_ID=..., AWS_SECRET_ACCESS_KEY=... and AWS_DEFAULT_REGION=auto
  # of an R2 token that can only read and write the agent-traces bucket.
  sops.secrets.agent-backup-r2-env = {
    sopsFile = ../../secrets/agent-backup.yaml;
    owner = username;
  };

  services.restic.backups.agent-traces = {
    user = username; # as Erik, so SQLite never leaves root-owned -shm files in his folders
    repository = "s3:https://37050018c7c04a0f0fa3909c51303e32.r2.cloudflarestorage.com/agent-traces/${host}";
    passwordFile = config.sops.secrets.agent-backup-restic-password.path;
    environmentFile = config.sops.secrets.agent-backup-r2-env.path;
    initialize = true;
    dynamicFilesFrom = "${existing}";
    backupPrepareCommand = "${lib.getExe prepare} ${lib.escapeShellArgs sources}";
    backupCleanupCommand = "rm -rf ${stage}";
    exclude = [
      # the live databases; their .backup copies under ${stage} are kept
      "*.sqlite"
      "*.sqlite-*"
      "*.sqlite3"
      "*.db"
      "*.db-wal"
      "*.db-shm"
      "*.db-journal"
      # logins and browser profiles
      "auth.json"
      "account.json"
      "mcp-auth.json"
      ".credentials.json"
      "*.lock"
      "${home}/.t3/userdata/secrets"
      "${home}/.t3/userdata/clerk"
      "${home}/.t3/userdata/server-browser"
      "${home}/.codex/browser"
      "${home}/.omp/puppeteer"
      # caches that are downloaded again
      "${home}/.codex/cache"
      "${home}/.claude_2/cache"
      "${home}/.grok/vendor"
    ];
    extraBackupArgs = [ "--tag agents" ];
    # Every night 1% of the stored data is downloaded and verified.
    runCheck = true;
    checkOpts = [ "--read-data-subset=1%" ];
    # pruneOpts stays empty: snapshots are kept forever.
    timerConfig = {
      OnCalendar = "02:15";
      RandomizedDelaySec = "30m";
      Persistent = true;
    };
    inhibitsSleep = true; # the laptop does not suspend mid-upload
    # `restic-agent-traces` (restic with the repository and keys) is on PATH
    # for restores (createWrapper, on by default).
  };

  systemd.services.restic-backups-agent-traces = {
    unitConfig.OnFailure = [ "agent-backup-alert.service" ];
    serviceConfig = quiet // {
      StateDirectory = "agent-backup";
      # 3 = a file vanished or changed while it was read (agents write all
      # the time); the snapshot is still made.
      SuccessExitStatus = 3;
      ExecStartPost = "${pkgs.coreutils}/bin/touch ${state}/last-success";
    };
  };

  systemd.services.agent-backup-alert = {
    description = "Tell Erik the agent session backup failed";
    environment.HOME = home;
    serviceConfig = {
      Type = "oneshot";
      User = username;
      ExecStart = "/run/current-system/sw/bin/notify-erik -p high -t 'Agent session backup on ${host} failed' 'restic-backups-agent-traces failed. journalctl -u restic-backups-agent-traces'";
    };
  };

  systemd.services.agent-backup-check = {
    description = "Check the agent session backup is recent and covers every agent";
    environment.HOME = home;
    serviceConfig = quiet // {
      Type = "oneshot";
      User = username;
      StateDirectory = "agent-backup";
      ExecStart = lib.getExe check;
    };
  };
  systemd.timers.agent-backup-check = {
    wantedBy = [ "timers.target" ];
    timerConfig.OnCalendar = "11:00";
  };
}
